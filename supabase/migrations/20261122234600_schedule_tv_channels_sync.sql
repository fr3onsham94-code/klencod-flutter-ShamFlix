-- Schedule TV channel aggregation every six hours and health checks hourly.
create extension if not exists pg_cron with schema pg_catalog;
create extension if not exists pg_net;
grant usage on schema cron to postgres;
grant all privileges on all tables in schema cron to postgres;
grant usage on schema vault to service_role;
grant select on vault.decrypted_secrets to service_role;

create or replace function public.verify_tv_channels_cron_secret(candidate_secret text)
returns boolean
language sql
stable
set search_path = ''
as $function$
  select exists (
    select 1 from vault.decrypted_secrets
    where name = 'shamflix_tv_channels_cron_secret_v1'
      and decrypted_secret = candidate_secret
  );
$function$;

revoke all on function public.verify_tv_channels_cron_secret(text) from public, anon, authenticated;
grant execute on function public.verify_tv_channels_cron_secret(text) to service_role;

select vault.create_secret(
  replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', ''),
  'shamflix_tv_channels_cron_secret_v1'
);

select vault.create_secret(
  'https://qjagbdxuytnuzwcfbcse.supabase.co',
  'shamflix_tv_channels_project_url_v1'
);

select cron.schedule(
  'shamflix-tv-channels-sync',
  '0 */6 * * *',
  $job$
    select net.http_post(
      url := (select decrypted_secret from vault.decrypted_secrets where name = 'shamflix_tv_channels_project_url_v1') || '/functions/v1/tv-channels-auto-sync',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-shamflix-tv-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'shamflix_tv_channels_cron_secret_v1')
      ),
      body := jsonb_build_object('mode', 'sync', 'triggered_at', now()),
      timeout_milliseconds := 120000
    );
  $job$
);

select cron.schedule(
  'shamflix-tv-channels-health',
  '15 * * * *',
  $job$
    select net.http_post(
      url := (select decrypted_secret from vault.decrypted_secrets where name = 'shamflix_tv_channels_project_url_v1') || '/functions/v1/tv-channels-auto-sync',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-shamflix-tv-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'shamflix_tv_channels_cron_secret_v1')
      ),
      body := jsonb_build_object('mode', 'health', 'triggered_at', now()),
      timeout_milliseconds := 120000
    );
  $job$
);
