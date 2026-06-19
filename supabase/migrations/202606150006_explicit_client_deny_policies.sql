do $$
declare
    table_row record;
begin
    for table_row in
        select * from (values
            ('public', 'app_settings'),
            ('public', 'console_reservations'),
            ('public', 'consoles'),
            ('public', 'payments'),
            ('public', 'pricing'),
            ('public', 'stores'),
            ('public', 'time_plans'),
            ('public', 'store_time_plan_prices')
        ) as protected_tables(schema_name, table_name)
    loop
        if not exists (
            select 1
            from pg_policies
            where schemaname = table_row.schema_name
              and tablename = table_row.table_name
              and policyname = 'deny_client_direct_access'
        ) then
            execute format(
                'create policy deny_client_direct_access on %I.%I for all to anon, authenticated using (false) with check (false)',
                table_row.schema_name,
                table_row.table_name
            );
        end if;
    end loop;
end $$;
