import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import {
  identityKey,
  normalizePhoneLastFour,
  publicCheckInParticipant,
  sha256,
  verifyCheckInToken,
} from "../_shared/registration_public.ts";

type Row = Record<string, unknown>;

const corsHeaders = {
  "access-control-allow-origin": "*",
  "access-control-allow-headers":
    "authorization, x-client-info, apikey, content-type",
  "access-control-allow-methods": "POST, OPTIONS",
};
const json = (status: number, body: Row) =>
  new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "content-type": "application/json; charset=utf-8",
    },
  });
const ok = (body: Row) => json(200, { ok: true, ...body, error: null });
const fail = (status: number, code: string) =>
  json(status, {
    ok: false,
    error: { code, message: code },
  });
const text = (value: unknown, maximum = 500) =>
  String(value ?? "").trim().slice(0, maximum);
const record = (value: unknown): Row =>
  value && typeof value === "object" && !Array.isArray(value)
    ? value as Row
    : {};
const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const uuid = (value: unknown) =>
  uuidPattern.test(text(value)) ? text(value).toLowerCase() : null;

function serviceClient() {
  const url = text(
    Deno.env.get("SUPABASE_URL") ?? Deno.env.get("DHD_SUPABASE_URL"),
  );
  const service = text(
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ??
      Deno.env.get("DHD_SERVICE_ROLE_KEY"),
  );
  if (!url || !service) throw new Error("missing_supabase_secrets");
  return createClient(url, service, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

async function rateLimit(
  admin: ReturnType<typeof serviceClient>,
  request: Request,
  scope: string,
  limit: number,
) {
  const forwarded = text(request.headers.get("x-forwarded-for"), 160).split(
    ",",
  )[0]?.trim();
  const address = forwarded ||
    text(request.headers.get("cf-connecting-ip"), 80) || "unknown";
  const bucket = await sha256(`registration-public|${scope}|${address}`);
  const { data, error } = await admin.rpc("sd_public_request_allowed", {
    p_bucket_key: `registration:${bucket}`,
    p_limit: limit,
    p_window_seconds: 900,
  });
  if (error || data !== true) throw new Error("public_rate_limit_exceeded");
}

async function publicSite(
  admin: ReturnType<typeof serviceClient>,
  slugValue: unknown,
) {
  const slug = text(slugValue, 63).toLowerCase();
  if (!/^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$/.test(slug)) return null;
  const { data } = await admin.from("sd_public_sites").select(
    "id,org_id,slug,status",
  )
    .eq("slug", slug).eq("status", "published").maybeSingle();
  return data ?? null;
}

function randomToken(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(32));
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(
    /=+$/g,
    "",
  );
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsHeaders });
  }
  if (request.method !== "POST") return fail(405, "method_not_allowed");
  try {
    const payload = record(await request.json());
    const action = text(payload.action, 60);
    const admin = serviceClient();

    if (action === "list_public_offerings") {
      const site = await publicSite(admin, payload.site_slug);
      if (!site) return fail(404, "site_not_found");
      await rateLimit(admin, request, `offerings:${site.id}`, 120);
      const { data, error } = await admin.from("sd_registration_offerings")
        .select(
          "id,name,offering_type,description,format,opens_at,closes_at,capacity,waitlist_capacity,age_guidance,graduation_year_guidance,fee_cents,deposit_cents,refund_policy,location_id",
        )
        .eq("organization_id", site.org_id)
        .eq("public_visible", true)
        .in("state", ["published", "open", "registration_open"])
        .lte("opens_at", new Date().toISOString())
        .gte("closes_at", new Date().toISOString())
        .order("opens_at");
      if (error) throw new Error("public_offering_lookup_failed");
      return ok({ offerings: data ?? [] });
    }

    if (action === "list_individual_tryout_slots") {
      const site = await publicSite(admin, payload.site_slug);
      const offeringId = uuid(payload.offering_id);
      if (!site || !offeringId) return fail(400, "invalid_offering_request");
      await rateLimit(admin, request, `slots:${offeringId}`, 120);
      const { data: offering } = await admin.from("sd_registration_offerings")
        .select("id").eq("id", offeringId).eq("organization_id", site.org_id)
        .eq("public_visible", true).eq("format", "individual").maybeSingle();
      if (!offering) return fail(404, "offering_not_found");
      const { data, error } = await admin.from("sd_registration_sessions")
        .select("id,name,start_at,end_at,location_id,capacity")
        .eq("organization_id", site.org_id).eq("offering_id", offeringId)
        .eq("session_type", "individual").eq("status", "scheduled")
        .gte("start_at", new Date().toISOString()).order("start_at");
      if (error) throw new Error("public_slot_lookup_failed");
      const sessionIds = (data ?? []).map((row) => row.id);
      const { data: reservations } = sessionIds.length
        ? await admin.from("sd_registration_session_participants").select(
          "session_id",
        ).in("session_id", sessionIds)
        : { data: [] };
      const used = new Set(
        (reservations ?? []).map((row) => String(row.session_id)),
      );
      return ok({
        slots: (data ?? []).filter((row) => !used.has(String(row.id))),
      });
    }

    if (action === "submit_registration") {
      const site = await publicSite(admin, payload.site_slug);
      const offeringId = uuid(payload.offering_id);
      if (!site || !offeringId) return fail(400, "invalid_registration");
      await rateLimit(admin, request, `submit:${offeringId}`, 8);
      const displayName = text(payload.player_name, 160);
      const email = text(payload.email, 254).toLowerCase();
      const phone = text(payload.phone, 40);
      const birthYear = Number(payload.birth_year);
      if (
        !displayName || !email.includes("@") ||
        normalizePhoneLastFour(phone) === null
      ) {
        return fail(400, "registration_contact_required");
      }
      const { data: offering } = await admin.from("sd_registration_offerings")
        .select("id,organization_id,fee_cents,deposit_cents,capacity")
        .eq("id", offeringId).eq("organization_id", site.org_id)
        .eq("public_visible", true).lte("opens_at", new Date().toISOString())
        .gte("closes_at", new Date().toISOString()).maybeSingle();
      if (!offering) return fail(404, "offering_not_found");
      if (
        Number(offering.fee_cents) > 0 || Number(offering.deposit_cents) > 0
      ) {
        return fail(409, "registration_payment_form_required");
      }
      const identitySecret = text(
        Deno.env.get("REGISTRATION_IDENTITY_HMAC_SECRET"),
        500,
      );
      if (identitySecret.length < 24) {
        throw new Error("registration_identity_secret_required");
      }
      const key = await identityKey(identitySecret, site.org_id, {
        displayName,
        birthYear: Number.isInteger(birthYear) ? birthYear : null,
        email,
        phone,
      });
      const { data: prospect, error: prospectError } = await admin.from(
        "sd_registration_prospects",
      )
        .upsert({
          organization_id: site.org_id,
          identity_key: key,
          display_name: displayName,
          birth_year: Number.isInteger(birthYear) ? birthYear : null,
          graduation_year: Number.isInteger(Number(payload.graduation_year))
            ? Number(payload.graduation_year)
            : null,
          email,
          phone,
          positions: Array.isArray(payload.positions)
            ? payload.positions.map((item) => text(item, 40)).filter(Boolean)
              .slice(0, 12)
            : [],
        }, { onConflict: "organization_id,identity_key" }).select("id")
        .single();
      if (prospectError || !prospect) {
        throw new Error("registration_prospect_save_failed");
      }
      const accessToken = randomToken();
      const tokenHash = await sha256(accessToken);
      const { data: participant, error } = await admin.from(
        "sd_registration_participants",
      ).insert({
        organization_id: site.org_id,
        offering_id: offeringId,
        prospect_id: prospect.id,
        source_kind: "direct_public",
        public_access_token_hash: tokenHash,
        display_name: displayName,
        contact_email: email,
        contact_phone: phone,
        age_group: text(payload.age_group, 60) || null,
        graduation_year: Number.isInteger(Number(payload.graduation_year))
          ? Number(payload.graduation_year)
          : null,
        positions: Array.isArray(payload.positions)
          ? payload.positions.map((item) => text(item, 40)).filter(Boolean)
            .slice(0, 12)
          : [],
        public_answers: record(payload.answers),
        registration_status: "submitted",
        payment_status: "not_due",
      }).select("id,participant_number,registration_status,payment_status")
        .single();
      if (error || !participant) throw new Error("registration_save_failed");
      return ok({ registration: participant, access_token: accessToken });
    }

    if (action === "reserve_individual_slot") {
      const participantId = uuid(payload.participant_id);
      const sessionId = uuid(payload.session_id);
      const tokenHash = await sha256(text(payload.access_token, 500));
      if (!participantId || !sessionId) {
        return fail(400, "invalid_slot_request");
      }
      await rateLimit(admin, request, `reserve:${participantId}`, 12);
      const { data: participant } = await admin.from(
        "sd_registration_participants",
      )
        .select("id,organization_id,offering_id").eq("id", participantId)
        .eq("public_access_token_hash", tokenHash).maybeSingle();
      if (!participant) return fail(403, "registration_access_required");
      const { data: session } = await admin.from("sd_registration_sessions")
        .select("id").eq("id", sessionId).eq(
          "organization_id",
          participant.organization_id,
        )
        .eq("offering_id", participant.offering_id).eq(
          "session_type",
          "individual",
        )
        .eq("status", "scheduled").maybeSingle();
      if (!session) return fail(404, "registration_slot_not_found");
      const { error } = await admin.from("sd_registration_session_participants")
        .insert({ session_id: sessionId, participant_id: participantId });
      if (error) return fail(409, "registration_slot_unavailable");
      return ok({ reserved: true, session_id: sessionId });
    }

    if (action === "load_qr_checkin_roster") {
      const checkInSecret = text(
        Deno.env.get("REGISTRATION_CHECKIN_SIGNING_SECRET"),
        500,
      );
      const token = await verifyCheckInToken(
        checkInSecret,
        text(payload.token, 2_000),
      );
      if (!token) return fail(403, "checkin_link_invalid_or_expired");
      await rateLimit(admin, request, `roster:${token.session_id}`, 120);
      const { data: session } = await admin.from("sd_registration_sessions")
        .select(
          "id,name,start_at,end_at,checkin_opens_at,checkin_closes_at,offering_id,status",
        )
        .eq("id", token.session_id).eq("status", "scheduled").maybeSingle();
      if (!session) return fail(404, "checkin_session_not_found");
      const now = Date.now();
      if (
        (session.checkin_opens_at &&
          new Date(session.checkin_opens_at).valueOf() > now) ||
        (session.checkin_closes_at &&
          new Date(session.checkin_closes_at).valueOf() < now)
      ) return fail(409, "checkin_window_closed");
      const { data, error } = await admin.from("sd_registration_participants")
        .select("id,display_name,participant_number,age_group")
        .eq("offering_id", session.offering_id)
        .not("registration_status", "in", "(withdrawn,cancelled)")
        .order("participant_number");
      if (error) throw new Error("checkin_roster_lookup_failed");
      return ok({
        session: {
          id: session.id,
          name: session.name,
          start_at: session.start_at,
        },
        participants: (data ?? []).map(publicCheckInParticipant),
      });
    }

    if (action === "self_check_in") {
      const checkInSecret = text(
        Deno.env.get("REGISTRATION_CHECKIN_SIGNING_SECRET"),
        500,
      );
      const token = await verifyCheckInToken(
        checkInSecret,
        text(payload.token, 2_000),
      );
      const participantId = uuid(payload.participant_id);
      if (!token || !participantId) {
        return fail(403, "checkin_link_invalid_or_expired");
      }
      await rateLimit(
        admin,
        request,
        `checkin:${token.session_id}:${participantId}`,
        8,
      );
      const { data: session } = await admin.from("sd_registration_sessions")
        .select(
          "id,offering_id,organization_id,status,checkin_opens_at,checkin_closes_at",
        )
        .eq("id", token.session_id).eq("status", "scheduled").maybeSingle();
      if (!session) return fail(404, "checkin_session_not_found");
      const now = Date.now();
      if (
        (session.checkin_opens_at &&
          new Date(session.checkin_opens_at).valueOf() > now) ||
        (session.checkin_closes_at &&
          new Date(session.checkin_closes_at).valueOf() < now)
      ) return fail(409, "checkin_window_closed");
      const { data: participant } = await admin.from(
        "sd_registration_participants",
      )
        .select("id,contact_phone,participant_number,display_name")
        .eq("id", participantId).eq("organization_id", session.organization_id)
        .eq("offering_id", session.offering_id).maybeSingle();
      if (
        !participant ||
        normalizePhoneLastFour(participant.contact_phone) !==
          normalizePhoneLastFour(payload.phone_last_four)
      ) {
        return fail(403, "checkin_phone_confirmation_failed");
      }
      await admin.from("sd_registration_session_participants").upsert({
        session_id: session.id,
        participant_id: participant.id,
      }, { onConflict: "session_id,participant_id" });
      const { data: checkin, error } = await admin.from(
        "sd_registration_checkins",
      ).upsert({
        organization_id: session.organization_id,
        session_id: session.id,
        participant_id: participant.id,
        status: "present",
        checked_in_at: new Date().toISOString(),
        checked_in_by: null,
        source: "qr",
        request_id: uuid(payload.request_id) ?? crypto.randomUUID(),
      }, { onConflict: "session_id,participant_id" }).select(
        "id,status,checked_in_at",
      ).single();
      if (error) throw new Error("checkin_save_failed");
      return ok({
        checkin,
        participant: publicCheckInParticipant(participant),
      });
    }

    if (action === "get_registration_payment_status") {
      const participantId = uuid(payload.participant_id);
      if (!participantId) return fail(400, "registration_required");
      await rateLimit(admin, request, `status:${participantId}`, 30);
      const tokenHash = await sha256(text(payload.access_token, 500));
      const { data } = await admin.from("sd_registration_participants")
        .select(
          "id,registration_status,payment_status,participant_number,decision_state,decision_released_at,decision_message",
        )
        .eq("id", participantId).eq("public_access_token_hash", tokenHash)
        .maybeSingle();
      if (!data) return fail(403, "registration_access_required");
      return ok({
        registration: {
          id: data.id,
          registration_status: data.registration_status,
          payment_status: data.payment_status,
          participant_number: data.participant_number,
          decision_state: data.decision_released_at
            ? data.decision_state
            : null,
          decision_message: data.decision_released_at
            ? data.decision_message
            : null,
        },
      });
    }

    return fail(400, "unsupported_action");
  } catch (error) {
    const code = error instanceof Error
      ? error.message
      : "registration_public_failed";
    if (code === "public_rate_limit_exceeded") return fail(429, code);
    return fail(
      500,
      [
          "missing_supabase_secrets",
          "registration_identity_secret_required",
        ].includes(code)
        ? code
        : "registration_public_failed",
    );
  }
});
