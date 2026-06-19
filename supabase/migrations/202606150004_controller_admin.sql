create extension if not exists pgcrypto;

alter type console_state add value if not exists 'disabled';

create table if not exists public.app_settings (
    id uuid primary key default gen_random_uuid(),
    key text not null unique,
    value text not null,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

drop trigger if exists app_settings_touch_updated_at on public.app_settings;
create trigger app_settings_touch_updated_at
before update on public.app_settings
for each row execute function public.touch_updated_at();

alter table public.app_settings enable row level security;

-- The controller access code must be set explicitly during deployment.
-- Do not seed a shared default credential in source control.

alter table public.consoles
    add column if not exists console_pin text,
    add column if not exists store_name text,
    add column if not exists store_location text,
    add column if not exists store_phone text,
    add column if not exists store_email text,
    add column if not exists disabled_at timestamptz,
    add column if not exists added_by text,
    add column if not exists added_at timestamptz not null default now();

create unique index if not exists consoles_mac_address_unique_idx
    on public.consoles(lower(mac_address))
    where mac_address is not null and mac_address <> '';

create or replace function public.verify_controller_admin_pin(p_pin text)
returns boolean
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
    stored_hash text;
begin
    if p_pin is null or length(p_pin) < 4 then
        return false;
    end if;

    select value into stored_hash
    from public.app_settings
    where key = 'controller_admin_pin';

    if stored_hash is null then
        return false;
    end if;

    return stored_hash = crypt(p_pin, stored_hash);
end;
$$;

create or replace function public.set_controller_admin_pin(p_new_pin text)
returns void
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
begin
    if p_new_pin is null or length(p_new_pin) < 4 then
        raise exception 'invalid_controller_pin';
    end if;

    insert into public.app_settings(key, value)
    values ('controller_admin_pin', crypt(p_new_pin, gen_salt('bf', 10)))
    on conflict (key) do update
        set value = excluded.value,
            updated_at = now();
end;
$$;

create or replace function public.safe_console_json(console_row public.consoles)
returns jsonb
language sql
stable
set search_path = public, extensions, pg_temp
as $$
    select to_jsonb(console_row)
        - 'console_pin'
        - 'store_phone'
        - 'store_email';
$$;

create or replace function public.reserve_available_console()
returns table(reservation jsonb, console jsonb)
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
    console_row consoles%rowtype;
    reservation_row console_reservations%rowtype;
begin
    perform public.release_expired_reservations_sql();

    select * into console_row
    from consoles
    where state = 'available'
      and disabled_at is null
    order by coalesce(last_seen_at, created_at) desc
    limit 1
    for update skip locked;

    if not found then
        return;
    end if;

    update consoles
    set state = 'reserved'
    where id = console_row.id
    returning * into console_row;

    insert into console_reservations(console_id)
    values (console_row.id)
    returning * into reservation_row;

    reservation := to_jsonb(reservation_row);
    console := public.safe_console_json(console_row);
    return next;
end;
$$;

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

    select * into reservation_row from console_reservations where id = payment_row.reservation_id for update;
    if not found or reservation_row.status <> 'reserved' or reservation_row.expires_at < now() then
        raise exception 'reservation_expired';
    end if;

    select * into console_row from consoles where id = reservation_row.console_id for update;
    if not found or console_row.state <> 'reserved' or console_row.disabled_at is not null then
        raise exception 'console_unavailable';
    end if;

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
        'active',
        now(),
        now() + make_interval(hours => payment_row.duration_hours),
        now() + make_interval(hours => payment_row.duration_hours) + interval '5 minutes',
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

    select * into session_row from play_sessions where id = payment_row.session_id for update;
    if not found or session_row.status not in ('active', 'extended', 'expired') or session_row.grace_ends_at < now() then
        raise exception 'session_not_extendable';
    end if;

    select * into console_row from consoles where id = session_row.console_id for update;
    if not found or console_row.disabled_at is not null then
        raise exception 'console_unavailable';
    end if;

    update payments
    set status = 'paid',
        razorpay_payment_id = p_razorpay_payment_id,
        razorpay_signature = p_razorpay_signature,
        paid_at = now()
    where id = p_payment_id
    returning * into payment_row;

    update play_sessions
    set status = 'extended',
        ends_at = greatest(ends_at, now()) + make_interval(hours => payment_row.duration_hours),
        grace_ends_at = greatest(ends_at, now()) + make_interval(hours => payment_row.duration_hours) + interval '5 minutes',
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

revoke all on table public.app_settings from public, anon, authenticated;
revoke execute on function public.verify_controller_admin_pin(text) from public, anon, authenticated;
revoke execute on function public.set_controller_admin_pin(text) from public, anon, authenticated;
grant execute on function public.verify_controller_admin_pin(text) to service_role;
grant execute on function public.set_controller_admin_pin(text) to service_role;
grant execute on function public.safe_console_json(public.consoles) to service_role;
