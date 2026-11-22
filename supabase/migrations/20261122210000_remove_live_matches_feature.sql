-- Permanently remove the ShamFlix "Matches Today" feature.
-- The live-match tables contain only feature-specific data and are no longer used.

do $$
declare
  match_job_id bigint;
begin
  select jobid into match_job_id
  from cron.job
  where jobname = 'shamflix-live-matches-hourly'
  limit 1;

  if match_job_id is not null then
    perform cron.unschedule(match_job_id);
  end if;
end
$$;

delete from public.content_package_items
where package_id in (
  select id
  from public.content_packages
  where name = 'مباريات اليوم'
    and content_type = 'channel'
);

delete from public.content_packages
where name = 'مباريات اليوم'
  and content_type = 'channel';

drop table if exists
  public.live_match_servers,
  public.live_match_source_events,
  public.live_match_sources,
  public.live_matches
cascade;
