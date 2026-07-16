# Player Development Import UI

The staff-only workspace opens from a player’s Player Development AI header. It uses existing Home Plate header cards, cards, status badges, buttons, fields, loading states, and empty states.

The workflow selects a CSV/TSV and provider label, uploads privately, displays detected delimiter/headers/counts, chooses wide or long shape, maps player/date/metric/value/unit/sample fields, optionally saves or reuses an exact-header profile, previews normalized rows, filters validation states, resolves an unmatched row to the open player, explicitly confirms commit, and shows import history/archive controls.

The preview always states “Preview only — no player development data has been imported.” Confirmation explains that the backend revalidates and will not run reports, alerts, notifications, or APNs. After dismissing the import workspace, Player Development AI refreshes evidence; report generation remains explicit.

Organization/user context changes reset the model, selected job, inspection, preview, mapping profiles, definitions, messages, and commit guard. Each async result carries a context token and stale results are ignored.
