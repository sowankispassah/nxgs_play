alter function public.release_expired_reservations_sql()
set search_path = public, extensions, pg_temp;

alter function public.reserve_available_console()
set search_path = public, extensions, pg_temp;

alter function public.release_reservation(uuid)
set search_path = public, extensions, pg_temp;

alter function public.confirm_initial_payment(uuid, text, text)
set search_path = public, extensions, pg_temp;

alter function public.confirm_extension_payment(uuid, text, text)
set search_path = public, extensions, pg_temp;

alter function public.heartbeat_session(uuid)
set search_path = public, extensions, pg_temp;

alter function public.end_session(uuid, session_state)
set search_path = public, extensions, pg_temp;

alter function public.release_expired_sessions_sql()
set search_path = public, extensions, pg_temp;

revoke execute on function public.release_expired_reservations_sql() from public, anon, authenticated;
revoke execute on function public.reserve_available_console() from public, anon, authenticated;
revoke execute on function public.release_reservation(uuid) from public, anon, authenticated;
revoke execute on function public.confirm_initial_payment(uuid, text, text) from public, anon, authenticated;
revoke execute on function public.confirm_extension_payment(uuid, text, text) from public, anon, authenticated;
revoke execute on function public.heartbeat_session(uuid) from public, anon, authenticated;
revoke execute on function public.end_session(uuid, session_state) from public, anon, authenticated;
revoke execute on function public.release_expired_sessions_sql() from public, anon, authenticated;

grant execute on function public.release_expired_reservations_sql() to service_role;
grant execute on function public.reserve_available_console() to service_role;
grant execute on function public.release_reservation(uuid) to service_role;
grant execute on function public.confirm_initial_payment(uuid, text, text) to service_role;
grant execute on function public.confirm_extension_payment(uuid, text, text) to service_role;
grant execute on function public.heartbeat_session(uuid) to service_role;
grant execute on function public.end_session(uuid, session_state) to service_role;
grant execute on function public.release_expired_sessions_sql() to service_role;

create index if not exists payments_console_id_idx
    on public.payments(console_id);

create index if not exists payments_reservation_id_idx
    on public.payments(reservation_id);

create index if not exists payments_session_id_idx
    on public.payments(session_id);

create index if not exists play_sessions_reservation_id_idx
    on public.play_sessions(reservation_id);
