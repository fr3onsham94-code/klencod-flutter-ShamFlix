create or replace function public.is_app_admin()
returns boolean
language sql
stable
set search_path = public
as $$
  select
    auth.uid() = 'dda16adb-3b6e-4244-a028-83df88b7801d'::uuid
    or coalesce(
      (auth.jwt() -> 'app_metadata' ->> 'role') in ('admin', 'manager'),
      false
    );
$$;

grant execute on function public.is_app_admin() to authenticated;
