create table if not exists public.app_presence (
  id uuid primary key default gen_random_uuid(),
  session_id text not null check (char_length(session_id) between 12 and 128),
  user_id uuid null references auth.users(id) on delete set null,
  display_name text not null default 'زائر' check (char_length(display_name) <= 120),
  last_seen timestamptz not null default now(),
  created_at timestamptz not null default now()
);

create index if not exists app_presence_last_seen_idx
  on public.app_presence (last_seen desc);
create index if not exists app_presence_session_last_seen_idx
  on public.app_presence (session_id, last_seen desc);

alter table public.app_presence enable row level security;

grant insert on public.app_presence to anon, authenticated;
grant select, delete on public.app_presence to authenticated;

drop policy if exists "Visitors can register app presence" on public.app_presence;
create policy "Visitors can register app presence"
  on public.app_presence for insert to anon
  with check (user_id is null);

drop policy if exists "Signed-in users can register own app presence" on public.app_presence;
create policy "Signed-in users can register own app presence"
  on public.app_presence for insert to authenticated
  with check (user_id is not distinct from (select auth.uid()));

drop policy if exists "Admins can view app presence" on public.app_presence;
create policy "Admins can view app presence"
  on public.app_presence for select to authenticated
  using ((select public.is_app_admin()));

drop policy if exists "Admins can clean app presence" on public.app_presence;
create policy "Admins can clean app presence"
  on public.app_presence for delete to authenticated
  using ((select public.is_app_admin()));
