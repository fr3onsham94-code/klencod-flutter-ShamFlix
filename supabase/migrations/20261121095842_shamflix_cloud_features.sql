-- ShamFlix cloud features: user sync, ratings, notifications and device registrations.
create table if not exists public.user_library (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  profile_id text not null default 'main',
  collection text not null check (collection in ('favorites','history')),
  content_type text not null check (content_type in ('movie','series','episode','channel')),
  content_id text not null,
  payload jsonb not null default '{}'::jsonb,
  progress_ms bigint not null default 0 check (progress_ms >= 0),
  updated_at timestamptz not null default now(),
  unique (user_id, profile_id, collection, content_type, content_id)
);
create index if not exists user_library_sync_idx on public.user_library(user_id, profile_id, collection, updated_at desc);

create table if not exists public.user_profiles (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  profile_id text not null,
  name text not null,
  updated_at timestamptz not null default now(),
  unique (user_id, profile_id)
);

create table if not exists public.user_ratings (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  content_type text not null check (content_type in ('movie','series','channel')),
  content_id text not null,
  rating smallint not null check (rating between 1 and 5),
  reaction text not null default 'none' check (reaction in ('none','like','dislike')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, content_type, content_id)
);
create index if not exists user_ratings_content_idx on public.user_ratings(content_type, content_id);

create table if not exists public.user_notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  content_type text not null,
  content_id text not null,
  title text not null,
  body text not null default '',
  is_read boolean not null default false,
  created_at timestamptz not null default now()
);
create index if not exists user_notifications_user_idx on public.user_notifications(user_id, created_at desc);

create table if not exists public.user_devices (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  device_token text not null,
  platform text not null default 'android',
  updated_at timestamptz not null default now(),
  unique (user_id, device_token)
);

alter table public.user_library enable row level security;
alter table public.user_profiles enable row level security;
alter table public.user_ratings enable row level security;
alter table public.user_notifications enable row level security;
alter table public.user_devices enable row level security;

grant select, insert, update, delete on public.user_library to authenticated;
grant select, insert, update, delete on public.user_profiles to authenticated;
grant select, insert, update, delete on public.user_ratings to authenticated;
grant select, update, delete on public.user_notifications to authenticated;
grant select, insert, update, delete on public.user_devices to authenticated;

drop policy if exists "Users manage own library" on public.user_library;
create policy "Users manage own library" on public.user_library for all to authenticated
using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
drop policy if exists "Users manage own profiles" on public.user_profiles;
create policy "Users manage own profiles" on public.user_profiles for all to authenticated
using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
drop policy if exists "Users manage own ratings" on public.user_ratings;
create policy "Users manage own ratings" on public.user_ratings for all to authenticated
using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
drop policy if exists "Users read own notifications" on public.user_notifications;
create policy "Users read own notifications" on public.user_notifications for select to authenticated
using ((select auth.uid()) = user_id);
drop policy if exists "Users update own notifications" on public.user_notifications;
create policy "Users update own notifications" on public.user_notifications for update to authenticated
using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
drop policy if exists "Users delete own notifications" on public.user_notifications;
create policy "Users delete own notifications" on public.user_notifications for delete to authenticated
using ((select auth.uid()) = user_id);
drop policy if exists "Users manage own devices" on public.user_devices;
create policy "Users manage own devices" on public.user_devices for all to authenticated
using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);

create or replace function public.notify_users_new_content()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare item_title text; item_type text; item_id text;
begin
  item_type := TG_ARGV[0];
  item_id := new.id::text;
  item_title := coalesce(to_jsonb(new)->>'title', to_jsonb(new)->>'name', 'محتوى جديد');
  insert into public.user_notifications(user_id, content_type, content_id, title, body)
  select u.id, item_type, item_id, item_title,
    case when item_type = 'episode' then 'تمت إضافة حلقة جديدة' else 'تمت إضافة محتويات جديدة إلى ShamFlix' end
  from auth.users u
  where not exists (select 1 from public.user_notifications n
    where n.user_id = u.id and n.content_type = item_type and n.content_id = item_id);
  return new;
end;
$$;
revoke all on function public.notify_users_new_content() from public, anon, authenticated;

drop trigger if exists notify_new_movie on public.movies;
create trigger notify_new_movie after insert on public.movies for each row when (new.is_published = true)
execute function public.notify_users_new_content('movie');
drop trigger if exists notify_new_series on public.series;
create trigger notify_new_series after insert on public.series for each row when (new.is_published = true)
execute function public.notify_users_new_content('series');
drop trigger if exists notify_new_episode on public.episodes;
create trigger notify_new_episode after insert on public.episodes for each row when (new.is_published = true)
execute function public.notify_users_new_content('episode');
drop trigger if exists notify_new_channel on public.channels;
create trigger notify_new_channel after insert on public.channels for each row when (new.is_published = true)
execute function public.notify_users_new_content('channel');



create table if not exists public.content_rating_stats (
  content_type text not null, content_id text not null, average numeric not null default 0,
  rating_count bigint not null default 0, likes bigint not null default 0, dislikes bigint not null default 0,
  updated_at timestamptz not null default now(), primary key (content_type, content_id)
);
alter table public.content_rating_stats enable row level security;
grant select on public.content_rating_stats to anon, authenticated;
drop policy if exists "Public can read rating summaries" on public.content_rating_stats;
create policy "Public can read rating summaries" on public.content_rating_stats
for select to anon, authenticated using (true);
create or replace function public.refresh_content_rating_stats(p_type text, p_id text)
returns void language plpgsql security definer set search_path = ''
as $$
begin
  insert into public.content_rating_stats(content_type, content_id, average, rating_count, likes, dislikes, updated_at)
  select p_type, p_id, coalesce(avg(rating), 0), count(*)::bigint,
         count(*) filter (where reaction = 'like')::bigint,
         count(*) filter (where reaction = 'dislike')::bigint, now()
  from public.user_ratings where content_type = p_type and content_id = p_id
  on conflict (content_type, content_id) do update
  set average = excluded.average, rating_count = excluded.rating_count,
      likes = excluded.likes, dislikes = excluded.dislikes, updated_at = now();
end;
$$;
revoke all on function public.refresh_content_rating_stats(text, text) from public, anon, authenticated;
create or replace function public.handle_user_rating_stats()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  if TG_OP = 'DELETE' then
    perform public.refresh_content_rating_stats(old.content_type, old.content_id); return old;
  elsif TG_OP = 'UPDATE' then
    perform public.refresh_content_rating_stats(new.content_type, new.content_id);
    if old.content_type is distinct from new.content_type or old.content_id is distinct from new.content_id then
      perform public.refresh_content_rating_stats(old.content_type, old.content_id);
    end if;
    return new;
  else
    perform public.refresh_content_rating_stats(new.content_type, new.content_id); return new;
  end if;
end;
$$;
revoke all on function public.handle_user_rating_stats() from public, anon, authenticated;
drop trigger if exists user_rating_stats_trigger on public.user_ratings;
create trigger user_rating_stats_trigger after insert or update or delete on public.user_ratings
for each row execute function public.handle_user_rating_stats();

drop trigger if exists notify_published_movie on public.movies;
create trigger notify_published_movie after update of is_published on public.movies
for each row when (new.is_published = true and old.is_published is distinct from new.is_published)
execute function public.notify_users_new_content('movie');
drop trigger if exists notify_published_series on public.series;
create trigger notify_published_series after update of is_published on public.series
for each row when (new.is_published = true and old.is_published is distinct from new.is_published)
execute function public.notify_users_new_content('series');
drop trigger if exists notify_published_episode on public.episodes;
create trigger notify_published_episode after update of is_published on public.episodes
for each row when (new.is_published = true and old.is_published is distinct from new.is_published)
execute function public.notify_users_new_content('episode');
drop trigger if exists notify_published_channel on public.channels;
create trigger notify_published_channel after update of is_published on public.channels
for each row when (new.is_published = true and old.is_published is distinct from new.is_published)
execute function public.notify_users_new_content('channel');

-- ShamFlix - آخر تحديث: 21-11-2026: جداول مزامنة المستخدمين والتقييمات والإشعارات وملخصات التقييم.
