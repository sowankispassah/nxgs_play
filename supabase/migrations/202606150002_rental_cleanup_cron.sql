create extension if not exists pg_cron;

select cron.unschedule(jobid)
from cron.job
where jobname in (
    'nxgs-release-expired-reservations',
    'nxgs-release-expired-sessions'
);

select cron.schedule(
    'nxgs-release-expired-reservations',
    '* * * * *',
    $$select public.release_expired_reservations_sql();$$
);

select cron.schedule(
    'nxgs-release-expired-sessions',
    '* * * * *',
    $$select public.release_expired_sessions_sql();$$
);
