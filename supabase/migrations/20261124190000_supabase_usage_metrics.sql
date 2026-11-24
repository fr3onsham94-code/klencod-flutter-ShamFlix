create or replace function public.shamflix_usage_metrics()
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $function$
declare
  v_database_bytes bigint;
  v_storage_bytes bigint;
  v_storage_files bigint;
  v_table_counts jsonb;
begin
  select pg_catalog.pg_database_size(current_database())
    into v_database_bytes;

  select
    coalesce(sum(
      case
        when (metadata ->> 'size') ~ '^[0-9]+$'
          then (metadata ->> 'size')::bigint
        else 0
      end
    ), 0),
    count(*)
  into v_storage_bytes, v_storage_files
  from storage.objects;

  v_table_counts := jsonb_build_object(
    'movies', (select count(*) from public.movies),
    'series', (select count(*) from public.series),
    'channels', (select count(*) from public.channels),
    'seasons', (select count(*) from public.seasons),
    'episodes', (select count(*) from public.episodes),
    'playback_servers', (select count(*) from public.playback_servers),
    'content_packages', (select count(*) from public.content_packages),
    'content_package_items', (select count(*) from public.content_package_items),
    'user_profiles', (select count(*) from public.user_profiles),
    'user_library', (select count(*) from public.user_library),
    'user_ratings', (select count(*) from public.user_ratings),
    'user_notifications', (select count(*) from public.user_notifications),
    'app_presence', (select count(*) from public.app_presence),
    'user_devices', (select count(*) from public.user_devices),
    'live_matches', (select count(*) from public.live_matches),
    'live_match_servers', (select count(*) from public.live_match_servers)
  );

  return jsonb_build_object(
    'database_bytes', v_database_bytes,
    'storage_bytes', v_storage_bytes,
    'storage_files', v_storage_files,
    'table_counts', v_table_counts
  );
end;
$function$;

revoke all on function public.shamflix_usage_metrics() from public, anon, authenticated;
grant execute on function public.shamflix_usage_metrics() to service_role;
