-- Keep the newest heartbeat for each device session and enforce one row per session.
with ranked as (
  select id,
         row_number() over (
           partition by session_id
           order by last_seen desc, created_at desc, id desc
         ) as row_number
  from public.app_presence
)
delete from public.app_presence p
using ranked r
where p.id = r.id and r.row_number > 1;

-- Remove abandoned sessions older than 30 days.
delete from public.app_presence
where last_seen < now() - interval '30 days';

create unique index if not exists app_presence_session_id_uidx
  on public.app_presence (session_id);

-- ShamFlix - آخر تعديل: إزالة سجلات heartbeat المكررة وضمان صف واحد لكل جلسة | 22/11/2026.
