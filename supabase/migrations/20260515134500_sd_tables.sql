-- Auth-UID based tables for the iOS "Self Development" app.
-- Prefixed with `sd_` to avoid collisions with existing DHD/SelfScout tables.

create extension if not exists pgcrypto;

create table if not exists public.sd_program_templates (
  id uuid primary key default gen_random_uuid(),
  coach_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  weeks int not null check (weeks in (2, 4)),
  lift_weekdays int[] not null default '{1,3,5}', -- Mon/Wed/Fri
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_sd_program_templates_coach on public.sd_program_templates(coach_id);

create table if not exists public.sd_program_days (
  id uuid primary key default gen_random_uuid(),
  template_id uuid not null references public.sd_program_templates(id) on delete cascade,
  week int not null check (week between 1 and 4),
  day_index int not null check (day_index between 1 and 6),
  -- json array of exercises in display order:
  -- [{ "name": "Trap Bar Deadlift", "sets": 3, "reps": "5", "unit": "lb", "notes": "" }]
  exercises jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (template_id, week, day_index)
);

create index if not exists idx_sd_program_days_template on public.sd_program_days(template_id);

create table if not exists public.sd_program_assignments (
  id uuid primary key default gen_random_uuid(),
  player_id uuid not null references auth.users(id) on delete cascade,
  coach_id uuid not null references auth.users(id) on delete cascade,
  template_id uuid not null references public.sd_program_templates(id) on delete restrict,
  start_date date not null,
  ended_at timestamptz,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_sd_program_assignments_player on public.sd_program_assignments(player_id);
create index if not exists idx_sd_program_assignments_active on public.sd_program_assignments(player_id, ended_at);

-- One daily log per player/date (calendar + self assessment + comments/feel)
create table if not exists public.sd_daily_logs (
  id uuid primary key default gen_random_uuid(),
  player_id uuid not null references auth.users(id) on delete cascade,
  log_date date not null,
  comments text,
  feel int check (feel between 1 and 10),
  got_video boolean,
  ate_breakfast boolean,
  hit_daily_goals boolean,
  stuck_to_process boolean,
  fell_short text,
  excelled text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (player_id, log_date)
);

create index if not exists idx_sd_daily_logs_player_date on public.sd_daily_logs(player_id, log_date);

-- Strength per-exercise logger (per-set weights)
create table if not exists public.sd_strength_logs (
  id uuid primary key default gen_random_uuid(),
  player_id uuid not null references auth.users(id) on delete cascade,
  log_date date not null,
  assignment_id uuid references public.sd_program_assignments(id) on delete set null,
  template_id uuid references public.sd_program_templates(id) on delete set null,
  week int,
  day_index int,
  exercise_name text not null,
  no_weight boolean not null default false,
  set_weights_json jsonb, -- ["185","185","195"]
  sets_completed int,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_sd_strength_logs_player_date on public.sd_strength_logs(player_id, log_date);

-- Testing entries (coach/player can input; used for trends)
create table if not exists public.sd_testing_entries (
  id uuid primary key default gen_random_uuid(),
  player_id uuid not null references auth.users(id) on delete cascade,
  entry_date date not null,
  height_in numeric,
  weight_lb numeric,
  squat_1rm numeric,
  bench_1rm numeric,
  deadlift_1rm numeric,
  max_exit_velo numeric,
  avg_exit_velo numeric,
  hip_er_diff numeric,
  hip_ir_diff numeric,
  shoulder_ir_diff numeric,
  shoulder_er_diff numeric,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (player_id, entry_date)
);

create index if not exists idx_sd_testing_entries_player_date on public.sd_testing_entries(player_id, entry_date);

-- BP sessions and pitch events (Rapsodo/HitTrax)
create table if not exists public.sd_bp_sessions (
  id uuid primary key default gen_random_uuid(),
  player_id uuid not null references auth.users(id) on delete cascade,
  session_date date not null,
  source text not null check (source in ('rapsodo','hitrax')),
  reps_type text not null default 'practice' check (reps_type in ('practice','game')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (player_id, session_date, source, reps_type)
);

create index if not exists idx_sd_bp_sessions_player_date on public.sd_bp_sessions(player_id, session_date);

create table if not exists public.sd_bp_events (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references public.sd_bp_sessions(id) on delete cascade,
  pitch_num int,
  exit_velo numeric,
  distance numeric,
  launch_angle numeric,
  strike_x numeric,
  strike_z numeric,
  raw jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists idx_sd_bp_events_session on public.sd_bp_events(session_id);

-- Updated-at trigger
create or replace function public.sd_set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_sd_program_templates_updated_at on public.sd_program_templates;
create trigger trg_sd_program_templates_updated_at before update on public.sd_program_templates
for each row execute function public.sd_set_updated_at();

drop trigger if exists trg_sd_program_days_updated_at on public.sd_program_days;
create trigger trg_sd_program_days_updated_at before update on public.sd_program_days
for each row execute function public.sd_set_updated_at();

drop trigger if exists trg_sd_program_assignments_updated_at on public.sd_program_assignments;
create trigger trg_sd_program_assignments_updated_at before update on public.sd_program_assignments
for each row execute function public.sd_set_updated_at();

drop trigger if exists trg_sd_daily_logs_updated_at on public.sd_daily_logs;
create trigger trg_sd_daily_logs_updated_at before update on public.sd_daily_logs
for each row execute function public.sd_set_updated_at();

drop trigger if exists trg_sd_strength_logs_updated_at on public.sd_strength_logs;
create trigger trg_sd_strength_logs_updated_at before update on public.sd_strength_logs
for each row execute function public.sd_set_updated_at();

drop trigger if exists trg_sd_testing_entries_updated_at on public.sd_testing_entries;
create trigger trg_sd_testing_entries_updated_at before update on public.sd_testing_entries
for each row execute function public.sd_set_updated_at();

drop trigger if exists trg_sd_bp_sessions_updated_at on public.sd_bp_sessions;
create trigger trg_sd_bp_sessions_updated_at before update on public.sd_bp_sessions
for each row execute function public.sd_set_updated_at();

