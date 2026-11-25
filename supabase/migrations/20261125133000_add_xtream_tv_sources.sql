-- Xtream credentials and imported M3U files are managed independently per source.
alter table public.tv_channel_sources
  alter column playlist_url drop not null;

alter table public.tv_channel_sources
  add column if not exists source_type text not null default 'm3u_url',
  add column if not exists xtream_server_url text,
  add column if not exists xtream_username text,
  add column if not exists xtream_password text,
  add column if not exists playlist_storage_path text;

alter table public.tv_channel_sources
  add constraint tv_channel_sources_source_type_check
  check (source_type in ('m3u_url', 'xtream', 'm3u_file'));

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'tv-source-playlists',
  'tv-source-playlists',
  false,
  25165824,
  array['text/plain', 'application/octet-stream', 'application/vnd.apple.mpegurl', 'application/x-mpegurl']
)
on conflict (id) do update
set public = false, file_size_limit = 25165824,
    allowed_mime_types = excluded.allowed_mime_types;

create policy "Admins can read TV source playlist files"
on storage.objects for select to authenticated
using (bucket_id = 'tv-source-playlists' and public.is_app_admin());

create policy "Admins can upload TV source playlist files"
on storage.objects for insert to authenticated
with check (bucket_id = 'tv-source-playlists' and public.is_app_admin());

create policy "Admins can update TV source playlist files"
on storage.objects for update to authenticated
using (bucket_id = 'tv-source-playlists' and public.is_app_admin())
with check (bucket_id = 'tv-source-playlists' and public.is_app_admin());

create policy "Admins can delete TV source playlist files"
on storage.objects for delete to authenticated
using (bucket_id = 'tv-source-playlists' and public.is_app_admin());

comment on column public.tv_channel_sources.xtream_password is
  'Xtream credential; visible only to authorized app admins through the protected tv_channel_sources table.';
