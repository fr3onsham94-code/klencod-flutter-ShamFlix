alter table public.live_match_sources drop constraint if exists live_match_sources_check_interval_minutes_check;
alter table public.live_match_sources add constraint live_match_sources_check_interval_minutes_check check (check_interval_minutes >= 5 and check_interval_minutes <= 1440);
