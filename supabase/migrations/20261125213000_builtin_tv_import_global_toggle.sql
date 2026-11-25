-- Global switch for built-in TV catalogue imports.
-- Individual source is_active values are intentionally preserved while the
-- global switch is off, so re-enabling restores each source's prior setting.
create table if not exists public.tv_source_global_settings (
  id text primary key,
  built_in_import_enabled boolean not null default true,
  updated_at timestamptz not null default now(),
  constraint tv_source_global_settings_singleton check (id = 'global')
);

alter table public.tv_source_global_settings enable row level security;

insert into public.tv_source_global_settings (id, built_in_import_enabled)
values ('global', true)
on conflict (id) do nothing;

comment on table public.tv_source_global_settings is
  'Private service-role settings for the global built-in TV source import switch.';
