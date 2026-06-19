create table if not exists public.manual_console_locks (
    id uuid primary key default gen_random_uuid(),
    console_id uuid not null unique references public.consoles(id) on delete cascade,
    lock_type text not null,
    note text,
    expires_at timestamptz,
    created_by text not null default 'controller_admin',
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint manual_console_locks_type_check
        check (lock_type in ('reserved', 'occupied')),
    constraint manual_console_locks_note_length_check
        check (note is null or length(note) <= 500)
);

create index if not exists manual_console_locks_expiry_idx
    on public.manual_console_locks(expires_at)
    where expires_at is not null;

drop trigger if exists manual_console_locks_touch_updated_at on public.manual_console_locks;
create trigger manual_console_locks_touch_updated_at
before update on public.manual_console_locks
for each row execute function public.touch_updated_at();

alter table public.manual_console_locks enable row level security;

drop policy if exists deny_client_direct_access on public.manual_console_locks;
create policy deny_client_direct_access
on public.manual_console_locks
for all
to anon, authenticated
using (false)
with check (false);

revoke all on table public.manual_console_locks from public, anon, authenticated;
grant select, insert, update, delete on table public.manual_console_locks to service_role;

create or replace function public.release_expired_manual_console_locks_sql()
returns int
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
    released_count int := 0;
begin
    delete from public.manual_console_locks
    where expires_at is not null
      and expires_at <= now();

    get diagnostics released_count = row_count;
    return released_count;
end;
$$;

create or replace function public.set_manual_console_availability(
    p_console_id uuid,
    p_action text,
    p_duration_minutes int default null,
    p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
    console_row public.consoles%rowtype;
    lock_row public.manual_console_locks%rowtype;
    normalized_action text := lower(trim(coalesce(p_action, '')));
    normalized_note text := nullif(trim(coalesce(p_note, '')), '');
    lock_expires_at timestamptz;
    has_customer_activity boolean := false;
begin
    if normalized_action not in ('available', 'reserved', 'occupied', 'maintenance', 'disabled') then
        raise exception 'invalid_manual_console_action';
    end if;

    if normalized_note is not null and length(normalized_note) > 500 then
        raise exception 'invalid_manual_console_note';
    end if;

    perform public.release_expired_reservations_sql();
    perform public.release_expired_sessions_sql();
    perform public.release_expired_manual_console_locks_sql();

    select *
    into console_row
    from public.consoles
    where id = p_console_id
    for update;

    if not found then
        raise exception 'console_not_found';
    end if;

    select exists (
        select 1
        from public.console_reservations
        where console_id = p_console_id
          and status = 'reserved'
          and expires_at > now()
    ) or exists (
        select 1
        from public.play_sessions
        where console_id = p_console_id
          and status in ('pending', 'active', 'extended', 'expired')
          and coalesce(grace_ends_at, ends_at, now() + interval '1 minute') > now()
    )
    into has_customer_activity;

    if has_customer_activity or console_row.state in ('reserved', 'in_session') then
        raise exception 'console_has_active_customer_activity';
    end if;

    if normalized_action in ('reserved', 'occupied') then
        if console_row.state <> 'available' or console_row.disabled_at is not null then
            raise exception 'console_not_available_for_manual_lock';
        end if;

        if p_duration_minutes is not null
           and (p_duration_minutes < 1 or p_duration_minutes > 43200) then
            raise exception 'invalid_manual_lock_duration';
        end if;

        lock_expires_at := case
            when p_duration_minutes is null then null
            else now() + make_interval(mins => p_duration_minutes)
        end;

        insert into public.manual_console_locks(
            console_id,
            lock_type,
            note,
            expires_at,
            created_by
        )
        values (
            p_console_id,
            normalized_action,
            normalized_note,
            lock_expires_at,
            'controller_admin'
        )
        on conflict (console_id) do update
        set lock_type = excluded.lock_type,
            note = excluded.note,
            expires_at = excluded.expires_at,
            created_by = excluded.created_by,
            updated_at = now()
        returning * into lock_row;

        return jsonb_build_object(
            'console', to_jsonb(console_row),
            'manual_lock', to_jsonb(lock_row),
            'effective_state', normalized_action
        );
    end if;

    delete from public.manual_console_locks
    where console_id = p_console_id;

    update public.consoles
    set state = normalized_action::console_state,
        disabled_at = case when normalized_action = 'disabled' then now() else null end
    where id = p_console_id
    returning * into console_row;

    return jsonb_build_object(
        'console', to_jsonb(console_row),
        'manual_lock', null,
        'effective_state', normalized_action
    );
end;
$$;

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
    perform public.release_expired_manual_console_locks_sql();

    select count(*)
    into available_count
    from public.consoles c
    where c.state = 'available'
      and c.disabled_at is null
      and c.tailscale_ip is not null
      and c.mac_address is not null
      and c.mac_address <> ''
      and not exists (
          select 1
          from public.manual_console_locks manual_lock
          where manual_lock.console_id = c.id
            and (manual_lock.expires_at is null or manual_lock.expires_at > now())
      );

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
    console_row public.consoles%rowtype;
    reservation_row public.console_reservations%rowtype;
begin
    perform public.release_expired_reservations_sql();
    perform public.release_expired_sessions_sql();
    perform public.release_expired_manual_console_locks_sql();

    select *
    into console_row
    from public.consoles c
    where c.state = 'available'
      and c.disabled_at is null
      and c.tailscale_ip is not null
      and c.mac_address is not null
      and c.mac_address <> ''
      and not exists (
          select 1
          from public.manual_console_locks manual_lock
          where manual_lock.console_id = c.id
            and (manual_lock.expires_at is null or manual_lock.expires_at > now())
      )
    order by coalesce(c.last_seen_at, c.added_at, c.created_at) desc, c.created_at asc
    limit 1
    for update of c skip locked;

    if not found then
        return;
    end if;

    update public.consoles c
    set state = 'reserved'
    where c.id = console_row.id
      and c.state = 'available'
      and c.disabled_at is null
      and c.tailscale_ip is not null
      and c.mac_address is not null
      and c.mac_address <> ''
      and not exists (
          select 1
          from public.manual_console_locks manual_lock
          where manual_lock.console_id = c.id
            and (manual_lock.expires_at is null or manual_lock.expires_at > now())
      )
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

revoke execute on function public.release_expired_manual_console_locks_sql() from public, anon, authenticated;
revoke execute on function public.set_manual_console_availability(uuid, text, int, text) from public, anon, authenticated;
grant execute on function public.release_expired_manual_console_locks_sql() to service_role;
grant execute on function public.set_manual_console_availability(uuid, text, int, text) to service_role;
grant execute on function public.count_available_consoles() to service_role;
grant execute on function public.reserve_available_console() to service_role;

select cron.unschedule(jobid)
from cron.job
where jobname = 'nxgs-release-expired-manual-console-locks';

select cron.schedule(
    'nxgs-release-expired-manual-console-locks',
    '* * * * *',
    $$select public.release_expired_manual_console_locks_sql();$$
);
