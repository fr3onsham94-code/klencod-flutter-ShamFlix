-- Store per-server request headers and optional DRM metadata for TV channels.
alter table public.playback_servers
  add column if not exists user_agent text,
  add column if not exists referer text,
  add column if not exists origin text,
  add column if not exists cookie text,
  add column if not exists drm_key text,
  add column if not exists license_url text;

comment on column public.playback_servers.user_agent is 'Optional User-Agent request header for this playback server.';
comment on column public.playback_servers.referer is 'Optional Referer request header for this playback server.';
comment on column public.playback_servers.origin is 'Optional Origin request header for this playback server.';
comment on column public.playback_servers.cookie is 'Optional Cookie request header for this playback server.';
comment on column public.playback_servers.drm_key is 'Optional DRM key metadata; playback requires a compatible DRM implementation.';
comment on column public.playback_servers.license_url is 'Optional DRM license server URL; playback requires a compatible DRM implementation.';
