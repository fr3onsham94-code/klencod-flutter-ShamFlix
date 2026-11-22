-- Automatic aggregation of free-to-air TV channels from approved public playlists.
alter table public.channels
  add column if not exists external_source_key text,
  add column if not exists name_en text,
  add column if not exists aliases text[] not null default '{}';

create unique index if not exists channels_external_source_key_uidx
  on public.channels(external_source_key)
  where external_source_key is not null;

alter table public.playback_servers
  add column if not exists source_key text,
  add column if not exists source_id text,
  add column if not exists source_checked_at timestamptz,
  add column if not exists source_failures integer not null default 0;

create unique index if not exists playback_servers_source_key_uidx
  on public.playback_servers(source_key)
  where source_key is not null;

create index if not exists playback_servers_source_health_idx
  on public.playback_servers(source_id, source_checked_at)
  where source_id is not null;

-- Public clients already read active playback_servers and published channels.
-- Source-managed rows are written only by the Edge Function using service_role.
