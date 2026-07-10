-- Keep legacy bridge views server-only and make the chat summary view obey
-- the caller's RLS policies. The Swift app reads the native sd_* tables.

alter view public.sd_chat_channel_last_message set (security_invoker = true);

revoke all on table public.dev_entries from anon, authenticated;
revoke all on table public.bp_sessions from anon, authenticated;
revoke all on table public.bp_pitch_events from anon, authenticated;
revoke all on table public.daily_logs from anon, authenticated;

-- The bridge is for an explicitly configured server-side legacy integration.
grant select, insert, update, delete on table public.dev_entries to service_role;
grant select, insert, update, delete on table public.bp_sessions to service_role;
grant select, insert, update, delete on table public.bp_pitch_events to service_role;
grant select, insert, update, delete on table public.daily_logs to service_role;
