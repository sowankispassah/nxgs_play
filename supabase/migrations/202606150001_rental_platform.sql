create extension if not exists pgcrypto;

do $$ begin
    create type console_state as enum ('available', 'reserved', 'in_session', 'offline', 'maintenance');
exception when duplicate_object then null; end $$;

do $$ begin
    create type reservation_state as enum ('reserved', 'released', 'expired', 'converted');
exception when duplicate_object then null; end $$;

do $$ begin
    create type session_state as enum ('pending', 'active', 'extended', 'expired', 'completed', 'disconnected');
exception when duplicate_object then null; end $$;

do $$ begin
    create type payment_status as enum ('order_created', 'verified', 'failed', 'refunded');
exception when duplicate_object then null; end $$;

do $$ begin
    create type payment_kind as enum ('initial', 'extension');
exception when duplicate_object then null; end $$;

create table if not exists consoles (
    id uuid primary key default gen_random_uuid(),
    name text not null,
    state console_state not null default 'available',
    tailscale_ip inet not null,
    mac_address text,
    registered_host_nickname text,
    remote_play_target text not null default 'PS5',
    last_seen_at timestamptz,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint consoles_remote_play_target_check check (remote_play_target in ('PS4', 'PS5'))
);

create table if not exists pricing (
    id uuid primary key default gen_random_uuid(),
    duration_hours int not null unique,
    amount_paise int not null check (amount_paise > 0),
    currency text not null default 'INR',
    active boolean not null default true,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint pricing_duration_check check (duration_hours in (1, 2, 3, 4))
);

create table if not exists console_reservations (
    id uuid primary key default gen_random_uuid(),
    console_id uuid not null references consoles(id),
    status reservation_state not null default 'reserved',
    expires_at timestamptz not null default now() + interval '10 minutes',
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create table if not exists play_sessions (
    id uuid primary key default gen_random_uuid(),
    reservation_id uuid references console_reservations(id),
    console_id uuid not null references consoles(id),
    status session_state not null default 'pending',
    started_at timestamptz,
    ends_at timestamptz,
    grace_ends_at timestamptz,
    last_heartbeat_at timestamptz,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create table if not exists payments (
    id uuid primary key default gen_random_uuid(),
    reservation_id uuid references console_reservations(id),
    session_id uuid references play_sessions(id),
    console_id uuid references consoles(id),
    kind payment_kind not null,
    status payment_status not null default 'order_created',
    duration_hours int not null check (duration_hours in (1, 2, 3, 4)),
    amount_paise int not null check (amount_paise > 0),
    currency text not null default 'INR',
    razorpay_order_id text not null unique,
    razorpay_payment_id text,
    razorpay_signature text,
    verified_at timestamptz,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create index if not exists consoles_assignable_idx on consoles (state, last_seen_at) where tailscale_ip is not null;
create index if not exists console_reservations_active_idx on console_reservations (console_id, status, expires_at);
create index if not exists play_sessions_active_idx on play_sessions (console_id, status, ends_at, grace_ends_at);
create index if not exists play_sessions_heartbeat_idx on play_sessions (status, last_heartbeat_at);
create index if not exists payments_order_idx on payments (razorpay_order_id);

alter table consoles enable row level security;
alter table pricing enable row level security;
alter table console_reservations enable row level security;
alter table play_sessions enable row level security;
alter table payments enable row level security;

drop policy if exists play_sessions_realtime_select on play_sessions;
create policy play_sessions_realtime_select
on play_sessions
for select
to anon
using (true);

insert into pricing (duration_hours, amount_paise, currency)
values (1, 10000, 'INR'), (2, 18000, 'INR'), (3, 25000, 'INR'), (4, 32000, 'INR')
on conflict (duration_hours) do nothing;

create or replace function touch_updated_at()
returns trigger
language plpgsql
as $$
begin
    new.updated_at = now();
    return new;
end;
$$;

drop trigger if exists consoles_touch_updated_at on consoles;
create trigger consoles_touch_updated_at before update on consoles
for each row execute function touch_updated_at();

drop trigger if exists pricing_touch_updated_at on pricing;
create trigger pricing_touch_updated_at before update on pricing
for each row execute function touch_updated_at();

drop trigger if exists console_reservations_touch_updated_at on console_reservations;
create trigger console_reservations_touch_updated_at before update on console_reservations
for each row execute function touch_updated_at();

drop trigger if exists play_sessions_touch_updated_at on play_sessions;
create trigger play_sessions_touch_updated_at before update on play_sessions
for each row execute function touch_updated_at();

drop trigger if exists payments_touch_updated_at on payments;
create trigger payments_touch_updated_at before update on payments
for each row execute function touch_updated_at();

create or replace function release_expired_reservations_sql()
returns int
language plpgsql
security definer
as $$
declare
    released_count int := 0;
begin
    with expired as (
        update console_reservations
        set status = 'expired'
        where status = 'reserved'
          and expires_at < now()
        returning console_id
    ),
    released as (
        update consoles c
        set state = 'available'
        from expired e
        where c.id = e.console_id
          and c.state = 'reserved'
        returning c.id
    )
    select count(*) into released_count from released;

    return released_count;
end;
$$;

create or replace function reserve_available_console()
returns table(reservation jsonb, console jsonb)
language plpgsql
security definer
as $$
declare
    selected_console consoles%rowtype;
    created_reservation console_reservations%rowtype;
begin
    perform release_expired_reservations_sql();

    select *
    into selected_console
    from consoles
    where state = 'available'
      and tailscale_ip is not null
    order by coalesce(last_seen_at, created_at) desc, created_at asc
    for update skip locked
    limit 1;

    if not found then
        return;
    end if;

    update consoles
    set state = 'reserved'
    where id = selected_console.id
    returning * into selected_console;

    insert into console_reservations (console_id)
    values (selected_console.id)
    returning * into created_reservation;

    return query select to_jsonb(created_reservation), to_jsonb(selected_console);
end;
$$;

create or replace function release_reservation(p_reservation_id uuid)
returns jsonb
language plpgsql
security definer
as $$
declare
    reservation_row console_reservations%rowtype;
begin
    select *
    into reservation_row
    from console_reservations
    where id = p_reservation_id
    for update;

    if not found then
        raise exception 'reservation_not_found';
    end if;

    if reservation_row.status = 'reserved' then
        update console_reservations
        set status = 'released'
        where id = p_reservation_id
        returning * into reservation_row;

        update consoles
        set state = 'available'
        where id = reservation_row.console_id
          and state = 'reserved';
    end if;

    return to_jsonb(reservation_row);
end;
$$;

create or replace function confirm_initial_payment(
    p_payment_id uuid,
    p_razorpay_payment_id text,
    p_razorpay_signature text
)
returns table(payment jsonb, session jsonb, console jsonb)
language plpgsql
security definer
as $$
declare
    payment_row payments%rowtype;
    reservation_row console_reservations%rowtype;
    session_row play_sessions%rowtype;
    console_row consoles%rowtype;
begin
    select * into payment_row from payments where id = p_payment_id for update;
    if not found or payment_row.kind <> 'initial' or payment_row.status <> 'order_created' then
        raise exception 'invalid_payment';
    end if;

    select * into reservation_row from console_reservations where id = payment_row.reservation_id for update;
    if not found or reservation_row.status <> 'reserved' or reservation_row.expires_at < now() then
        raise exception 'reservation_expired';
    end if;

    select * into console_row from consoles where id = reservation_row.console_id for update;
    if not found or console_row.state <> 'reserved' then
        raise exception 'console_not_reserved';
    end if;

    update payments
    set status = 'verified',
        razorpay_payment_id = p_razorpay_payment_id,
        razorpay_signature = p_razorpay_signature,
        verified_at = now()
    where id = p_payment_id
    returning * into payment_row;

    insert into play_sessions (
        reservation_id,
        console_id,
        status,
        started_at,
        ends_at,
        grace_ends_at,
        last_heartbeat_at
    )
    values (
        reservation_row.id,
        reservation_row.console_id,
        'active',
        now(),
        now() + (payment_row.duration_hours || ' hours')::interval,
        now() + (payment_row.duration_hours || ' hours')::interval + interval '5 minutes',
        now()
    )
    returning * into session_row;

    update console_reservations
    set status = 'converted'
    where id = reservation_row.id;

    update consoles
    set state = 'in_session'
    where id = console_row.id
    returning * into console_row;

    return query select to_jsonb(payment_row), to_jsonb(session_row), to_jsonb(console_row);
end;
$$;

create or replace function confirm_extension_payment(
    p_payment_id uuid,
    p_razorpay_payment_id text,
    p_razorpay_signature text
)
returns table(payment jsonb, session jsonb, console jsonb)
language plpgsql
security definer
as $$
declare
    payment_row payments%rowtype;
    session_row play_sessions%rowtype;
    console_row consoles%rowtype;
    new_end timestamptz;
begin
    select * into payment_row from payments where id = p_payment_id for update;
    if not found or payment_row.kind <> 'extension' or payment_row.status <> 'order_created' then
        raise exception 'invalid_payment';
    end if;

    select * into session_row from play_sessions where id = payment_row.session_id for update;
    if not found or session_row.status not in ('active', 'extended', 'expired') or session_row.grace_ends_at < now() then
        raise exception 'session_not_extendable';
    end if;

    new_end := greatest(session_row.ends_at, now()) + (payment_row.duration_hours || ' hours')::interval;

    update payments
    set status = 'verified',
        razorpay_payment_id = p_razorpay_payment_id,
        razorpay_signature = p_razorpay_signature,
        verified_at = now()
    where id = p_payment_id
    returning * into payment_row;

    update play_sessions
    set status = 'extended',
        ends_at = new_end,
        grace_ends_at = new_end + interval '5 minutes',
        last_heartbeat_at = now()
    where id = session_row.id
    returning * into session_row;

    update consoles
    set state = 'in_session'
    where id = session_row.console_id
    returning * into console_row;

    return query select to_jsonb(payment_row), to_jsonb(session_row), to_jsonb(console_row);
end;
$$;

create or replace function heartbeat_session(p_session_id uuid)
returns jsonb
language plpgsql
security definer
as $$
declare
    session_row play_sessions%rowtype;
begin
    select * into session_row from play_sessions where id = p_session_id for update;
    if not found then
        raise exception 'session_not_found';
    end if;

    if session_row.status in ('completed', 'disconnected') then
        return to_jsonb(session_row);
    end if;

    if session_row.grace_ends_at < now() then
        update play_sessions
        set status = 'completed'
        where id = p_session_id
        returning * into session_row;

        update consoles
        set state = 'available'
        where id = session_row.console_id
          and state = 'in_session';

        return to_jsonb(session_row);
    end if;

    update play_sessions
    set status = case when ends_at < now() then 'expired'::session_state else status end,
        last_heartbeat_at = now()
    where id = p_session_id
    returning * into session_row;

    return to_jsonb(session_row);
end;
$$;

create or replace function end_session(p_session_id uuid, p_status session_state default 'completed')
returns jsonb
language plpgsql
security definer
as $$
declare
    session_row play_sessions%rowtype;
begin
    select * into session_row from play_sessions where id = p_session_id for update;
    if not found then
        raise exception 'session_not_found';
    end if;

    update play_sessions
    set status = p_status,
        last_heartbeat_at = now()
    where id = p_session_id
      and status in ('pending', 'active', 'extended', 'expired')
    returning * into session_row;

    update consoles
    set state = 'available'
    where id = session_row.console_id
      and state = 'in_session';

    return to_jsonb(session_row);
end;
$$;

create or replace function release_expired_sessions_sql()
returns int
language plpgsql
security definer
as $$
declare
    released_count int := 0;
begin
    update play_sessions
    set status = 'expired'
    where status in ('active', 'extended')
      and ends_at < now()
      and grace_ends_at >= now();

    with stale as (
        update play_sessions
        set status = 'disconnected'
        where status in ('active', 'extended', 'expired')
          and last_heartbeat_at < now() - interval '2 minutes'
          and grace_ends_at >= now()
        returning console_id
    ),
    grace_done as (
        update play_sessions
        set status = 'expired'
        where status in ('active', 'extended', 'expired')
          and grace_ends_at < now()
        returning console_id
    ),
    released as (
        update consoles c
        set state = 'available'
        where c.state = 'in_session'
          and c.id in (
            select console_id from stale
            union
            select console_id from grace_done
          )
        returning c.id
    )
    select count(*) into released_count from released;

    return released_count;
end;
$$;

do $$
begin
    alter publication supabase_realtime add table consoles;
exception when duplicate_object or undefined_object then null;
end $$;

do $$
begin
    alter publication supabase_realtime add table console_reservations;
exception when duplicate_object or undefined_object then null;
end $$;

do $$
begin
    alter publication supabase_realtime add table play_sessions;
exception when duplicate_object or undefined_object then null;
end $$;

do $$
begin
    alter publication supabase_realtime add table payments;
exception when duplicate_object or undefined_object then null;
end $$;
