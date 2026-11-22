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
