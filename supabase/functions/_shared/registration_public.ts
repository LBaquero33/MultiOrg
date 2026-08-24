const encoder = new TextEncoder();

export type CheckInTokenPayload = {
  session_id: string;
  purpose: "registration_checkin";
  exp: number;
};

function base64Url(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(
    /=+$/g,
    "",
  );
}

function decodeBase64Url(value: string): Uint8Array {
  const padded = value.replace(/-/g, "+").replace(/_/g, "/") +
    "=".repeat((4 - value.length % 4) % 4);
  const binary = atob(padded);
  return Uint8Array.from(binary, (character) => character.charCodeAt(0));
}

async function hmac(secret: string, value: string): Promise<Uint8Array> {
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  return new Uint8Array(
    await crypto.subtle.sign("HMAC", key, encoder.encode(value)),
  );
}

export async function sha256(value: string): Promise<string> {
  return base64Url(
    new Uint8Array(
      await crypto.subtle.digest("SHA-256", encoder.encode(value)),
    ),
  );
}

export async function identityKey(
  secret: string,
  organizationId: string,
  fields: {
    displayName: string;
    birthYear?: number | null;
    email?: string | null;
    phone?: string | null;
  },
): Promise<string> {
  const normalized = [
    organizationId.toLowerCase(),
    fields.displayName.toLowerCase().replace(/\s+/g, " ").trim(),
    String(fields.birthYear ?? ""),
    String(fields.email ?? "").toLowerCase().trim(),
    String(fields.phone ?? "").replace(/\D/g, ""),
  ].join("|");
  return base64Url(await hmac(secret, normalized));
}

export async function signCheckInToken(
  secret: string,
  sessionId: string,
  expiresAtSeconds: number,
): Promise<string> {
  const encoded = base64Url(encoder.encode(JSON.stringify(
    {
      session_id: sessionId,
      purpose: "registration_checkin",
      exp: expiresAtSeconds,
    } satisfies CheckInTokenPayload,
  )));
  return `${encoded}.${base64Url(await hmac(secret, encoded))}`;
}

export async function verifyCheckInToken(
  secret: string,
  token: string,
  nowSeconds = Math.floor(Date.now() / 1000),
): Promise<CheckInTokenPayload | null> {
  const [encoded, signature, extra] = token.split(".");
  if (!encoded || !signature || extra) return null;
  const expected = await hmac(secret, encoded);
  const supplied = decodeBase64Url(signature);
  if (expected.length !== supplied.length) return null;
  let mismatch = 0;
  for (let index = 0; index < expected.length; index += 1) {
    mismatch |= expected[index] ^ supplied[index];
  }
  if (mismatch !== 0) return null;
  try {
    const payload = JSON.parse(
      new TextDecoder().decode(decodeBase64Url(encoded)),
    ) as CheckInTokenPayload;
    if (
      payload.purpose !== "registration_checkin" ||
      !payload.session_id ||
      !Number.isFinite(payload.exp) ||
      payload.exp < nowSeconds
    ) return null;
    return payload;
  } catch {
    return null;
  }
}

export function normalizePhoneLastFour(value: unknown): string | null {
  const digits = String(value ?? "").replace(/\D/g, "");
  return digits.length >= 4 ? digits.slice(-4) : null;
}

export function publicCheckInParticipant(row: Record<string, unknown>) {
  return {
    id: String(row.id ?? ""),
    display_name: String(row.display_name ?? "Registrant"),
    participant_number: row.participant_number == null
      ? null
      : Number(row.participant_number),
    age_group: row.age_group == null ? null : String(row.age_group),
  };
}
