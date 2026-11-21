-- Content packages: public read, admin/manager writes.
drop policy if exists "Admins and managers manage content packages" on public.content_packages;
create policy "Admins and managers insert content packages" on public.content_packages
  for insert to authenticated with check (public.is_app_admin());
create policy "Admins and managers update content packages" on public.content_packages
  for update to authenticated using (public.is_app_admin()) with check (public.is_app_admin());
create policy "Admins and managers delete content packages" on public.content_packages
  for delete to authenticated using (public.is_app_admin());

drop policy if exists "Admins and managers manage package items" on public.content_package_items;
create policy "Admins and managers insert package items" on public.content_package_items
  for insert to authenticated with check (public.is_app_admin());
create policy "Admins and managers update package items" on public.content_package_items
  for update to authenticated using (public.is_app_admin()) with check (public.is_app_admin());
create policy "Admins and managers delete package items" on public.content_package_items
  for delete to authenticated using (public.is_app_admin());

drop policy if exists "Admins and managers manage movies" on public.movies;
drop policy if exists "Published movies visible" on public.movies;
create policy "Published movies visible" on public.movies
  for select to anon, authenticated using (is_published = true or public.is_app_admin());
create policy "Admins and managers insert movies" on public.movies
  for insert to authenticated with check (public.is_app_admin());
create policy "Admins and managers update movies" on public.movies
  for update to authenticated using (public.is_app_admin()) with check (public.is_app_admin());
create policy "Admins and managers delete movies" on public.movies
  for delete to authenticated using (public.is_app_admin());

drop policy if exists "Admins and managers manage series" on public.series;
drop policy if exists "Published series visible" on public.series;
create policy "Published series visible" on public.series
  for select to anon, authenticated using (is_published = true or public.is_app_admin());
create policy "Admins and managers insert series" on public.series
  for insert to authenticated with check (public.is_app_admin());
create policy "Admins and managers update series" on public.series
  for update to authenticated using (public.is_app_admin()) with check (public.is_app_admin());
create policy "Admins and managers delete series" on public.series
  for delete to authenticated using (public.is_app_admin());

drop policy if exists "Admins and managers manage channels" on public.channels;
drop policy if exists "Published channels visible" on public.channels;
create policy "Published channels visible" on public.channels
  for select to anon, authenticated using (is_published = true or public.is_app_admin());
create policy "Admins and managers insert channels" on public.channels
  for insert to authenticated with check (public.is_app_admin());
create policy "Admins and managers update channels" on public.channels
  for update to authenticated using (public.is_app_admin()) with check (public.is_app_admin());
create policy "Admins and managers delete channels" on public.channels
  for delete to authenticated using (public.is_app_admin());

drop policy if exists "Admins and managers manage seasons" on public.seasons;
drop policy if exists "Published seasons visible" on public.seasons;
create policy "Published seasons visible" on public.seasons
  for select to anon, authenticated using (
    public.is_app_admin() or exists (
      select 1 from public.series s where s.id = seasons.series_id and s.is_published = true
    )
  );
create policy "Admins and managers insert seasons" on public.seasons
  for insert to authenticated with check (public.is_app_admin());
create policy "Admins and managers update seasons" on public.seasons
  for update to authenticated using (public.is_app_admin()) with check (public.is_app_admin());
create policy "Admins and managers delete seasons" on public.seasons
  for delete to authenticated using (public.is_app_admin());

drop policy if exists "Admins and managers manage episodes" on public.episodes;
drop policy if exists "Published episodes visible" on public.episodes;
create policy "Published episodes visible" on public.episodes
  for select to anon, authenticated using (
    public.is_app_admin() or (
      is_published = true and exists (
        select 1 from public.seasons se
        join public.series s on s.id = se.series_id
        where se.id = episodes.season_id and s.is_published = true
      )
    )
  );
create policy "Admins and managers insert episodes" on public.episodes
  for insert to authenticated with check (public.is_app_admin());
create policy "Admins and managers update episodes" on public.episodes
  for update to authenticated using (public.is_app_admin()) with check (public.is_app_admin());
create policy "Admins and managers delete episodes" on public.episodes
  for delete to authenticated using (public.is_app_admin());

drop policy if exists "Admins and managers manage playback servers" on public.playback_servers;
drop policy if exists "Published content playback servers visible" on public.playback_servers;
create policy "Published content playback servers visible" on public.playback_servers
  for select to anon, authenticated using (
    public.is_app_admin() or (
      is_active = true and (
        (movie_id is not null and exists (select 1 from public.movies m where m.id = playback_servers.movie_id and m.is_published = true))
        or (channel_id is not null and exists (select 1 from public.channels c where c.id = playback_servers.channel_id and c.is_published = true))
        or (episode_id is not null and exists (
          select 1 from public.episodes e
          join public.seasons se on se.id = e.season_id
          join public.series s on s.id = se.series_id
          where e.id = playback_servers.episode_id and e.is_published = true and s.is_published = true
        ))
      )
    )
  );
create policy "Admins and managers insert playback servers" on public.playback_servers
  for insert to authenticated with check (public.is_app_admin());
create policy "Admins and managers update playback servers" on public.playback_servers
  for update to authenticated using (public.is_app_admin()) with check (public.is_app_admin());
create policy "Admins and managers delete playback servers" on public.playback_servers
  for delete to authenticated using (public.is_app_admin());

-- ShamFlix - آخر تحديث: 21-11-2026: تحسين سياسات قراءة المحتوى وكتابته.
