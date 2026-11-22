create table if not exists public.content_packages (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(trim(name)) > 0),
  content_type text not null check (content_type in ('movie', 'series', 'channel')),
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (content_type, name)
);

create table if not exists public.content_package_items (
  id uuid primary key default gen_random_uuid(),
  package_id uuid not null references public.content_packages(id) on delete cascade,
  content_type text not null check (content_type in ('movie', 'series', 'channel')),
  content_id uuid not null,
  created_at timestamptz not null default now(),
  unique (package_id, content_type, content_id)
);

create index if not exists content_packages_type_order_idx
  on public.content_packages(content_type, sort_order, name);
create index if not exists content_package_items_content_idx
  on public.content_package_items(content_type, content_id);
create index if not exists content_package_items_package_idx
  on public.content_package_items(package_id);

alter table public.movies add column if not exists backdrop_url text;
alter table public.movies add column if not exists director text;
alter table public.movies add column if not exists cast_names text;
alter table public.movies add column if not exists runtime_minutes integer;
alter table public.series add column if not exists backdrop_url text;
alter table public.series add column if not exists director text;
alter table public.series add column if not exists cast_names text;

alter table public.content_packages enable row level security;
alter table public.content_package_items enable row level security;

grant select on public.content_packages to anon, authenticated;
grant select on public.content_package_items to anon, authenticated;
grant insert, update, delete on public.content_packages to authenticated;
grant insert, update, delete on public.content_package_items to authenticated;

drop policy if exists "Public can read content packages" on public.content_packages;
create policy "Public can read content packages"
  on public.content_packages for select to anon, authenticated using (true);

drop policy if exists "Admins manage content packages" on public.content_packages;
create policy "Admins manage content packages"
  on public.content_packages for all to authenticated
  using ((select auth.jwt() -> 'app_metadata' ->> 'role') = 'admin')
  with check ((select auth.jwt() -> 'app_metadata' ->> 'role') = 'admin');

drop policy if exists "Public can read package items" on public.content_package_items;
create policy "Public can read package items"
  on public.content_package_items for select to anon, authenticated using (true);

drop policy if exists "Admins manage package items" on public.content_package_items;
create policy "Admins manage package items"
  on public.content_package_items for all to authenticated
  using ((select auth.jwt() -> 'app_metadata' ->> 'role') = 'admin')
  with check ((select auth.jwt() -> 'app_metadata' ->> 'role') = 'admin');

create or replace function public.ensure_content_package_type()
returns trigger language plpgsql set search_path = public as $$
declare expected_type text;
begin
  select content_type into expected_type from public.content_packages where id = new.package_id;
  if expected_type is null or expected_type <> new.content_type then
    raise exception 'Package type does not match content type';
  end if;
  return new;
end;
$$;

drop trigger if exists content_package_type_guard on public.content_package_items;
create trigger content_package_type_guard
before insert or update of package_id, content_type on public.content_package_items
for each row execute function public.ensure_content_package_type();

create or replace function public.cleanup_content_package_items()
returns trigger language plpgsql set search_path = public as $$
begin
  delete from public.content_package_items
  where content_type = tg_argv[0] and content_id = old.id;
  return old;
end;
$$;

drop trigger if exists cleanup_movie_package_items on public.movies;
create trigger cleanup_movie_package_items after delete on public.movies
for each row execute function public.cleanup_content_package_items('movie');

drop trigger if exists cleanup_series_package_items on public.series;
create trigger cleanup_series_package_items after delete on public.series
for each row execute function public.cleanup_content_package_items('series');

drop trigger if exists cleanup_channel_package_items on public.channels;
create trigger cleanup_channel_package_items after delete on public.channels
for each row execute function public.cleanup_content_package_items('channel');

insert into public.app_settings(setting_key, setting_value)
values ('app_invite_link', to_jsonb(''::text))
on conflict (setting_key) do nothing;

insert into public.app_settings(setting_key, setting_value)
values ('app_update', '{"version":"1.0.0","apk_url":""}'::jsonb)
on conflict (setting_key) do nothing;

-- ShamFlix - آخر تحديث: 21-11-2026: إنشاء جداول الباقات وحقول تفاصيل الأفلام والمسلسلات.
