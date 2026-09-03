// Supabase Edge Function: stripe-webhook
//
// Retired legacy endpoint. Home Plate player digital access is purchased with
// Apple In-App Purchase and synchronized by verify-apple-player-subscription.
// This endpoint continues to verify historical Stripe deliveries and returns a
// successful ignored response so Stripe does not retry, but it never mutates a
// subscription or sd_access_entitlements row.
//
// New organization SaaS events belong to stripe-platform-webhook. Payments for
// real-world baseball services belong to stripe-connected-payments-webhook.

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
  const parts = sigHeader.split(",").map((part) => part.trim());
  const values: Record<string, string[]> = {};
  for (const part of parts) {
    const separator = part.indexOf("=");
    if (separator <= 0) continue;
    const key = part.slice(0, separator).trim();
    const value = part.slice(separator + 1).trim();
    values[key] = values[key] ?? [];
    values[key].push(value);
  }
  return {
    timestamp: (values.t ?? [])[0] ?? "",
    signatures: values.v1 ?? [],
  };
}

async function hmacSha256Hex(secret: string, payload: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    "HMAC",
    key,
    new TextEncoder().encode(payload),
  );
  return Array.from(new Uint8Array(signature))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

function timingSafeEqualHex(left: string, right: string): boolean {
  if (left.length !== right.length) return false;
  let difference = 0;
  for (let index = 0; index < left.length; index += 1) {
    difference |= left.charCodeAt(index) ^ right.charCodeAt(index);
  }
  return difference === 0;
}

async function verifyStripeSignature(options: {
  secret: string;
  rawBody: string;
  signatureHeader: string;
  toleranceSeconds?: number;
}): Promise<{ ok: true } | { ok: false; reason: string }> {
  const parsed = parseStripeSignatureHeader(options.signatureHeader);
  const timestamp = Number(parsed.timestamp);
  if (!parsed.timestamp || !Number.isFinite(timestamp)) {
    return { ok: false, reason: "missing_or_invalid_timestamp" };
  }
  if (parsed.signatures.length === 0) {
    return { ok: false, reason: "missing_v1_signature" };
  }
  const toleranceSeconds = options.toleranceSeconds ?? 300;
  if (Math.abs(Math.floor(Date.now() / 1000) - timestamp) > toleranceSeconds) {
    return { ok: false, reason: "timestamp_out_of_tolerance" };
  }
  const expected = await hmacSha256Hex(
    options.secret,
    `${parsed.timestamp}.${options.rawBody}`,
  );
  return parsed.signatures.some((candidate) =>
      timingSafeEqualHex(expected, candidate)
    )
    ? { ok: true }
    : { ok: false, reason: "signature_mismatch" };
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response(null, { status: 204 });
  if (request.method !== "POST") {
    return json(405, { error: "method_not_allowed" });
  }

  const webhookSecret = getEnv("STRIPE_WEBHOOK_SECRET");
  if (!webhookSecret) {
    return json(500, { error: "missing_required_secret" });
  }

  const rawBody = await request.text();
  const verified = await verifyStripeSignature({
    secret: webhookSecret,
    rawBody,
    signatureHeader: request.headers.get("Stripe-Signature") ?? "",
  });
  if (!verified.ok) {
    return json(400, {
      error: "invalid_signature",
      reason: verified.reason,
    });
  }

  try {
    JSON.parse(rawBody);
  } catch {
    return json(400, { error: "invalid_json" });
  }

  return json(200, {
    ok: true,
    ignored: true,
    reason: "player_digital_access_uses_apple_iap",
  });
});
