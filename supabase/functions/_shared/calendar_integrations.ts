export const CALENDAR_INTEGRATION_VERSION = "google-calendar-v1";
export const GOOGLE_CALENDAR_SCOPE = "https://www.googleapis.com/auth/calendar.events";

export type CalendarSourceKind =
  | "sd_events"
  | "sd_team_events"
  | "sd_facility_bookings";

export type CalendarSource = {
  kind: CalendarSourceKind;
  id: string;
  organizationId: string;
  teamId: string | null;
  title: string;
  description: string | null;
  startAt: string;
  endAt: string;
  location: string | null;
  status: string;
  updatedAt: string | null;
  createdBy?: string | null;
  playerId?: string | null;
};

export type GoogleCalendarEvent = {
  id?: string;
  etag?: string;
  status?: string;
  summary?: string;
  description?: string;
  location?: string;
  updated?: string;
  start?: { dateTime?: string; date?: string; timeZone?: string };
  end?: { dateTime?: string; date?: string; timeZone?: string };
  extendedProperties?: { private?: Record<string, string> };
};

const encoder = new TextEncoder();
const decoder = new TextDecoder();

function bytesToBase64(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary);
}

function base64ToBytes(value: string): Uint8Array {
  const binary = atob(value);
  return Uint8Array.from(binary, (character) => character.charCodeAt(0));
}

export function base64url(bytes: Uint8Array): string {
  return bytesToBase64(bytes).replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/g, "");
}

export function randomOpaqueValue(byteCount = 32): string {
  const bytes = new Uint8Array(byteCount);
  crypto.getRandomValues(bytes);
  return base64url(bytes);
}

export async function sha256Hex(value: string): Promise<string> {
  const bytes = new Uint8Array(await crypto.subtle.digest("SHA-256", encoder.encode(value)));
  return [...bytes].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

export async function pkceChallenge(verifier: string): Promise<string> {
  return base64url(new Uint8Array(await crypto.subtle.digest("SHA-256", encoder.encode(verifier))));
}

async function encryptionKey(rawBase64: string): Promise<CryptoKey> {
  const bytes = base64ToBytes(rawBase64);
  if (bytes.byteLength !== 32) throw new Error("calendar_encryption_key_invalid");
  return await crypto.subtle.importKey("raw", bytes.slice().buffer as ArrayBuffer, "AES-GCM", false, ["encrypt", "decrypt"]);
}

export async function sealSecret(value: string, rawBase64Key: string): Promise<string> {
  const nonce = new Uint8Array(12);
  crypto.getRandomValues(nonce);
  const encrypted = new Uint8Array(await crypto.subtle.encrypt(
    { name: "AES-GCM", iv: nonce },
    await encryptionKey(rawBase64Key),
    encoder.encode(value),
  ));
  return `v1.${bytesToBase64(nonce)}.${bytesToBase64(encrypted)}`;
}

export async function openSecret(value: string, rawBase64Key: string): Promise<string> {
  const [version, nonceValue, encryptedValue] = value.split(".");
  if (version !== "v1" || !nonceValue || !encryptedValue) {
    throw new Error("calendar_ciphertext_invalid");
  }
  const plaintext = await crypto.subtle.decrypt(
    { name: "AES-GCM", iv: base64ToBytes(nonceValue).slice().buffer as ArrayBuffer },
    await encryptionKey(rawBase64Key),
    base64ToBytes(encryptedValue).slice().buffer as ArrayBuffer,
  );
  return decoder.decode(plaintext);
}

export function googleAuthorizationURL(args: {
  clientId: string;
  redirectUri: string;
  state: string;
  codeChallenge: string;
}): string {
  const url = new URL("https://accounts.google.com/o/oauth2/v2/auth");
  url.searchParams.set("client_id", args.clientId);
  url.searchParams.set("redirect_uri", args.redirectUri);
  url.searchParams.set("response_type", "code");
  url.searchParams.set("scope", GOOGLE_CALENDAR_SCOPE);
  url.searchParams.set("access_type", "offline");
  url.searchParams.set("include_granted_scopes", "true");
  url.searchParams.set("prompt", "consent");
  url.searchParams.set("state", args.state);
  url.searchParams.set("code_challenge", args.codeChallenge);
  url.searchParams.set("code_challenge_method", "S256");
  return url.toString();
}

export function sourceToGoogleEvent(source: CalendarSource): GoogleCalendarEvent {
  const booking = source.kind === "sd_facility_bookings";
  return {
    summary: source.title,
    description: [
      source.description,
      booking
        ? "This booking is managed in Home Plate. Approval status cannot be changed from Google Calendar."
        : "This event is managed in Home Plate.",
    ].filter(Boolean).join("\n\n"),
    location: source.location ?? undefined,
    start: { dateTime: source.startAt },
    end: { dateTime: source.endAt },
    extendedProperties: {
      private: {
        homePlateSourceKind: source.kind,
        homePlateSourceId: source.id,
        homePlateOrganizationId: source.organizationId,
        homePlateIntegrationVersion: CALENDAR_INTEGRATION_VERSION,
        homePlateReadOnly: booking ? "true" : "false",
      },
    },
  };
}

export function externalEventPatch(event: GoogleCalendarEvent): {
  title: string;
  description: string | null;
  startAt: string;
  endAt: string;
  location: string | null;
} | null {
  const startAt = event.start?.dateTime;
  const endAt = event.end?.dateTime;
  const title = event.summary?.trim();
  if (!title || !startAt || !endAt) return null;
  const start = new Date(startAt);
  const end = new Date(endAt);
  if (!Number.isFinite(start.valueOf()) || !Number.isFinite(end.valueOf()) || end <= start) return null;
  return {
    title: title.slice(0, 160),
    description: event.description?.trim() || null,
    startAt: start.toISOString(),
    endAt: end.toISOString(),
    location: event.location?.trim() || null,
  };
}

export function canApplyGoogleEdit(args: {
  role: string;
  capabilities: string[];
  sourceKind: CalendarSourceKind;
  eventType?: string | null;
}): boolean {
  if (args.sourceKind === "sd_facility_bookings") return false;
  const role = args.role.trim().toLowerCase();
  if (role === "owner" || role === "admin") return true;
  if (role !== "coach") return false;
  const required = (() => {
    switch ((args.eventType ?? "custom").toLowerCase()) {
      case "practice": return "manage_practice_event";
      case "game": return "manage_game_event";
      case "tournament": return "manage_tournament_event";
      case "meeting": return "manage_meeting_event";
      case "travel": return "manage_travel_event";
      default: return "manage_custom_event";
    }
  })();
  return args.capabilities.includes(required) || args.capabilities.includes("manage_team_schedule");
}

export function safeCalendarError(error: unknown): string {
  const message = error instanceof Error ? error.message.toLowerCase() : "";
  if (message.includes("invalid_grant") || message.includes("unauthorized")) return "google_reauthorization_required";
  if (message.includes("rate") || message.includes("429")) return "google_rate_limited";
  if (message.includes("encryption") || message.includes("ciphertext")) return "calendar_crypto_failed";
  if (message.includes("permission") || message.includes("forbidden") || message.includes("403")) return "calendar_permission_denied";
  if (message.includes("fetch") || message.includes("network") || message.includes("timeout")) return "calendar_network_failed";
  return "calendar_sync_failed";
}
