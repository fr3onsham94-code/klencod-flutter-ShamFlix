alter table public.movies
  add column if not exists source_page_url text;

create unique index if not exists movies_source_page_url_unique
  on public.movies (source_page_url)
  where source_page_url is not null;

create table if not exists public.movie_source_monitors (
  id uuid primary key default gen_random_uuid(),
  package_id uuid not null references public.content_packages(id) on delete cascade,
  source_url text not null,
  source_host text not null,
  category text,
  check_interval_minutes integer not null default 60 check (check_interval_minutes between 15 and 1440),
  is_active boolean not null default true,
  last_checked_at timestamptz,
  last_error text,
  last_added_count integer not null default 0 check (last_added_count >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint movie_source_monitors_unique_source unique (package_id, source_url),
  constraint movie_source_monitors_http_url check (source_url ~* '^https?://')
);

create index if not exists idx_movie_source_monitors_active
  on public.movie_source_monitors (is_active, last_checked_at)
  where is_active = true;

alter table public.movie_source_monitors enable row level security;
grant select, insert, update, delete on public.movie_source_monitors to authenticated;

drop policy if exists "Admins manage movie source monitors" on public.movie_source_monitors;
create policy "Admins manage movie source monitors"
  on public.movie_source_monitors
  for all
  to authenticated
  using (public.is_app_admin())
  with check (public.is_app_admin());

select cron.schedule(
  'shamflix-movie-auto-monitor',
  '*/30 * * * *',
  $job$
    select net.http_post(
      url := (select decrypted_secret from vault.decrypted_secrets where name = 'shamflix_series_monitor_project_url_v1') || '/functions/v1/movie-auto-monitor',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-shamflix-monitor-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'shamflix_series_monitor_cron_secret_v1')
      ),
      body := jsonb_build_object('triggered_at', now()),
      timeout_milliseconds := 120000
    );
  $job$
);
