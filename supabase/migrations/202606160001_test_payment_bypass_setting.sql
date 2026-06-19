insert into public.app_settings(key, value)
values ('test_payment_bypass', 'false')
on conflict (key) do nothing;
