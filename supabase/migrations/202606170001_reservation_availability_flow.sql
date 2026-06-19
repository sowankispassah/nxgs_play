create or replace function public.count_available_consoles()
returns int
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
    available_count int := 0;
begin
    perform public.release_expired_reservations_sql();
    perform public.release_expired_sessions_sql();

    select count(*)
    into available_count
    from public.consoles
    where state = 'available'
      and disabled_at is null
      and tailscale_ip is not null;

    return available_count;
end;
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
    perform public.release_expired_sessions_sql();

    select * into console_row
    from public.consoles
    where state = 'available'
      and disabled_at is null
      and tailscale_ip is not null
    order by coalesce(last_seen_at, created_at) desc, created_at asc
    limit 1
    for update skip locked;

    if not found then
        return;
    end if;

    update public.consoles
    set state = 'reserved'
    where id = console_row.id
      and state = 'available'
      and disabled_at is null
      and tailscale_ip is not null
    returning * into console_row;

    if not found then
        return;
    end if;

    insert into public.console_reservations(console_id)
    values (console_row.id)
    returning * into reservation_row;

    reservation := to_jsonb(reservation_row);
    console := public.safe_console_json(console_row);
    return next;
end;
$$;

create or replace function public.release_reservation(p_reservation_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
    reservation_row console_reservations%rowtype;
begin
    select *
    into reservation_row
    from public.console_reservations
    where id = p_reservation_id
    for update;

    if not found then
        raise exception 'reservation_not_found';
    end if;

    if reservation_row.status = 'reserved' then
        update public.console_reservations
        set status = 'released'
        where id = p_reservation_id
        returning * into reservation_row;

        update public.consoles
        set state = 'available'
        where id = reservation_row.console_id
          and state = 'reserved'
          and disabled_at is null;
    end if;

    return to_jsonb(reservation_row);
end;
$$;

create or replace function public.end_session(p_session_id uuid, p_status session_state default 'completed')
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
    session_row play_sessions%rowtype;
begin
    select * into session_row from public.play_sessions where id = p_session_id for update;
    if not found then
        raise exception 'session_not_found';
    end if;

    update public.play_sessions
    set status = p_status,
        last_heartbeat_at = now()
    where id = p_session_id
      and status in ('pending', 'active', 'extended', 'expired')
    returning * into session_row;

    update public.consoles
    set state = 'available'
    where id = session_row.console_id
      and state = 'in_session'
      and disabled_at is null;

    return to_jsonb(session_row);
end;
$$;

create or replace function public.release_expired_reservations_sql()
returns int
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
    released_count int := 0;
begin
    with expired as (
        update public.console_reservations
        set status = 'expired'
        where status = 'reserved'
          and expires_at < now()
        returning console_id
    ),
    released as (
        update public.consoles c
        set state = 'available'
        from expired e
        where c.id = e.console_id
          and c.state = 'reserved'
          and c.disabled_at is null
        returning c.id
    )
    select count(*) into released_count from released;

    return released_count;
end;
$$;

create or replace function public.release_expired_sessions_sql()
returns int
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
    released_count int := 0;
begin
    update public.play_sessions
    set status = 'expired'
    where status in ('active', 'extended')
      and ends_at < now()
      and grace_ends_at >= now();

    with stale as (
        update public.play_sessions
        set status = 'disconnected'
        where status in ('active', 'extended', 'expired')
          and last_heartbeat_at < now() - interval '2 minutes'
          and grace_ends_at >= now()
        returning console_id
    ),
    grace_done as (
        update public.play_sessions
        set status = 'expired'
        where status in ('active', 'extended', 'expired')
          and grace_ends_at < now()
        returning console_id
    ),
    released as (
        update public.consoles c
        set state = 'available'
        where c.state = 'in_session'
          and c.disabled_at is null
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

revoke execute on function public.count_available_consoles() from public, anon, authenticated;
grant execute on function public.count_available_consoles() to service_role;
grant execute on function public.reserve_available_console() to service_role;
grant execute on function public.release_reservation(uuid) to service_role;
grant execute on function public.end_session(uuid, session_state) to service_role;
grant execute on function public.release_expired_reservations_sql() to service_role;
grant execute on function public.release_expired_sessions_sql() to service_role;
