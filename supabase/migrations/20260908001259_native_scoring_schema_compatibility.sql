-- The native migration history predates web Scoring v2. Provide only the two
-- additive compatibility columns required by the native atomic command/journal
-- contract before 20260908001300 compiles. This does not enable v2 scoring.
begin;
alter table public.sd_games
  add column if not exists scoring_schema_version integer not null default 1
    check (scoring_schema_version in (1, 2));
alter table public.sd_game_scorekeeper_sessions
  add column if not exists authority_epoch bigint not null default 1
    check (authority_epoch > 0);
commit;
