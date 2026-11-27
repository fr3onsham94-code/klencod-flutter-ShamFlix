-- Trial-only migration: multi-category support for TV channels.
-- This file is intentionally committed to the test branch only and is NOT applied
-- to the production Supabase project by this change.
create table if not exists public.channel_categories (
  id uuid primary key default gen_random_uuid(),
  channel_id uuid not null references public.channels(id) on delete cascade,
  category text not null check (length(btrim(category)) between 1 and 80),
  created_at timestamptz not null default now(),
  constraint channel_categories_channel_category_key unique (channel_id, category)
);

create index if not exists channel_categories_category_idx
  on public.channel_categories (category);

-- Preserve the current single-category value for every existing channel.
insert into public.channel_categories (channel_id, category)
select id, btrim(category)
from public.channels
where category is not null and btrim(category) <> ''
on conflict (channel_id, category) do nothing;

alter table public.channel_categories enable row level security;

grant select on public.channel_categories to anon, authenticated;
grant insert, update, delete on public.channel_categories to authenticated;

drop policy if exists "Published channel categories visible" on public.channel_categories;
create policy "Published channel categories visible"
  on public.channel_categories
  for select
  to anon, authenticated
  using (
    exists (
      select 1 from public.channels c
      where c.id = channel_categories.channel_id
        and (c.is_published = true or public.is_app_admin())
    )
  );

drop policy if exists "Admins manage channel categories" on public.channel_categories;
create policy "Admins manage channel categories"
  on public.channel_categories
  for all
  to authenticated
  using (public.is_app_admin())
  with check (public.is_app_admin());
