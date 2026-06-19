create or replace function public.safe_console_json(console_row public.consoles)
returns jsonb
language sql
stable
set search_path = public, extensions, pg_temp
as $$
    select (to_jsonb(console_row)
        - 'console_pin'
        - 'store_phone'
        - 'store_email')
        || jsonb_build_object('tailscale_ip', host(console_row.tailscale_ip));
$$;

grant execute on function public.safe_console_json(public.consoles) to service_role;
