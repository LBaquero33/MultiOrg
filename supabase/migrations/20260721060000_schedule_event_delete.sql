-- Phase 14C: preserve an explicit audit record when authorized schedule staff
-- permanently delete an event. Event authorization and deletion remain in the
-- existing team-scheduling contract; this only extends its audit vocabulary.

alter table public.sd_team_event_audit_logs
  drop constraint if exists sd_team_event_audit_logs_action_check;
alter table public.sd_team_event_audit_logs
  add constraint sd_team_event_audit_logs_action_check check (action in (
    'created','published','edited','rescheduled','cancelled','draft_deleted',
    'recurrence_changed','series_cancelled','conflict_override',
    'visibility_changed','duplicated','postponed','deleted'
  ));
