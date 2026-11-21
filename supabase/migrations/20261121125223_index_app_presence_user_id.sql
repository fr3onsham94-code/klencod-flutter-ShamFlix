create index if not exists app_presence_user_id_idx
  on public.app_presence (user_id);
drop index if exists public.app_presence_session_last_seen_idx;
