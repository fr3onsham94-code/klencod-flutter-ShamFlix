-- Allow M3U uploads whose Android/Flutter MIME resolver reports audio/x-mpegurl.
-- Keep the bucket private and preserve its existing size and MIME restrictions.
update storage.buckets
set allowed_mime_types = array(
  select distinct mime_type
  from unnest(coalesce(allowed_mime_types, array[]::text[])) as mime_type
  union
  select 'audio/x-mpegurl'
)
where id = 'tv-source-playlists';
