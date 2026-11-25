-- Manage built-in and user-added TV playlist sources from the admin panel.
alter table public.tv_channel_sources
  add column if not exists source_key text,
  add column if not exists is_builtin boolean not null default false;

create unique index if not exists tv_channel_sources_source_key_uidx
  on public.tv_channel_sources(source_key)
  where source_key is not null;

insert into public.tv_channel_sources (source_key, is_builtin, name, playlist_url, is_active)
values
('iptv-org','IPTV-ORG PRIMARY','https://iptv-org.github.io/iptv/index.m3u'),
('iptv-org-country-dz','IPTV-ORG COUNTRY DZ','https://iptv-org.github.io/iptv/countries/dz.m3u'),
('iptv-org-country-bh','IPTV-ORG COUNTRY BH','https://iptv-org.github.io/iptv/countries/bh.m3u'),
('iptv-org-country-km','IPTV-ORG COUNTRY KM','https://iptv-org.github.io/iptv/countries/km.m3u'),
('iptv-org-country-eg','IPTV-ORG COUNTRY EG','https://iptv-org.github.io/iptv/countries/eg.m3u'),
('iptv-org-country-iq','IPTV-ORG COUNTRY IQ','https://iptv-org.github.io/iptv/countries/iq.m3u'),
('iptv-org-country-jo','IPTV-ORG COUNTRY JO','https://iptv-org.github.io/iptv/countries/jo.m3u'),
('iptv-org-country-kw','IPTV-ORG COUNTRY KW','https://iptv-org.github.io/iptv/countries/kw.m3u'),
('iptv-org-country-lb','IPTV-ORG COUNTRY LB','https://iptv-org.github.io/iptv/countries/lb.m3u'),
('iptv-org-country-ly','IPTV-ORG COUNTRY LY','https://iptv-org.github.io/iptv/countries/ly.m3u'),
('iptv-org-country-mr','IPTV-ORG COUNTRY MR','https://iptv-org.github.io/iptv/countries/mr.m3u'),
('iptv-org-country-ma','IPTV-ORG COUNTRY MA','https://iptv-org.github.io/iptv/countries/ma.m3u'),
('iptv-org-country-om','IPTV-ORG COUNTRY OM','https://iptv-org.github.io/iptv/countries/om.m3u'),
('iptv-org-country-ps','IPTV-ORG COUNTRY PS','https://iptv-org.github.io/iptv/countries/ps.m3u'),
('iptv-org-country-qa','IPTV-ORG COUNTRY QA','https://iptv-org.github.io/iptv/countries/qa.m3u'),
('iptv-org-country-sa','IPTV-ORG COUNTRY SA','https://iptv-org.github.io/iptv/countries/sa.m3u'),
('iptv-org-country-so','IPTV-ORG COUNTRY SO','https://iptv-org.github.io/iptv/countries/so.m3u'),
('iptv-org-country-sd','IPTV-ORG COUNTRY SD','https://iptv-org.github.io/iptv/countries/sd.m3u'),
('iptv-org-country-sy','IPTV-ORG COUNTRY SY','https://iptv-org.github.io/iptv/countries/sy.m3u'),
('iptv-org-country-tn','IPTV-ORG COUNTRY TN','https://iptv-org.github.io/iptv/countries/tn.m3u'),
('iptv-org-country-ae','IPTV-ORG COUNTRY AE','https://iptv-org.github.io/iptv/countries/ae.m3u'),
('iptv-org-country-ye','IPTV-ORG COUNTRY YE','https://iptv-org.github.io/iptv/countries/ye.m3u'),
('iptv-org-country-tr','IPTV-ORG COUNTRY TR','https://iptv-org.github.io/iptv/countries/tr.m3u'),
('free-tv','FREE-TV','https://raw.githubusercontent.com/Free-TV/IPTV/master/playlist.m3u8'),
('nexus','IPTV-NEXUS','https://dearbulut.github.io/iptv/playlists/index.m3u'),
('tdtchannels','TDTCHANNELS TV M3U8','https://www.tdtchannels.com/lists/tv.m3u8'),
('tdtchannels-m3u','TDTCHANNELS TV M3U','https://www.tdtchannels.com/lists/tv.m3u'),
('m3ucl-total','M3U.CL TOTAL','https://www.m3u.cl/lista/total.m3u'),
('m3ucl-music','M3U.CL MUSIC','https://www.m3u.cl/lista/musica.m3u'),
('m3ucl-religious','M3U.CL RELIGIOUS','https://www.m3u.cl/lista/religiosos.m3u'),
('m3ucl-ar','M3U.CL ARGENTINA','https://www.m3u.cl/lista/AR.m3u'),
('m3ucl-bo','M3U.CL BOLIVIA','https://www.m3u.cl/lista/BO.m3u'),
('m3ucl-br','M3U.CL BRAZIL','https://www.m3u.cl/lista/BR.m3u'),
('m3ucl-cl','M3U.CL CHILE','https://www.m3u.cl/lista/CL.m3u'),
('m3ucl-co','M3U.CL COLOMBIA','https://www.m3u.cl/lista/CO.m3u'),
('m3ucl-ec','M3U.CL ECUADOR','https://www.m3u.cl/lista/EC.m3u'),
('m3ucl-es','M3U.CL SPAIN','https://www.m3u.cl/lista/ES.m3u'),
('m3ucl-mx','M3U.CL MEXICO','https://www.m3u.cl/lista/MX.m3u'),
('m3ucl-py','M3U.CL PARAGUAY','https://www.m3u.cl/lista/PY.m3u'),
('m3ucl-pe','M3U.CL PERU','https://www.m3u.cl/lista/PE.m3u'),
('m3ucl-do','M3U.CL DOMINICAN REPUBLIC','https://www.m3u.cl/lista/DO.m3u'),
('m3ucl-ve','M3U.CL VENEZUELA','https://www.m3u.cl/lista/VE.m3u')
on conflict (source_key) where source_key is not null do nothing;

comment on column public.tv_channel_sources.source_key is
  'Stable identifier for built-in playlist sources; null for user-added sources.';
comment on column public.tv_channel_sources.is_builtin is
  'Built-in sources can be paused or resumed but cannot be deleted from the admin UI.';
