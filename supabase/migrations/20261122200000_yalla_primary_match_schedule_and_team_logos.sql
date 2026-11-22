-- Make Yalla Shoot the sole authoritative source for match schedule data.
-- fel3ardaa.one remains active only to discover playback servers for existing matches.

alter table public.live_matches
  add column if not exists home_team_logo_url text,
  add column if not exists away_team_logo_url text;

update public.live_match_sources
set
  source_name = 'Yalla Shoot - المصدر الأساسي للجدول',
  base_url = 'https://yalla-shoot.ltd/matches-today/',
  is_active = true,
  allowed_redirect_hosts = array(
    select distinct host
    from unnest(
      coalesce(allowed_redirect_hosts, array[]::text[])
      || array['a5.pandab-hd.com']::text[]
    ) as host
  ),
  parser_config = coalesce(parser_config, '{}'::jsonb)
    || jsonb_build_object('allow_new_matches', true, 'timezone_offset_minutes', 120),
  updated_at = now()
where parser_key = 'yalla_shoot_ltd_cards';

-- m-yala may continue to enrich matches already created by Yalla Shoot,
-- but it must not create new schedule entries.
update public.live_match_sources
set
  source_name = 'm-yala - مصدر ثانوي للمطابقة',
  parser_config = coalesce(parser_config, '{}'::jsonb)
    || jsonb_build_object('allow_new_matches', false),
  updated_at = now()
where parser_key = 'm_yala_wordpress_cards';

-- fel3ardaa is used exclusively for playback-server discovery.
update public.live_match_sources
set
  source_name = 'fel3ardaa - سيرفرات البث فقط',
  parser_config = coalesce(parser_config, '{}'::jsonb)
    || jsonb_build_object('allow_new_matches', false, 'servers_only', true),
  updated_at = now()
where parser_key = 'fel3ardaa_json_api';
