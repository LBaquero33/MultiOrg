-- RLS policies for `sd_` tables (auth.uid()-based).

create or replace function public.sd_is_coach(uid uuid)
returns boolean
language sql
stable
as $$
  select exists (
    select 1 from public.profiles p
    where p.id = uid and p.role = 'coach'
  );
$$;

-- PROGRAM TEMPLATES
alter table public.sd_program_templates enable row level security;
drop policy if exists "sd_program_templates_select" on public.sd_program_templates;
create policy "sd_program_templates_select"
on public.sd_program_templates
for select
using (
  coach_id = auth.uid()
  or public.sd_is_coach(auth.uid())
  or exists (
    select 1 from public.sd_program_assignments a
    where a.template_id = sd_program_templates.id
      and a.player_id = auth.uid()
      and a.ended_at is null
  )
);

drop policy if exists "sd_program_templates_insert" on public.sd_program_templates;
create policy "sd_program_templates_insert"
on public.sd_program_templates
for insert
with check (coach_id = auth.uid() and public.sd_is_coach(auth.uid()));

drop policy if exists "sd_program_templates_update" on public.sd_program_templates;
create policy "sd_program_templates_update"
on public.sd_program_templates
for update
using (coach_id = auth.uid() and public.sd_is_coach(auth.uid()))
with check (coach_id = auth.uid() and public.sd_is_coach(auth.uid()));

-- PROGRAM DAYS
alter table public.sd_program_days enable row level security;
drop policy if exists "sd_program_days_select" on public.sd_program_days;
create policy "sd_program_days_select"
on public.sd_program_days
for select
using (
  exists (
    select 1 from public.sd_program_templates t
    where t.id = template_id
      and (
        t.coach_id = auth.uid()
        or public.sd_is_coach(auth.uid())
        or exists (
          select 1 from public.sd_program_assignments a
          where a.template_id = t.id
            and a.player_id = auth.uid()
            and a.ended_at is null
        )
      )
  )
);

drop policy if exists "sd_program_days_write" on public.sd_program_days;
create policy "sd_program_days_write"
on public.sd_program_days
for all
using (
  exists (select 1 from public.sd_program_templates t where t.id = template_id and t.coach_id = auth.uid() and public.sd_is_coach(auth.uid()))
)
with check (
  exists (select 1 from public.sd_program_templates t where t.id = template_id and t.coach_id = auth.uid() and public.sd_is_coach(auth.uid()))
);

-- ASSIGNMENTS
alter table public.sd_program_assignments enable row level security;
drop policy if exists "sd_assignments_select" on public.sd_program_assignments;
create policy "sd_assignments_select"
on public.sd_program_assignments
for select
using (
  player_id = auth.uid()
  or public.sd_is_coach(auth.uid())
);

drop policy if exists "sd_assignments_insert" on public.sd_program_assignments;
create policy "sd_assignments_insert"
on public.sd_program_assignments
for insert
with check (coach_id = auth.uid() and public.sd_is_coach(auth.uid()));

drop policy if exists "sd_assignments_update" on public.sd_program_assignments;
create policy "sd_assignments_update"
on public.sd_program_assignments
for update
using (coach_id = auth.uid() and public.sd_is_coach(auth.uid()))
with check (coach_id = auth.uid() and public.sd_is_coach(auth.uid()));

-- DAILY LOGS (player writes; coach reads)
alter table public.sd_daily_logs enable row level security;
drop policy if exists "sd_daily_logs_select" on public.sd_daily_logs;
create policy "sd_daily_logs_select"
on public.sd_daily_logs
for select
using (
  player_id = auth.uid()
  or public.sd_is_coach(auth.uid())
);

drop policy if exists "sd_daily_logs_write_own" on public.sd_daily_logs;
create policy "sd_daily_logs_write_own"
on public.sd_daily_logs
for all
using (player_id = auth.uid())
with check (player_id = auth.uid());

-- STRENGTH LOGS (player writes; coach reads)
alter table public.sd_strength_logs enable row level security;
drop policy if exists "sd_strength_logs_select" on public.sd_strength_logs;
create policy "sd_strength_logs_select"
on public.sd_strength_logs
for select
using (
  player_id = auth.uid()
  or public.sd_is_coach(auth.uid())
);

drop policy if exists "sd_strength_logs_write_own" on public.sd_strength_logs;
create policy "sd_strength_logs_write_own"
on public.sd_strength_logs
for all
using (player_id = auth.uid())
with check (player_id = auth.uid());

-- TESTING (player writes; coach reads)
alter table public.sd_testing_entries enable row level security;
drop policy if exists "sd_testing_select" on public.sd_testing_entries;
create policy "sd_testing_select"
on public.sd_testing_entries
for select
using (
  player_id = auth.uid()
  or public.sd_is_coach(auth.uid())
);

drop policy if exists "sd_testing_write_own" on public.sd_testing_entries;
create policy "sd_testing_write_own"
on public.sd_testing_entries
for all
using (player_id = auth.uid())
with check (player_id = auth.uid());

-- BP (player writes; coach reads)
alter table public.sd_bp_sessions enable row level security;
alter table public.sd_bp_events enable row level security;

drop policy if exists "sd_bp_sessions_select" on public.sd_bp_sessions;
create policy "sd_bp_sessions_select"
on public.sd_bp_sessions
for select
using (player_id = auth.uid() or public.sd_is_coach(auth.uid()));

drop policy if exists "sd_bp_sessions_write_own" on public.sd_bp_sessions;
create policy "sd_bp_sessions_write_own"
on public.sd_bp_sessions
for all
using (player_id = auth.uid())
with check (player_id = auth.uid());

drop policy if exists "sd_bp_events_select" on public.sd_bp_events;
create policy "sd_bp_events_select"
on public.sd_bp_events
for select
using (
  exists (
    select 1 from public.sd_bp_sessions s
    where s.id = sd_bp_events.session_id
      and (s.player_id = auth.uid() or public.sd_is_coach(auth.uid()))
  )
);

drop policy if exists "sd_bp_events_write_own" on public.sd_bp_events;
create policy "sd_bp_events_write_own"
on public.sd_bp_events
for all
using (
  exists (select 1 from public.sd_bp_sessions s where s.id = sd_bp_events.session_id and s.player_id = auth.uid())
)
with check (
  exists (select 1 from public.sd_bp_sessions s where s.id = sd_bp_events.session_id and s.player_id = auth.uid())
);

