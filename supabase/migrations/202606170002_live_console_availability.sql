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
      and tailscale_ip is not null
      and last_seen_at is not null
      and last_seen_at > now() - interval '2 minutes';

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
      and last_seen_at is not null
      and last_seen_at > now() - interval '2 minutes'
    order by last_seen_at desc, created_at asc
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
      and last_seen_at is not null
      and last_seen_at > now() - interval '2 minutes'
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

grant execute on function public.count_available_consoles() to service_role;
grant execute on function public.reserve_available_console() to service_role;
