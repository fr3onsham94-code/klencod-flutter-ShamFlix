-- Run movie and series source-page monitors every 15 minutes.
select cron.alter_job(1, schedule := '*/15 * * * *');
select cron.alter_job(2, schedule := '*/15 * * * *');
