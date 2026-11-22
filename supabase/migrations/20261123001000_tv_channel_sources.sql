create table if not exists public.tv_channel_sources (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(btrim(name)) between 1 and 80),
  playlist_url text not null unique check (playlist_url ~* '^https://'),
  is_active boolean not null default true,
  last_checked_at timestamptz,
  last_error text,
  last_entry_count integer not null default 0 check (last_entry_count >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists tv_channel_sources_active_idx
  on public.tv_channel_sources (is_active, created_at);

alter table public.tv_channel_sources enable row level security;

grant select, insert, update, delete on public.tv_channel_sources to authenticated;

drop policy if exists "Admins manage TV channel sources" on public.tv_channel_sources;
create policy "Admins manage TV channel sources"
  on public.tv_channel_sources
  for all
  to authenticated
  using (public.is_app_admin())
  with check (public.is_app_admin());