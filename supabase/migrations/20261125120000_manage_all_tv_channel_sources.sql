-- Manage built-in and user-added TV playlist sources from the admin panel.
alter table public.tv_channel_sources
  add column if not exists source_key text,
  add column if not exists is_builtin boolean not null default false;

create unique index if not exists tv_channel_sources_source_key_uidx
  on public.tv_channel_sources(source_key)
  where source_key is not null;

insert into public.tv_channel_sources (source_key, is_builtin, name, playlist_url, is_active)
values
('iptv-org',true,'IPTV-ORG PRIMARY','https://iptv-org.github.io/iptv/index.m3u',true),
('iptv-org-country-dz',true,'IPTV-ORG COUNTRY DZ','https://iptv-org.github.io/iptv/countries/dz.m3u',true),
('iptv-org-country-bh',true,'IPTV-ORG COUNTRY BH','https://iptv-org.github.io/iptv/countries/bh.m3u',true),
('iptv-org-country-km',true,'IPTV-ORG COUNTRY KM','https://iptv-org.github.io/iptv/countries/km.m3u',true),
('iptv-org-country-eg',true,'IPTV-ORG COUNTRY EG','https://iptv-org.github.io/iptv/countries/eg.m3u',true),
('iptv-org-country-iq',true,'IPTV-ORG COUNTRY IQ','https://iptv-org.github.io/iptv/countries/iq.m3u',true),
('iptv-org-country-jo',true,'IPTV-ORG COUNTRY JO','https://iptv-org.github.io/iptv/countries/jo.m3u',true),
('iptv-org-country-kw',true,'IPTV-ORG COUNTRY KW','https://iptv-org.github.io/iptv/countries/kw.m3u',true),
('iptv-org-country-lb',true,'IPTV-ORG COUNTRY LB','https://iptv-org.github.io/iptv/countries/lb.m3u',true),
('iptv-org-country-ly',true,'IPTV-ORG COUNTRY LY','https://iptv-org.github.io/iptv/countries/ly.m3u',true),
('iptv-org-country-mr',true,'IPTV-ORG COUNTRY MR','https://iptv-org.github.io/iptv/countries/mr.m3u',true),
('iptv-org-country-ma',true,'IPTV-ORG COUNTRY MA','https://iptv-org.github.io/iptv/countries/ma.m3u',true),
('iptv-org-country-om',true,'IPTV-ORG COUNTRY OM','https://iptv-org.github.io/iptv/countries/om.m3u',true),
('iptv-org-country-ps',true,'IPTV-ORG COUNTRY PS','https://iptv-org.github.io/iptv/countries/ps.m3u',true),
('iptv-org-country-qa',true,'IPTV-ORG COUNTRY QA','https://iptv-org.github.io/iptv/countries/qa.m3u',true),
('iptv-org-country-sa',true,'IPTV-ORG COUNTRY SA','https://iptv-org.github.io/iptv/countries/sa.m3u',true),
('iptv-org-country-so',true,'IPTV-ORG COUNTRY SO','https://iptv-org.github.io/iptv/countries/so.m3u',true),
('iptv-org-country-sd',true,'IPTV-ORG COUNTRY SD','https://iptv-org.github.io/iptv/countries/sd.m3u',true),
('iptv-org-country-sy',true,'IPTV-ORG COUNTRY SY','https://iptv-org.github.io/iptv/countries/sy.m3u',true),
('iptv-org-country-tn',true,'IPTV-ORG COUNTRY TN','https://iptv-org.github.io/iptv/countries/tn.m3u',true),
('iptv-org-country-ae',true,'IPTV-ORG COUNTRY AE','https://iptv-org.github.io/iptv/countries/ae.m3u',true),
('iptv-org-country-ye',true,'IPTV-ORG COUNTRY YE','https://iptv-org.github.io/iptv/countries/ye.m3u',true),
('iptv-org-country-tr',true,'IPTV-ORG COUNTRY TR','https://iptv-org.github.io/iptv/countries/tr.m3u',true),
('free-tv',true,'FREE-TV','https://raw.githubusercontent.com/Free-TV/IPTV/master/playlist.m3u8',true),
('nexus',true,'IPTV-NEXUS','https://dearbulut.github.io/iptv/playlists/index.m3u',true),
('tdtchannels',true,'TDTCHANNELS TV M3U8','https://www.tdtchannels.com/lists/tv.m3u8',true),
('tdtchannels-m3u',true,'TDTCHANNELS TV M3U','https://www.tdtchannels.com/lists/tv.m3u',true),
('m3ucl-total',true,'M3U.CL TOTAL','https://www.m3u.cl/lista/total.m3u',true),
('m3ucl-music',true,'M3U.CL MUSIC','https://www.m3u.cl/lista/musica.m3u',true),
('m3ucl-religious',true,'M3U.CL RELIGIOUS','https://www.m3u.cl/lista/religiosos.m3u',true),
('m3ucl-ar',true,'M3U.CL ARGENTINA','https://www.m3u.cl/lista/AR.m3u',true),
('m3ucl-bo',true,'M3U.CL BOLIVIA','https://www.m3u.cl/lista/BO.m3u',true),
('m3ucl-br',true,'M3U.CL BRAZIL','https://www.m3u.cl/lista/BR.m3u',true),
('m3ucl-cl',true,'M3U.CL CHILE','https://www.m3u.cl/lista/CL.m3u',true),
('m3ucl-co',true,'M3U.CL COLOMBIA','https://www.m3u.cl/lista/CO.m3u',true),
('m3ucl-ec',true,'M3U.CL ECUADOR','https://www.m3u.cl/lista/EC.m3u',true),
('m3ucl-es',true,'M3U.CL SPAIN','https://www.m3u.cl/lista/ES.m3u',true),
('m3ucl-mx',true,'M3U.CL MEXICO','https://www.m3u.cl/lista/MX.m3u',true),
('m3ucl-py',true,'M3U.CL PARAGUAY','https://www.m3u.cl/lista/PY.m3u',true),
('m3ucl-pe',true,'M3U.CL PERU','https://www.m3u.cl/lista/PE.m3u',true),
('m3ucl-do',true,'M3U.CL DOMINICAN REPUBLIC','https://www.m3u.cl/lista/DO.m3u',true),
('m3ucl-ve',true,'M3U.CL VENEZUELA','https://www.m3u.cl/lista/VE.m3u',true)
on conflict do nothing;

comment on column public.tv_channel_sources.source_key is
  'Stable identifier for built-in playlist sources; null for user-added sources.';
comment on column public.tv_channel_sources.is_builtin is
  'Built-in sources can be paused or resumed but cannot be deleted from the admin UI.';
