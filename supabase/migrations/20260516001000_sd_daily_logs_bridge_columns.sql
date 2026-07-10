-- Add Shiny-compat daily log fields onto the iOS-native `sd_daily_logs` table.
-- iOS can ignore these; they exist so `public.daily_logs` compat view can be 1:1.

alter table public.sd_daily_logs
  add column if not exists sc_followed_program int,
  add column if not exists sc_lifts text,
  add column if not exists sc_session_rpe numeric,
  add column if not exists hit_did_bp int,
  add column if not exists hit_bp_minutes numeric,
  add column if not exists hit_feel_1_10 numeric,
  add column if not exists hit_feel_notes text,
  add column if not exists hit_pitch_type text,
  add column if not exists hit_environment_competitive int,
  add column if not exists hit_avg_exit_velo numeric,
  add column if not exists notes text,
  add column if not exists sa_completed_at timestamptz;

create index if not exists idx_sd_daily_logs_date on public.sd_daily_logs(log_date);

