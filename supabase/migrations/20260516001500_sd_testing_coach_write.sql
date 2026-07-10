-- Allow coaches to add/edit testing entries for players (Shiny parity).
-- Keeps player write permissions intact.

drop policy if exists "sd_testing_write_coach" on public.sd_testing_entries;
create policy "sd_testing_write_coach"
on public.sd_testing_entries
for all
using (public.sd_is_coach(auth.uid()))
with check (public.sd_is_coach(auth.uid()));

