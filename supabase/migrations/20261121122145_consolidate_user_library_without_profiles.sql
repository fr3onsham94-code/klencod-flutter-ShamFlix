with ranked as (
  select
    id,
    row_number() over (
      partition by user_id, collection, content_type, content_id
      order by updated_at desc, id desc
    ) as row_number
  from public.user_library
)
delete from public.user_library
where id in (select id from ranked where row_number > 1);

update public.user_library
set profile_id = 'main'
where profile_id <> 'main';

-- ShamFlix - آخر تحديث: 21-11-2026: دمج بيانات المفضلة والسجل من الملفات القديمة إلى المكتبة الرئيسية.
