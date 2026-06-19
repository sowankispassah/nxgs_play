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
    if payment_row.status = 'verified' then
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
    set status = 'verified',
        razorpay_payment_id = p_razorpay_payment_id,
        razorpay_signature = p_razorpay_signature,
        verified_at = now()
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
        last_heartbeat_at
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
        now()
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
    if payment_row.status = 'verified' then
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
    set status = 'verified',
        razorpay_payment_id = p_razorpay_payment_id,
        razorpay_signature = p_razorpay_signature,
        verified_at = now()
    where id = p_payment_id
    returning * into payment_row;

    update play_sessions
    set status = 'extended',
        store_id = payment_row.store_id,
        time_plan_id = payment_row.time_plan_id,
        duration_minutes = coalesce(duration_minutes, 0) + payment_row.duration_minutes,
        ends_at = greatest(ends_at, now()) + duration_interval,
        grace_ends_at = greatest(ends_at, now()) + duration_interval + interval '5 minutes',
        last_heartbeat_at = now()
    where id = session_row.id
    returning * into session_row;

    payment := to_jsonb(payment_row);
    session := to_jsonb(session_row);
    console := public.safe_console_json(console_row);
    return next;
end;
$$;

revoke execute on function public.confirm_initial_payment(uuid, text, text) from public, anon, authenticated;
revoke execute on function public.confirm_extension_payment(uuid, text, text) from public, anon, authenticated;
grant execute on function public.confirm_initial_payment(uuid, text, text) to service_role;
grant execute on function public.confirm_extension_payment(uuid, text, text) to service_role;
