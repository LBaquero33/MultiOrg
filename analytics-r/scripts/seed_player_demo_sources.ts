const PROJECT_URL = requiredEnv("SUPABASE_URL").replace(/\/$/, "");
const SERVICE_ROLE_KEY = requiredEnv("SUPABASE_SERVICE_ROLE_KEY");
const ORGANIZATION_ID = requiredEnv("HOME_PLATE_SEED_ORG_ID").toLowerCase();
const FIXTURE_PATH = requiredEnv("HOME_PLATE_SEED_FIXTURE");
const SEED_VERSION = "homeplate-r-analytics-demo.v1";
const IMPORT_SOURCE = "synthetic_r_analytics_demo";
const BUCKET = "player-development-imports";

type Row = Record<string, unknown>;

function requiredEnv(name: string): string {
  const value = Deno.env.get(name)?.trim();
  if (!value) throw new Error(`Missing required environment: ${name}`);
  return value;
}

function headers(extra: HeadersInit = {}): Headers {
  return new Headers({
    apikey: SERVICE_ROLE_KEY,
    Authorization: `Bearer ${SERVICE_ROLE_KEY}`,
    ...extra,
  });
}

async function responseJSON(response: Response): Promise<unknown> {
  const body = await response.json().catch(() => null);
  if (!response.ok) {
    const code = body && typeof body === "object"
      ? String((body as Row).code ?? (body as Row).error ?? response.status)
      : String(response.status);
    throw new Error(`Supabase request failed: ${code}`);
  }
  return body;
}

async function rest(path: string, init: RequestInit = {}): Promise<unknown> {
  return await responseJSON(
    await fetch(`${PROJECT_URL}/rest/v1/${path}`, {
      ...init,
      headers: headers({
        "content-type": "application/json",
        ...(init.headers ?? {}),
      }),
    }),
  );
}

async function sha256(value: Uint8Array | string): Promise<string> {
  const bytes = typeof value === "string"
    ? new TextEncoder().encode(value)
    : value;
  const buffer = bytes.buffer.slice(
    bytes.byteOffset,
    bytes.byteOffset + bytes.byteLength,
  ) as ArrayBuffer;
  const digest = await crypto.subtle.digest("SHA-256", buffer);
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

async function deterministicUUID(namespace: string): Promise<string> {
  const digest = await sha256(namespace);
  const bytes = digest.slice(0, 32).split("");
  bytes[12] = "5";
  bytes[16] = ["8", "9", "a", "b"][parseInt(bytes[16], 16) % 4];
  const value = bytes.join("");
  return `${value.slice(0, 8)}-${value.slice(8, 12)}-${value.slice(12, 16)}-${
    value.slice(16, 20)
  }-${value.slice(20)}`;
}

async function activePlayerIds(): Promise<string[]> {
  const params = new URLSearchParams({
    select: "user_id",
    org_id: `eq.${ORGANIZATION_ID}`,
    role: "eq.player",
    status: "eq.active",
    order: "user_id.asc",
    limit: "10000",
  });
  const rows = await rest(`sd_org_memberships?${params}`) as Row[];
  return rows.map((row) => String(row.user_id ?? "").toLowerCase()).filter(
    Boolean,
  );
}

async function ownerId(): Promise<string> {
  const params = new URLSearchParams({
    select: "user_id",
    org_id: `eq.${ORGANIZATION_ID}`,
    role: "eq.owner",
    status: "eq.active",
    order: "created_at.asc",
    limit: "1",
  });
  const rows = await rest(`sd_org_memberships?${params}`) as Row[];
  const id = String(rows[0]?.user_id ?? "").toLowerCase();
  if (!id) throw new Error("The organization has no active owner.");
  return id;
}

async function existingPlayers(): Promise<Set<string>> {
  const params = new URLSearchParams({
    select: "player_id",
    org_id: `eq.${ORGANIZATION_ID}`,
    import_source: `eq.${IMPORT_SOURCE}`,
    status: "in.(completed,completed_with_errors)",
    limit: "10000",
  });
  const rows = await rest(`sd_development_import_jobs?${params}`) as Row[];
  return new Set(
    rows.map((row) => String(row.player_id ?? "").toLowerCase()).filter(
      Boolean,
    ),
  );
}

function personalizedFixture(base: string, playerId: string): Uint8Array {
  const marker = playerId.replaceAll("-", "").slice(0, 12);
  const lines = base.replace(/\r\n/g, "\n").trimEnd().split("\n");
  lines[0] += ",HomePlateSyntheticSource";
  for (let index = 1; index < lines.length; index += 1) {
    lines[index] += `,${SEED_VERSION}-${marker}`;
  }
  return new TextEncoder().encode(`${lines.join("\n")}\n`);
}

async function upload(path: string, bytes: Uint8Array): Promise<void> {
  const body = bytes.buffer.slice(
    bytes.byteOffset,
    bytes.byteOffset + bytes.byteLength,
  ) as ArrayBuffer;
  const response = await fetch(
    `${PROJECT_URL}/storage/v1/object/${BUCKET}/${path}`,
    {
      method: "POST",
      headers: headers({
        "content-type": "text/csv",
        "x-upsert": "true",
      }),
      body,
    },
  );
  await responseJSON(response);
}

async function upsertJob(job: Row): Promise<void> {
  const params = new URLSearchParams({ on_conflict: "id" });
  await rest(`sd_development_import_jobs?${params}`, {
    method: "POST",
    headers: {
      Prefer: "resolution=merge-duplicates,return=minimal",
    },
    body: JSON.stringify(job),
  });
}

const fixture = await Deno.readTextFile(FIXTURE_PATH);
const rowCount = Math.max(
  0,
  fixture.replace(/\r\n/g, "\n").trimEnd().split("\n").length - 1,
);
if (!fixture.startsWith("PitchNo,")) {
  throw new Error("The demo fixture is not a recognized TrackMan CSV export.");
}

const [players, requestedBy, existing] = await Promise.all([
  activePlayerIds(),
  ownerId(),
  existingPlayers(),
]);
if (!players.length) {
  throw new Error("No active players were found for this organization.");
}

let created = 0;
let skipped = 0;
for (const playerId of players) {
  if (existing.has(playerId)) {
    skipped += 1;
    continue;
  }
  const jobId = await deterministicUUID(
    `${SEED_VERSION}:job:${ORGANIZATION_ID}:${playerId}`,
  );
  const objectId = await deterministicUUID(
    `${SEED_VERSION}:object:${ORGANIZATION_ID}:${playerId}`,
  );
  const idempotencyKey = await deterministicUUID(
    `${SEED_VERSION}:request:${ORGANIZATION_ID}:${playerId}`,
  );
  const path = `${ORGANIZATION_ID}/${jobId}/${objectId}.csv`;
  const bytes = personalizedFixture(fixture, playerId);
  const fileHash = await sha256(bytes);
  const now = new Date().toISOString();

  await upload(path, bytes);
  await upsertJob({
    id: jobId,
    org_id: ORGANIZATION_ID,
    player_id: playerId,
    requested_by: requestedBy,
    import_source: IMPORT_SOURCE,
    provider: "trackman",
    file_name: "[DEMO] Home Plate R Analytics TrackMan.csv",
    status: "completed",
    row_count: rowCount,
    accepted_rows: rowCount,
    rejected_rows: 0,
    started_at: now,
    completed_at: now,
    idempotency_key: idempotencyKey,
    import_version: SEED_VERSION,
    original_file_type: "csv",
    file_sha256: fileHash,
    file_size_bytes: bytes.byteLength,
    storage_bucket: BUCKET,
    storage_path: path,
    parser_version: "trackman-synthetic.v1",
    validation_summary: {
      synthetic: true,
      seed_version: SEED_VERSION,
      purpose: "Advanced Data product testing only",
      excluded_from_benchmarks: true,
    },
  });
  created += 1;
  if (created % 10 === 0) console.log(`seed_progress=${created}`);
}

console.log(
  `seed_complete=true players=${players.length} created=${created} skipped=${skipped} rows_per_player=${rowCount}`,
);
