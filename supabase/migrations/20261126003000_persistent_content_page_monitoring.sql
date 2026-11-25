-- Persist individual public source pages and monitoring state for movies,
-- series and episodes. Existing content and playback servers are preserved.
alter table public.movies
  add column if not exists source_monitor_enabled boolean not null default true,
  add column if not exists source_monitor_interval_minutes integer not null default 60
    check (source_monitor_interval_minutes between 15 and 1440),
  add column if not exists source_page_checked_at timestamptz,
  add column if not exists source_page_last_error text;

alter table public.series
  add column if not exists source_monitor_enabled boolean not null default true,
  add column if not exists source_monitor_interval_minutes integer not null default 60
    check (source_monitor_interval_minutes between 15 and 1440),
  add column if not exists source_page_checked_at timestamptz,
  add column if not exists source_page_last_error text;

alter table public.episodes
  add column if not exists source_page_url text,
  add column if not exists source_monitor_enabled boolean not null default true,
  add column if not exists source_monitor_interval_minutes integer not null default 60
    check (source_monitor_interval_minutes between 15 and 1440),
  add column if not exists source_page_checked_at timestamptz,
  add column if not exists source_page_last_error text;

create index if not exists idx_movies_source_page_monitor
  on public.movies (source_page_checked_at)
  where source_page_url is not null and source_monitor_enabled = true;

create index if not exists idx_series_source_page_monitor
  on public.series (source_page_checked_at)
  where source_page_url is not null and source_monitor_enabled = true;

create index if not exists idx_episodes_source_page_monitor
  on public.episodes (source_page_checked_at)
  where source_page_url is not null and source_monitor_enabled = true;

-- Tag only links discovered from a particular source page so refreshes never
-- disable manually-entered playback servers.
alter table public.playback_servers
  add column if not exists source_page_url text;

create index if not exists idx_playback_servers_source_page
  on public.playback_servers (source_page_url)
  where source_page_url is not null;
