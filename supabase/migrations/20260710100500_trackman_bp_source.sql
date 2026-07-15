-- TrackMan uses the same normalized BP session/event storage as Rapsodo and HitTrax.
-- Expand the source constraint without changing existing session data.
alter table public.sd_bp_sessions
  drop constraint if exists sd_bp_sessions_source_check;

alter table public.sd_bp_sessions
  add constraint sd_bp_sessions_source_check
  check (source in ('rapsodo', 'hitrax', 'trackman'));
