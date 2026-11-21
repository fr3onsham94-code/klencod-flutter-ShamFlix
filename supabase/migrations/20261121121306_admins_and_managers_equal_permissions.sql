create or replace function public.is_app_admin()
returns boolean
language sql
stable
set search_path = public
as $$
  select coalesce(
    (auth.jwt() -> 'app_metadata' ->> 'role') in ('admin', 'manager'),
    false
  );
$$;

grant execute on function public.is_app_admin() to authenticated;

drop policy if exists "Admins can insert app settings" on public.app_settings;
create policy "Admins and managers can insert app settings"
  on public.app_settings for insert to authenticated
  with check (public.is_app_admin());

drop policy if exists "Admins can update app settings" on public.app_settings;
create policy "Admins and managers can update app settings"
  on public.app_settings for update to authenticated
  using (public.is_app_admin())
  with check (public.is_app_admin());

drop policy if exists "Admins manage channels" on public.channels;
create policy "Admins and managers manage channels"
  on public.channels for all to authenticated
  using (public.is_app_admin())
  with check (public.is_app_admin());

drop policy if exists "Admins manage episodes" on public.episodes;
create policy "Admins and managers manage episodes"
  on public.episodes for all to authenticated
  using (public.is_app_admin())
  with check (public.is_app_admin());

drop policy if exists "Admins manage movies" on public.movies;
create policy "Admins and managers manage movies"
  on public.movies for all to authenticated
  using (public.is_app_admin())
  with check (public.is_app_admin());

drop policy if exists "Admins manage playback servers" on public.playback_servers;
create policy "Admins and managers manage playback servers"
  on public.playback_servers for all to authenticated
  using (public.is_app_admin())
  with check (public.is_app_admin());

drop policy if exists "Admins manage seasons" on public.seasons;
create policy "Admins and managers manage seasons"
  on public.seasons for all to authenticated
  using (public.is_app_admin())
  with check (public.is_app_admin());

drop policy if exists "Admins manage series" on public.series;
create policy "Admins and managers manage series"
  on public.series for all to authenticated
  using (public.is_app_admin())
  with check (public.is_app_admin());

drop policy if exists "Admins manage content packages" on public.content_packages;
create policy "Admins and managers manage content packages"
  on public.content_packages for all to authenticated
  using (public.is_app_admin())
  with check (public.is_app_admin());

drop policy if exists "Admins manage package items" on public.content_package_items;
create policy "Admins and managers manage package items"
  on public.content_package_items for all to authenticated
  using (public.is_app_admin())
  with check (public.is_app_admin());

-- ShamFlix - آخر تحديث: 21-11-2026: توحيد صلاحيات المدير والأدمن.
