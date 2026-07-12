// Stripe REST helper. Requests use Stripe API version 2025-06-30.basil.
const STRIPE_API_VERSION = "2025-06-30.basil";

export function formBody(values: Record<string, string | number | boolean | null | undefined>) {
  const body = new URLSearchParams();
  for (const [key, value] of Object.entries(values)) {
    if (value !== null && value !== undefined) body.set(key, String(value));
  }
  return body;
}

export async function stripeRequest<T>(
  secretKey: string,
  path: string,
  options: { method?: "GET" | "POST"; form?: URLSearchParams; idempotencyKey?: string } = {},
): Promise<T> {
  const headers: Record<string, string> = {
    Authorization: `Basic ${btoa(`${secretKey}:`)}`,
    "Stripe-Version": STRIPE_API_VERSION,
  };
  if (options.idempotencyKey) headers["Idempotency-Key"] = options.idempotencyKey;
  if (options.form) headers["Content-Type"] = "application/x-www-form-urlencoded";
  const response = await fetch(`https://api.stripe.com/v1${path}`, {
    method: options.method ?? (options.form ? "POST" : "GET"),
    headers,
    body: options.form?.toString(),
  });
  const payload = await response.json();
  if (!response.ok) {
    const message = String(payload?.error?.message ?? "stripe_request_failed");
    throw new Error(`stripe_${response.status}:${message}`);
  }
  return payload as T;
}

export function stripeUnixToIso(value: unknown): string | null {
  const seconds = Number(value);
  return Number.isFinite(seconds) && seconds > 0 ? new Date(seconds * 1000).toISOString() : null;
}

export async function verifyStripeSignature(rawBody: string, signatureHeader: string, secret: string): Promise<boolean> {
  const values: Record<string, string[]> = {};
  for (const part of signatureHeader.split(",")) {
    const index = part.indexOf("=");
    if (index > 0) (values[part.slice(0, index).trim()] ??= []).push(part.slice(index + 1).trim());
  }
  const timestamp = (values.t ?? [])[0];
  const signatures = values.v1 ?? [];
  if (!timestamp || !signatures.length || Math.abs(Math.floor(Date.now() / 1000) - Number(timestamp)) > 300) return false;
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const bytes = new Uint8Array(await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(`${timestamp}.${rawBody}`)));
  const expected = Array.from(bytes).map((byte) => byte.toString(16).padStart(2, "0")).join("");
  return signatures.some((candidate) => candidate.length === expected.length && candidate.split("").reduce((diff, char, index) => diff | (char.charCodeAt(0) ^ expected.charCodeAt(index)), 0) === 0);
}
