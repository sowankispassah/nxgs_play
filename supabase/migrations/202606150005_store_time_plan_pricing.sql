create table if not exists public.stores (
    id uuid primary key default gen_random_uuid(),
    name text not null,
    location text,
    phone text,
    email text,
    notes text,
    active boolean not null default true,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create table if not exists public.time_plans (
    id uuid primary key default gen_random_uuid(),
    name text not null,
    duration_minutes int not null check (duration_minutes > 0),
    active boolean not null default true,
    sort_order int not null default 0,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    unique(duration_minutes)
);

create table if not exists public.store_time_plan_prices (
    id uuid primary key default gen_random_uuid(),
    store_id uuid not null references public.stores(id) on delete restrict,
    time_plan_id uuid not null references public.time_plans(id) on delete restrict,
    amount_paise int not null check (amount_paise > 0),
    currency text not null default 'INR',
    active boolean not null default true,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    unique(store_id, time_plan_id)
);

drop trigger if exists stores_touch_updated_at on public.stores;
create trigger stores_touch_updated_at
before update on public.stores
for each row execute function public.touch_updated_at();

drop trigger if exists time_plans_touch_updated_at on public.time_plans;
create trigger time_plans_touch_updated_at
before update on public.time_plans
for each row execute function public.touch_updated_at();

drop trigger if exists store_time_plan_prices_touch_updated_at on public.store_time_plan_prices;
create trigger store_time_plan_prices_touch_updated_at
before update on public.store_time_plan_prices
for each row execute function public.touch_updated_at();

alter table public.stores enable row level security;
alter table public.time_plans enable row level security;
alter table public.store_time_plan_prices enable row level security;

alter table public.payments
    alter column duration_hours drop not null,
    add column if not exists store_id uuid references public.stores(id),
    add column if not exists time_plan_id uuid references public.time_plans(id),
    add column if not exists duration_minutes int;

alter table public.play_sessions
    add column if not exists store_id uuid references public.stores(id),
    add column if not exists time_plan_id uuid references public.time_plans(id),
    add column if not exists duration_minutes int;

do $$
declare
    default_store_id uuid;
begin
    insert into public.stores(name, location, phone, active)
    values ('Default Store', '', '', true)
    on conflict do nothing;

    select id into default_store_id
    from public.stores
    order by created_at
    limit 1;

    insert into public.time_plans(name, duration_minutes, active, sort_order)
    select duration_hours::text || case when duration_hours = 1 then ' Hour' else ' Hours' end,
           duration_hours * 60,
           active,
           duration_hours * 60
    from public.pricing
    on conflict (duration_minutes) do update
        set name = excluded.name,
            active = excluded.active,
            sort_order = excluded.sort_order;

    insert into public.store_time_plan_prices(store_id, time_plan_id, amount_paise, currency, active)
    select default_store_id, tp.id, p.amount_paise, p.currency, p.active
    from public.pricing p
    join public.time_plans tp on tp.duration_minutes = p.duration_hours * 60
    where default_store_id is not null
    on conflict (store_id, time_plan_id) do update
        set amount_paise = excluded.amount_paise,
            currency = excluded.currency,
            active = excluded.active;
end $$;

alter table public.consoles
    drop column if exists store_name,
    drop column if exists store_location,
    drop column if exists store_phone,
    drop column if exists store_email;

create index if not exists store_time_plan_prices_store_idx
    on public.store_time_plan_prices(store_id);

create index if not exists store_time_plan_prices_time_plan_idx
    on public.store_time_plan_prices(time_plan_id);

create index if not exists payments_store_id_idx
    on public.payments(store_id);

create index if not exists payments_time_plan_id_idx
    on public.payments(time_plan_id);

create index if not exists play_sessions_store_id_idx
    on public.play_sessions(store_id);

create index if not exists play_sessions_time_plan_id_idx
    on public.play_sessions(time_plan_id);

create or replace function public.confirm_initial_payment(
    p_payment_id uuid,
    p_razorpay_payment_id text,
    p_razorpay_signature text
)
returns table(payment jsonb, session jsonb, console jsonb)
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
    payment_row payments%rowtype;
    reservation_row console_reservations%rowtype;
    console_row consoles%rowtype;
    session_row play_sessions%rowtype;
    duration_interval interval;
begin
    select * into payment_row from payments where id = p_payment_id for update;
    if not found then
        raise exception 'payment_not_found';
    end if;
    if payment_row.status = 'paid' then
        raise exception 'payment_already_verified';
    end if;
    if payment_row.kind <> 'initial' then
        raise exception 'invalid_payment_kind';
    end if;
    if payment_row.duration_minutes is null or payment_row.duration_minutes <= 0 then
        raise exception 'invalid_duration';
    end if;

    select * into reservation_row from console_reservations where id = payment_row.reservation_id for update;
    if not found or reservation_row.status <> 'reserved' or reservation_row.expires_at < now() then
        raise exception 'reservation_expired';
    end if;

    select * into console_row from consoles where id = reservation_row.console_id for update;
    if not found or console_row.state <> 'reserved' or console_row.disabled_at is not null then
        raise exception 'console_unavailable';
    end if;

    duration_interval := make_interval(mins => payment_row.duration_minutes);

    update payments
    set status = 'paid',
        razorpay_payment_id = p_razorpay_payment_id,
        razorpay_signature = p_razorpay_signature,
        paid_at = now()
    where id = p_payment_id
    returning * into payment_row;

    update console_reservations
    set status = 'converted'
    where id = reservation_row.id
    returning * into reservation_row;

    update consoles
    set state = 'in_session'
    where id = console_row.id
    returning * into console_row;

    insert into play_sessions(
        reservation_id,
        console_id,
        store_id,
        time_plan_id,
        duration_minutes,
        status,
        started_at,
        ends_at,
        grace_ends_at,
        last_heartbeat_at,
        total_paid_paise
    )
    values (
        reservation_row.id,
        console_row.id,
        payment_row.store_id,
        payment_row.time_plan_id,
        payment_row.duration_minutes,
        'active',
        now(),
        now() + duration_interval,
        now() + duration_interval + interval '5 minutes',
        now(),
        payment_row.amount_paise
    )
    returning * into session_row;

    update payments
    set session_id = session_row.id
    where id = payment_row.id
    returning * into payment_row;

    payment := to_jsonb(payment_row);
    session := to_jsonb(session_row);
    console := public.safe_console_json(console_row);
    return next;
end;
$$;

create or replace function public.confirm_extension_payment(
    p_payment_id uuid,
    p_razorpay_payment_id text,
    p_razorpay_signature text
)
returns table(payment jsonb, session jsonb, console jsonb)
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
    payment_row payments%rowtype;
    session_row play_sessions%rowtype;
    console_row consoles%rowtype;
    duration_interval interval;
begin
    select * into payment_row from payments where id = p_payment_id for update;
    if not found then
        raise exception 'payment_not_found';
    end if;
    if payment_row.status = 'paid' then
        raise exception 'payment_already_verified';
    end if;
    if payment_row.kind <> 'extension' then
        raise exception 'invalid_payment_kind';
    end if;
    if payment_row.duration_minutes is null or payment_row.duration_minutes <= 0 then
        raise exception 'invalid_duration';
    end if;

    select * into session_row from play_sessions where id = payment_row.session_id for update;
    if not found or session_row.status not in ('active', 'extended', 'expired') or session_row.grace_ends_at < now() then
        raise exception 'session_not_extendable';
    end if;

    select * into console_row from consoles where id = session_row.console_id for update;
    if not found or console_row.disabled_at is not null then
        raise exception 'console_unavailable';
    end if;

    duration_interval := make_interval(mins => payment_row.duration_minutes);

    update payments
    set status = 'paid',
        razorpay_payment_id = p_razorpay_payment_id,
        razorpay_signature = p_razorpay_signature,
        paid_at = now()
    where id = p_payment_id
    returning * into payment_row;

    update play_sessions
    set status = 'extended',
        store_id = payment_row.store_id,
        time_plan_id = payment_row.time_plan_id,
        duration_minutes = coalesce(duration_minutes, 0) + payment_row.duration_minutes,
        ends_at = greatest(ends_at, now()) + duration_interval,
        grace_ends_at = greatest(ends_at, now()) + duration_interval + interval '5 minutes',
        total_paid_paise = total_paid_paise + payment_row.amount_paise,
        last_heartbeat_at = now()
    where id = session_row.id
    returning * into session_row;

    payment := to_jsonb(payment_row);
    session := to_jsonb(session_row);
    console := public.safe_console_json(console_row);
    return next;
end;
$$;

revoke all on table public.stores from public, anon, authenticated;
revoke all on table public.time_plans from public, anon, authenticated;
revoke all on table public.store_time_plan_prices from public, anon, authenticated;
