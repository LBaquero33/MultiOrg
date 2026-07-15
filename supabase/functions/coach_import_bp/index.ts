// Supabase Edge Function: coach_import_bp
//
// Purpose:
// - Allow a COACH to upload/replace BP sessions + events for a player/day (server-side).
// - This avoids relaxing RLS to let coaches write to `sd_bp_sessions`/`sd_bp_events`.
//
// Required secrets (Supabase project → Edge Functions → Secrets):
// - SUPABASE_URL
// - SUPABASE_ANON_KEY
// - SUPABASE_SERVICE_ROLE_KEY   (NEVER expose to clients)
//
// Request body (JSON):
// {
//   "player_id": "uuid",
//   "session_date": "YYYY-MM-DD",
//   "source": "rapsodo" | "hitrax" | "trackman",
//   "reps_type": "practice" | "game",
//   "events": [
//     { "pitch_num": 1, "exit_velo": 90.1, "distance": 320, "launch_angle": 18, "strike_x": 0.2, "strike_z": 2.6, "raw": { ... } }
//   ]
// }
//
// Response:
// { "session_id": "uuid", "event_count": 123 }

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

type Json = Record<string, unknown>;

function json(status: number, body: Json) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });
}

function getEnv(name: string) {
  const v = Deno.env.get(name);
  return (v ?? "").trim();
}

function asText(x: unknown) {
  return String(x ?? "").trim();
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json(405, { error: "method_not_allowed" });

  const supabaseUrl = getEnv("SUPABASE_URL");
  const anonKey = getEnv("SUPABASE_ANON_KEY");
  const serviceKey = getEnv("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !anonKey || !serviceKey) return json(500, { error: "missing_supabase_secrets" });

  const authHeader = req.headers.get("authorization") ?? req.headers.get("Authorization") ?? "";
  if (!authHeader) return json(401, { error: "missing_authorization" });

  let payload: any;
  try {
    payload = await req.json();
  } catch {
    return json(400, { error: "invalid_json" });
  }

  const player_id = asText(payload.player_id);
  const session_date = asText(payload.session_date);
  const source = asText(payload.source);
  const reps_type = asText(payload.reps_type);
  const events = Array.isArray(payload.events) ? payload.events : [];

  if (!player_id || !session_date || !source || !reps_type) {
    return json(400, { error: "missing_fields" });
  }

  const userClient = createClient(supabaseUrl, anonKey, {
    auth: { persistSession: false, autoRefreshToken: false },
    global: { headers: { Authorization: authHeader } },
  });
  const { data: userData, error: userErr } = await userClient.auth.getUser();
  if (userErr) return json(401, { error: "invalid_auth", message: userErr.message });
  const uid = userData.user?.id ?? null;
  if (!uid) return json(401, { error: "no_user" });

  const admin = createClient(supabaseUrl, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  // Verify caller is a coach (profiles.role = 'coach')
  const { data: prof, error: profErr } = await admin.from("profiles").select("id, role").eq("id", uid).maybeSingle();
  if (profErr) return json(500, { error: "profile_lookup_failed", message: profErr.message });
  const role = String((prof as any)?.role ?? "").toLowerCase();
  if (role !== "coach") return json(403, { error: "forbidden" });

  // Upsert session
  const { data: sessionRow, error: sessErr } = await admin
    .from("sd_bp_sessions")
    .upsert(
      { player_id, session_date, source, reps_type },
      { onConflict: "player_id,session_date,source,reps_type" },
    )
    .select("id")
    .single();
  if (sessErr) return json(500, { error: "session_upsert_failed", message: sessErr.message });

  const session_id = (sessionRow as any)?.id;
  if (!session_id) return json(500, { error: "missing_session_id" });

  // Replace events (delete then insert)
  const { error: delErr } = await admin.from("sd_bp_events").delete().eq("session_id", session_id);
  if (delErr) return json(500, { error: "events_delete_failed", message: delErr.message });

  const insertRows = events.map((e: any) => ({
    session_id,
    pitch_num: e?.pitch_num ?? null,
    exit_velo: e?.exit_velo ?? null,
    distance: e?.distance ?? null,
    launch_angle: e?.launch_angle ?? null,
    strike_x: e?.strike_x ?? null,
    strike_z: e?.strike_z ?? null,
    raw: e?.raw ?? {},
  }));

  if (insertRows.length > 0) {
    const { error: insErr } = await admin.from("sd_bp_events").insert(insertRows);
    if (insErr) return json(500, { error: "events_insert_failed", message: insErr.message });
  }

  return json(200, { session_id, event_count: insertRows.length });
});
