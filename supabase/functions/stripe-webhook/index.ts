// Supabase Edge Function: stripe-webhook
//
// Purpose:
// - Receive Stripe webhook events
// - Verify signature (Stripe-Signature + STRIPE_WEBHOOK_SECRET)
// - Upsert `public.sd_access_entitlements` so the apps can enforce "active subscription only"
//
// Required Supabase secrets (Project → Edge Functions → Secrets):
// - SUPABASE_URL
// - SUPABASE_SERVICE_ROLE_KEY
// - STRIPE_WEBHOOK_SECRET   (from Stripe webhook endpoint: whsec_...)
//
// Optional:
// - STRIPE_SUB_ACTIVE_STATUSES (comma list; default: "active,trialing")
//
// Notes:
// - Deploy with JWT verification OFF (Stripe won't send an Authorization header).
// - For best attribution, pass the Supabase user_id as Stripe Checkout Session `client_reference_id`.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

type Json = Record<string, unknown>;

function json(status: number, body: Json) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });
}

function getEnv(name: string) {
  return (Deno.env.get(name) ?? "").trim();
}

function parseStripeSignatureHeader(sigHeader: string) {
  // Stripe-Signature: t=timestamp,v1=hex,v0=...
  const parts = sigHeader.split(",").map((s) => s.trim());
  const out: Record<string, string[]> = {};
  for (const p of parts) {
    const idx = p.indexOf("=");
    if (idx <= 0) continue;
    const k = p.slice(0, idx).trim();
    const v = p.slice(idx + 1).trim();
    out[k] = out[k] ?? [];
    out[k].push(v);
  }
  const t = (out["t"] ?? [])[0] ?? "";
  const v1 = out["v1"] ?? [];
  return { t, v1 };
}

async function hmacSha256Hex(secret: string, payload: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const sig = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(payload));
  const bytes = new Uint8Array(sig);
  return Array.from(bytes).map((b) => b.toString(16).padStart(2, "0")).join("");
}

function timingSafeEqualHex(a: string, b: string): boolean {
  // Constant-time compare for same-length hex strings.
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

async function verifyStripeSignature(opts: {
  secret: string;
  rawBody: string;
  signatureHeader: string;
  toleranceSeconds?: number;
}): Promise<{ ok: true } | { ok: false; reason: string }> {
  const toleranceSeconds = opts.toleranceSeconds ?? 300;
  const { t, v1 } = parseStripeSignatureHeader(opts.signatureHeader);
  const ts = Number(t);
  if (!t || !Number.isFinite(ts)) return { ok: false, reason: "missing_or_invalid_timestamp" };
  if (!v1.length) return { ok: false, reason: "missing_v1_signature" };

  const now = Math.floor(Date.now() / 1000);
  if (Math.abs(now - ts) > toleranceSeconds) return { ok: false, reason: "timestamp_out_of_tolerance" };

  const payload = `${t}.${opts.rawBody}`;
  const expected = await hmacSha256Hex(opts.secret, payload);
  for (const candidate of v1) {
    if (timingSafeEqualHex(expected, candidate)) return { ok: true };
  }
  return { ok: false, reason: "signature_mismatch" };
}

function activeStatusesFromEnv(): Set<string> {
  const raw = getEnv("STRIPE_SUB_ACTIVE_STATUSES") || "active,trialing";
  return new Set(raw.split(",").map((s) => s.trim().toLowerCase()).filter(Boolean));
}

function normalizeUuid(x: unknown): string | null {
  const s = String(x ?? "").trim();
  // Very light check; the DB will enforce real uuid type.
  if (!s) return null;
  return s;
}

function idFromStripeRef(x: unknown): string | null {
  // Stripe sometimes returns IDs as strings, or as expanded objects with an `id` field.
  if (!x) return null;
  if (typeof x === "string") return x;
  if (typeof x === "object" && (x as any).id) return String((x as any).id);
  return null;
}

function periodEndToIso(seconds: unknown): string | null {
  const n = Number(seconds);
  if (!Number.isFinite(n) || n <= 0) return null;
  return new Date(n * 1000).toISOString();
}

async function upsertEntitlementByUserId(args: {
  admin: ReturnType<typeof createClient>;
  userId: string;
  stripeCustomerId?: string | null;
  stripeSubscriptionId?: string | null;
  status?: string | null;
  currentPeriodEndIso?: string | null;
}) {
  const isActive = args.status ? activeStatusesFromEnv().has(args.status.toLowerCase()) : null;
  const payload: Record<string, unknown> = {
    user_id: args.userId,
    source: "stripe",
  };
  if (isActive !== null) payload.is_active = isActive;
  if (args.stripeCustomerId) payload.stripe_customer_id = args.stripeCustomerId;
  if (args.stripeSubscriptionId) payload.stripe_subscription_id = args.stripeSubscriptionId;
  if (args.currentPeriodEndIso) payload.current_period_end = args.currentPeriodEndIso;

  const { error } = await args.admin
    .from("sd_access_entitlements")
    .upsert(payload, { onConflict: "user_id" });
  if (error) throw new Error(`entitlement_upsert_failed: ${error.message}`);
}

async function updateEntitlementByStripeIds(args: {
  admin: ReturnType<typeof createClient>;
  stripeCustomerId?: string | null;
  stripeSubscriptionId?: string | null;
  status?: string | null;
  currentPeriodEndIso?: string | null;
}) {
  // If we don't know the user id, locate the entitlement row by stripe_subscription_id or stripe_customer_id.
  const filters: { col: string; val: string }[] = [];
  if (args.stripeSubscriptionId) filters.push({ col: "stripe_subscription_id", val: args.stripeSubscriptionId });
  if (args.stripeCustomerId) filters.push({ col: "stripe_customer_id", val: args.stripeCustomerId });
  if (!filters.length) return;

  // Try subscription first (most specific).
  let row: { user_id: string } | null = null;
  for (const f of filters) {
    const { data, error } = await args.admin
      .from("sd_access_entitlements")
      .select("user_id")
      .eq(f.col, f.val)
      .maybeSingle();
    if (error) throw new Error(`entitlement_lookup_failed: ${error.message}`);
    if (data?.user_id) {
      row = data as any;
      break;
    }
  }
  if (!row?.user_id) return;

  await upsertEntitlementByUserId({
    admin: args.admin,
    userId: row.user_id,
    stripeCustomerId: args.stripeCustomerId ?? null,
    stripeSubscriptionId: args.stripeSubscriptionId ?? null,
    status: args.status ?? null,
    currentPeriodEndIso: args.currentPeriodEndIso ?? null,
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { status: 204 });
  if (req.method !== "POST") return json(405, { error: "method_not_allowed" });

  const supabaseUrl = getEnv("SUPABASE_URL");
  const serviceKey = getEnv("SUPABASE_SERVICE_ROLE_KEY");
  const webhookSecret = getEnv("STRIPE_WEBHOOK_SECRET");
  if (!supabaseUrl || !serviceKey || !webhookSecret) {
    return json(500, { error: "missing_required_secrets" });
  }

  const sigHeader = req.headers.get("Stripe-Signature") ?? "";
  const rawBody = await req.text();

  const verified = await verifyStripeSignature({
    secret: webhookSecret,
    rawBody,
    signatureHeader: sigHeader,
    toleranceSeconds: 300,
  });
  if (!verified.ok) return json(400, { error: "invalid_signature", reason: verified.reason });

  let event: any;
  try {
    event = JSON.parse(rawBody);
  } catch {
    return json(400, { error: "invalid_json" });
  }

  const admin = createClient(supabaseUrl, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const type = String(event?.type ?? "");
  const obj = event?.data?.object ?? {};

  try {
    switch (type) {
      case "checkout.session.completed": {
        const userId = normalizeUuid(obj?.client_reference_id);
        const stripeCustomerId = idFromStripeRef(obj?.customer);
        const stripeSubscriptionId = idFromStripeRef(obj?.subscription);
        // Stripe doesn't include a subscription status on the session. For UX, we treat a paid subscription-mode
        // checkout as "active" immediately, then rely on `customer.subscription.*` events to keep it correct.
        const mode = String(obj?.mode ?? "").toLowerCase();
        const paymentStatus = String(obj?.payment_status ?? "").toLowerCase();
        const sessionStatus = String(obj?.status ?? "").toLowerCase();
        const optimisticStatus =
          mode === "subscription" &&
            (paymentStatus === "paid" ||
              paymentStatus === "no_payment_required" ||
              sessionStatus === "complete" ||
              !!stripeSubscriptionId)
            ? "active"
            : null;

        if (userId) {
          await upsertEntitlementByUserId({
            admin,
            userId,
            stripeCustomerId,
            stripeSubscriptionId,
            status: optimisticStatus,
            currentPeriodEndIso: null,
          });
        } else {
          // If you see this, make sure your payment link is opened with ?client_reference_id=<supabase_user_id>
          console.log("checkout.session.completed missing client_reference_id; cannot attribute to user_id");
        }
        break;
      }

      case "customer.subscription.created":
      case "customer.subscription.updated":
      case "customer.subscription.deleted": {
        const stripeSubscriptionId = obj?.id ? String(obj.id) : null;
        const stripeCustomerId = idFromStripeRef(obj?.customer);
        const status = obj?.status ? String(obj.status) : null;
        const currentPeriodEndIso = periodEndToIso(obj?.current_period_end);

        // Best-effort: try user id from metadata if present, otherwise resolve by stripe ids.
        const userId =
          normalizeUuid(obj?.metadata?.user_id) ??
          normalizeUuid(obj?.metadata?.supabase_user_id) ??
          null;

        if (userId) {
          await upsertEntitlementByUserId({
            admin,
            userId,
            stripeCustomerId,
            stripeSubscriptionId,
            status,
            currentPeriodEndIso,
          });
        } else {
          await updateEntitlementByStripeIds({
            admin,
            stripeCustomerId,
            stripeSubscriptionId,
            status,
            currentPeriodEndIso,
          });
        }
        break;
      }

      default:
        // Ignore other event types for MVP.
        break;
    }

    return json(200, { ok: true });
  } catch (err) {
    console.log("stripe-webhook error", String(err?.message ?? err));
    return json(500, { error: "handler_failed" });
  }
});
