-- Background monitoring runs and per-source status.
alter table public.movie_source_monitors
  add column if not exists last_status text not null default 'pending',
  add column if not exists last_run_id uuid not null default '00000000-0000-0000-0000-000000000000',
  add column if not exists last_started_at timestamptz,
  add column if not exists last_finished_at timestamptz;

alter table public.series_source_monitors
  add column if not exists last_status text not null default 'pending',
  add column if not exists last_run_id uuid not null default '00000000-0000-0000-0000-000000000000',
  add column if not exists last_started_at timestamptz,
  add column if not exists last_finished_at timestamptz;

alter table public.series_section_monitors
  add column if not exists last_status text not null default 'pending',
  add column if not exists last_run_id uuid not null default '00000000-0000-0000-0000-000000000000',
  add column if not exists last_started_at timestamptz,
  add column if not exists last_finished_at timestamptz;

alter table public.tv_channel_sources
  add column if not exists last_status text not null default 'pending',
  add column if not exists last_run_id uuid not null default '00000000-0000-0000-0000-000000000000',
  add column if not exists last_started_at timestamptz,
  add column if not exists last_finished_at timestamptz;

create index if not exists movie_source_monitors_last_run_idx
  on public.movie_source_monitors (is_active, last_run_id, last_checked_at);
create index if not exists series_source_monitors_last_run_idx
  on public.series_source_monitors (is_active, last_run_id, last_checked_at);
create index if not exists series_section_monitors_last_run_idx
  on public.series_section_monitors (is_active, last_run_id, last_checked_at);
create index if not exists tv_channel_sources_active_idx
  on public.tv_channel_sources (is_active, last_checked_at);

create table if not exists public.content_monitor_runs (
  id uuid primary key default gen_random_uuid(),
  triggered_by uuid references auth.users(id) on delete set null,
  status text not null default 'running'
    check (status in ('running','completed','partial','failed')),
  movies_done boolean not null default false,
  series_done boolean not null default false,
  channels_done boolean not null default false,
  movies_error text,
  series_error text,
  channels_error text,
  summary jsonb not null default '{}'::jsonb,
  started_at timestamptz not null default now(),
  finished_at timestamptz,
  created_at timestamptz not null default now()
);

create index if not exists content_monitor_runs_created_idx
  on public.content_monitor_runs (created_at desc);

alter table public.content_monitor_runs enable row level security;
grant select on public.content_monitor_runs to authenticated;
drop policy if exists "Admins can view content monitor runs" on public.content_monitor_runs;
create policy "Admins can view content monitor runs"
  on public.content_monitor_runs
  for select to authenticated
  using (public.is_app_admin());

-- Run short batches frequently; each source still respects its own 15-minute interval.
select cron.alter_job(1, schedule := '* * * * *');
select cron.alter_job(2, schedule := '* * * * *');
select cron.alter_job(4, schedule := '*/15 * * * *');
