-- Enable Supabase Realtime "postgres_changes" for facility bookings.
-- Needed for coach in-app notifications on booking requests.

do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'sd_facility_bookings'
  ) then
    execute 'alter publication supabase_realtime add table public.sd_facility_bookings';
  end if;
end $$;

