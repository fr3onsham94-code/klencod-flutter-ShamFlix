do $$
declare
  grp record;
  duplicate_id uuid;
begin
  for grp in
    with automatic_channels as (
      select distinct c.id, c.name, c.name_en
      from public.channels c
      join public.content_package_items i
        on i.content_id = c.id and i.content_type = 'channel'
      join public.content_packages p
        on p.id = i.package_id
       and p.content_type = 'channel'
       and p.name like 'قنوات تلقائية — %'
    ),
    normalized as (
      select id,
        regexp_replace(
          regexp_replace(
            lower(coalesce(name_en, name)),
            '\s*\(?\s*(sd|hd|fhd|uhd|4k|8k|[0-9]{3,4}p)\s*\)?\s*$', '', 'gi'
          ),
          '\s*[ⓈⒼⓅⒽⓊⓢⓖⓟⓗⓤ]+$', '', 'g'
        ) as display_base
      from automatic_channels
    ),
    keyed as (
      select id,
        regexp_replace(
          translate(display_base, 'أإآىة', 'ااايه'),
          '[^[:alnum:]ء-يğüşöçıİı]', '', 'g'
        ) as base_name
      from normalized
    )
    select base_name,
      (array_agg(id order by id))[1] as keeper_id,
      array_agg(id order by id) as ids
    from keyed
    where base_name <> ''
    group by base_name
    having count(*) > 1
  loop
    foreach duplicate_id in array grp.ids loop
      if duplicate_id <> grp.keeper_id then
        delete from public.playback_servers d
        using public.playback_servers k
        where d.channel_id = duplicate_id
          and k.channel_id = grp.keeper_id
          and d.stream_url = k.stream_url
          and d.source_id is not distinct from k.source_id;

        update public.playback_servers
          set channel_id = grp.keeper_id
        where channel_id = duplicate_id;

        delete from public.content_package_items d
        using public.content_package_items k
        where d.content_id = duplicate_id
          and k.content_id = grp.keeper_id
          and d.package_id = k.package_id
          and d.content_type = k.content_type;

        update public.content_package_items
          set content_id = grp.keeper_id
        where content_id = duplicate_id
          and content_type = 'channel';

        update public.channels keeper
          set logo_url = coalesce(keeper.logo_url, duplicate.logo_url)
        from public.channels duplicate
        where keeper.id = grp.keeper_id
          and duplicate.id = duplicate_id;

        delete from public.channels where id = duplicate_id;
      end if;
    end loop;

    update public.channels
      set external_source_key = 'name:' || grp.base_name,
          name = regexp_replace(
            regexp_replace(name,
              '\s*\(?\s*(sd|hd|fhd|uhd|4k|8k|[0-9]{3,4}p)\s*\)?\s*$', '', 'gi'),
            '\s*[ⓈⒼⓅⒽⓊⓢⓖⓟⓗⓤ]+$', '', 'g'),
          name_en = regexp_replace(
            regexp_replace(coalesce(name_en, name),
              '\s*\(?\s*(sd|hd|fhd|uhd|4k|8k|[0-9]{3,4}p)\s*\)?\s*$', '', 'gi'),
            '\s*[ⓈⒼⓅⒽⓊⓢⓖⓟⓗⓤ]+$', '', 'g'),
          updated_at = now()
    where id = grp.keeper_id;
  end loop;

  -- Align every remaining automatically packaged channel with the same
  -- normalized-name key used by the importer, so future syncs update in place.
  with automatic_channels as (
    select distinct c.id, c.name, c.name_en
    from public.channels c
    join public.content_package_items i
      on i.content_id = c.id and i.content_type = 'channel'
    join public.content_packages p
      on p.id = i.package_id
     and p.content_type = 'channel'
     and p.name like 'قنوات تلقائية — %'
  ),
  normalized as (
    select id,
      regexp_replace(
        regexp_replace(
          lower(coalesce(name_en, name)),
          '\s*\(?\s*(sd|hd|fhd|uhd|4k|8k|[0-9]{3,4}p)\s*\)?\s*$', '', 'gi'
        ),
        '\s*[ⓈⒼⓅⒽⓊⓢⓖⓟⓗⓤ]+$', '', 'g'
      ) as display_base
    from automatic_channels
  ),
  keyed as (
    select id,
      regexp_replace(
        translate(display_base, 'أإآىة', 'ااايه'),
        '[^[:alnum:]ء-يğüşöçıİı]', '', 'g'
      ) as base_name
    from normalized
  )
  update public.channels c
    set external_source_key = 'name:' || k.base_name,
        updated_at = now()
  from keyed k
  where c.id = k.id
    and k.base_name <> '';
end $$;