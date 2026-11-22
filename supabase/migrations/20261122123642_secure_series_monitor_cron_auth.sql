grant usage on schema vault to service_role;
grant select on vault.decrypted_secrets to service_role;

create or replace function public.verify_series_monitor_cron_secret(candidate_secret text)
returns boolean
language sql
stable
set search_path = ''
as $function$
  select exists (
    select 1
    from vault.decrypted_secrets
    where name = 'shamflix_series_monitor_cron_secret_v1'
      and decrypted_secret = candidate_secret
  );
$function$;

revoke all on function public.verify_series_monitor_cron_secret(text) from public, anon, authenticated;
grant execute on function public.verify_series_monitor_cron_secret(text) to service_role;

select vault.create_secret(
  replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', ''),
  'shamflix_series_monitor_cron_secret_v1'
);

select vault.create_secret(
  'https://qjagbdxuytnuzwcfbcse.supabase.co',
  'shamflix_series_monitor_project_url_v1'
);

select cron.schedule(
  'shamflix-series-auto-monitor',
  '*/30 * * * *',
  $job$
    select net.http_post(
      url := (select decrypted_secret from vault.decrypted_secrets where name = 'shamflix_series_monitor_project_url_v1') || '/functions/v1/series-auto-monitor',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-shamflix-monitor-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'shamflix_series_monitor_cron_secret_v1')
      ),
      body := jsonb_build_object('triggered_at', now()),
      timeout_milliseconds := 120000
    );
  $job$
);
