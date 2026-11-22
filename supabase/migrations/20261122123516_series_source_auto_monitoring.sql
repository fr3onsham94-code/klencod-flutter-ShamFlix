create table if not exists public.series_source_monitors (
  id uuid primary key default gen_random_uuid(),
  series_id uuid not null references public.series(id) on delete cascade,
  source_url text not null,
  source_host text not null,
  season_number integer not null default 1 check (season_number >= 1),
  check_interval_minutes integer not null default 60 check (check_interval_minutes between 15 and 1440),
  is_active boolean not null default true,
  last_checked_at timestamptz,
  last_error text,
  last_added_count integer not null default 0 check (last_added_count >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint series_source_monitors_unique_source unique (series_id, source_url),
  constraint series_source_monitors_http_url check (source_url ~* '^https?://')
);

create index if not exists idx_series_source_monitors_active
  on public.series_source_monitors (is_active, last_checked_at)
  where is_active = true;

alter table public.series_source_monitors enable row level security;

grant select, insert, update, delete on public.series_source_monitors to authenticated;

drop policy if exists "Admins manage series source monitors" on public.series_source_monitors;
create policy "Admins manage series source monitors"
  on public.series_source_monitors
  for all
  to authenticated
  using (public.is_app_admin())
  with check (public.is_app_admin());
