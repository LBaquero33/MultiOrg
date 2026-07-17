import { playerVisibleEvidencePack } from "./player_development_copilot.ts";
import { PLAYER_DEVELOPMENT_COPILOT_FEATURE_KEY } from "./platform_feature_flags.ts";

export type DevelopmentMembership = { role: string; status: string };

export type DevelopmentRecordAudience = "staff" | "player";

export type DevelopmentQualityStatus =
  | "sufficient"
  | "limited"
  | "stale"
  | "conflicting"
  | "unavailable";

export type PreferredDirection =
  | "higher_is_better"
  | "lower_is_better"
  | "target_range"
  | "informational"
  | "context_dependent";

export type MetricDefinition = {
  id: string;
  canonical_key: string;
  display_name: string;
  category: string;
  canonical_unit: string | null;
  preferred_direction: PreferredDirection;
  target_min: number | null;
  target_max: number | null;
  minimum_sample_size: number;
};

export type TestingEntry = {
  id: string;
  org_id: string;
  player_id: string;
  entry_date: string;
  height_in: number | null;
  weight_lb: number | null;
  squat_1rm: number | null;
  bench_1rm: number | null;
  deadlift_1rm: number | null;
  max_exit_velo: number | null;
  avg_exit_velo: number | null;
  hip_er_diff: number | null;
  hip_ir_diff: number | null;
  shoulder_ir_diff: number | null;
  shoulder_er_diff: number | null;
  notes?: string | null;
};

export type MetricObservation = {
  id: string;
  org_id: string;
  player_id: string;
  canonical_key: string;
  normalized_value: number | null;
  observed_value: string | null;
  unit: string | null;
  observed_at: string;
  source_system: string;
  source_entity_type: string;
  source_record_id: string;
  import_job_id?: string | null;
  original_unit?: string | null;
  canonical_unit?: string | null;
  verification_status?: string | null;
  parser_version?: string | null;
  mapping_version?: string | null;
  source_row_number?: number | null;
  quality_status: DevelopmentQualityStatus;
  sample_size: number | null;
  context_metadata?: Record<string, unknown>;
};

export type DailyLog = {
  id: string;
  org_id: string;
  player_id: string;
  log_date: string;
  feel: number | null;
  hit_daily_goals: boolean | null;
  stuck_to_process: boolean | null;
  notes?: string | null;
};

export type ProgramAssignment = {
  id: string;
  org_id: string;
  player_id: string;
  template_id: string;
  start_date: string;
  ended_at: string | null;
  notes?: string | null;
};

export type BPSession = {
  id: string;
  org_id: string;
  player_id: string;
  session_date: string;
  source: string;
  reps_type: string;
  events: Array<{
    id: string;
    exit_velo: number | null;
    distance: number | null;
    launch_angle: number | null;
    raw?: Record<string, unknown>;
  }>;
};

export type DevelopmentEvidenceSource = {
  player: { id: string; full_name: string | null };
  testing_entries: TestingEntry[];
  metric_observations: MetricObservation[];
  daily_logs: DailyLog[];
  program_assignments: ProgramAssignment[];
  bp_sessions: BPSession[];
  reports_awaiting_review: number;
  source_warnings?: string[];
};

export type DevelopmentEvidence = {
  evidence_key: string;
  section_key: string;
  source_entity_type: string;
  source_record_id: string;
  canonical_metric_key: string | null;
  raw_observed_value: string | null;
  normalized_numeric_value: number | null;
  unit: string | null;
  observation_date: string | null;
  comparison_value: number | null;
  comparison_period: string | null;
  direction: string | null;
  sample_size: number | null;
  freshness: string;
  quality: DevelopmentQualityStatus;
  deterministic_rule_id: string | null;
  display_label: string;
  explanation: string;
  source_metadata: Record<string, unknown>;
  evidence_snapshot: Record<string, unknown>;
};

export type DevelopmentTrend = {
  canonical_metric_key: string;
  display_name: string;
  unit: string | null;
  latest_value: number;
  prior_value: number | null;
  absolute_change: number | null;
  percentage_change: number | null;
  rolling_average: number | null;
  recent_window_average: number | null;
  prior_window_average: number | null;
  best_value: number | null;
  worst_value: number | null;
  sample_count: number;
  observation_frequency_days: number | null;
  freshness: string;
  quality: DevelopmentQualityStatus;
  interpretation:
    | "improvement"
    | "regression"
    | "stable"
    | "informational"
    | "insufficient";
  rule_id: string;
  evidence_keys: string[];
};

export type DevelopmentEvidencePack = {
  schema_version: "player_development_evidence_pack.v1";
  organization_id: string;
  player_id: string;
  player_name: string;
  report_type: string;
  window_start: string;
  window_end: string;
  evidence_cutoff: string;
  quality_status: DevelopmentQualityStatus;
  data_freshness: string;
  coverage: {
    testing_entries: number;
    metric_observations: number;
    daily_logs: number;
    program_assignments: number;
    bp_sessions: number;
  };
  trends: DevelopmentTrend[];
  evidence: DevelopmentEvidence[];
  missing_data_warnings: string[];
  stale_data_warnings: string[];
  unit_conflicts: string[];
  low_sample_warnings: string[];
};

export type DevelopmentReportContent = {
  overview: string;
  positive_trends: Array<
    { title: string; explanation: string; evidence_keys: string[] }
  >;
  development_priorities: Array<
    { title: string; explanation: string; evidence_keys: string[] }
  >;
  consistency_and_attendance: string;
  data_gaps: string[];
  coach_review_questions: string[];
  evidence_summary: Array<
    { label: string; explanation: string; evidence_key: string }
  >;
};

export type DevelopmentReportRecord = {
  id: string;
  org_id: string;
  player_id: string | null;
  team_id: string | null;
  report_type: string;
  requested_by: string;
  intended_audience: string;
  audience: "staff" | "player" | "parent";
  reporting_window_start: string;
  reporting_window_end: string;
  status: string;
  quality_status: DevelopmentQualityStatus;
  structured_content: DevelopmentReportContent;
  rendered_text: string;
  generation_mode: string;
  provider: string;
  model_identifier: string | null;
  generator_version: string;
  prompt_version: string;
  input_cutoff: string;
  generated_at: string | null;
  reviewed_at: string | null;
  reviewed_by: string | null;
  approved_at: string | null;
  rejected_at: string | null;
  archived_at: string | null;
  coach_edits: Record<string, unknown>;
  review_notes: string | null;
  confidence: number | null;
  data_freshness: string;
  missing_data_warnings: string[];
  evidence_fingerprint: string;
  created_at: string;
  updated_at: string;
};

export type DevelopmentReportDetail = {
  report: DevelopmentReportRecord;
  evidence: DevelopmentEvidence[];
  review_history: Array<Record<string, unknown>>;
};

export type DevelopmentAlert = {
  id: string;
  org_id: string;
  player_id: string;
  report_id: string | null;
  audience: DevelopmentRecordAudience;
  alert_type: string;
  severity: "info" | "attention" | "high";
  status: "active" | "acknowledged" | "dismissed" | "resolved" | "archived";
  first_detected_at: string;
  last_detected_at: string;
  evidence_window_start: string;
  evidence_window_end: string;
  rule_version: string;
  explanation: string;
  recommended_human_action: string;
  data_freshness: string;
  evidence_quality: DevelopmentQualityStatus;
  deduplication_key: string;
  player_name?: string | null;
};

export type DevelopmentAlertEvidence = {
  id?: string;
  alert_id?: string;
  org_id: string;
  player_id: string;
  evidence_key: string;
  source_entity_type: string;
  source_record_id: string;
  canonical_metric_key: string | null;
  observation_date: string | null;
  display_label: string;
  explanation: string;
  evidence_snapshot: Record<string, unknown>;
};

export type DevelopmentAlertDetail = {
  alert: DevelopmentAlert;
  evidence: DevelopmentAlertEvidence[];
  review_history: Array<Record<string, unknown>>;
};

export type AlertCandidate =
  & Omit<
    DevelopmentAlert,
    "id" | "first_detected_at" | "last_detected_at" | "status"
  >
  & {
    status: "active";
    evidence: DevelopmentEvidence[];
  };

export interface PlayerDevelopmentAIStore {
  authenticate(request: Request): Promise<string | null>;
  platformFeatureEnabled(key: string): Promise<boolean>;
  organizationStatus(orgId: string): Promise<string | null>;
  membership(
    orgId: string,
    actorId: string,
  ): Promise<DevelopmentMembership | null>;
  authorizedPlayerIds(orgId: string, actorId: string): Promise<Set<string>>;
  metricDefinitions(): Promise<MetricDefinition[]>;
  evidenceSource(
    orgId: string,
    playerId: string,
    start: string,
    end: string,
    cutoff: string,
  ): Promise<DevelopmentEvidenceSource>;
  createReport(input: {
    actorId: string;
    orgId: string;
    playerId: string;
    reportType: string;
    intendedAudience: string;
    audience: DevelopmentRecordAudience;
    windowStart: string;
    windowEnd: string;
    cutoff: string;
    idempotencyKey: string;
    evidenceFingerprint: string;
    qualityStatus: DevelopmentQualityStatus;
    content: DevelopmentReportContent;
    renderedText: string;
    confidence: number;
    dataFreshness: string;
    warnings: string[];
    evidence: DevelopmentEvidence[];
    promptVersion: string;
    generatorVersion: string;
  }): Promise<{ report: DevelopmentReportRecord; reused: boolean }>;
  listReports(
    orgId: string,
    playerIds: string[],
    playerId?: string,
    audience?: DevelopmentRecordAudience,
  ): Promise<DevelopmentReportRecord[]>;
  reportDetail(
    orgId: string,
    reportId: string,
    playerIds: string[],
    audience: DevelopmentRecordAudience,
  ): Promise<DevelopmentReportDetail | null>;
  reviewReport(
    actorId: string,
    orgId: string,
    reportId: string,
    action: string,
    notes: string | null,
    edits: Record<string, unknown>,
    audience: DevelopmentRecordAudience,
  ): Promise<DevelopmentReportRecord>;
  listAlerts(
    orgId: string,
    playerIds: string[],
    playerId?: string,
    audience?: DevelopmentRecordAudience,
  ): Promise<DevelopmentAlert[]>;
  alertDetail(
    orgId: string,
    alertId: string,
    playerIds: string[],
    audience: DevelopmentRecordAudience,
  ): Promise<DevelopmentAlertDetail | null>;
  persistAlerts(
    actorId: string,
    orgId: string,
    alerts: AlertCandidate[],
    audience: DevelopmentRecordAudience,
  ): Promise<DevelopmentAlert[]>;
  reviewAlert(
    actorId: string,
    orgId: string,
    alertId: string,
    action: string,
    notes: string | null,
    audience: DevelopmentRecordAudience,
  ): Promise<DevelopmentAlert>;
}

const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const datePattern = /^\d{4}-\d{2}-\d{2}$/;
export const DEVELOPMENT_MAX_REQUEST_BYTES = 65_536;
export const DEVELOPMENT_MAX_REPORTING_WINDOW_DAYS = 730;
export const DEVELOPMENT_GENERATOR_VERSION = "deterministic-template.v1";
export const DEVELOPMENT_PROMPT_VERSION = "none.deterministic.v1";
export const PLAYER_DEVELOPMENT_GENERATOR_VERSION =
  "player-deterministic-template.v1";
export const PLAYER_DEVELOPMENT_PROMPT_VERSION =
  "player-development-self-summary.v1";
const supportedReportTypes = new Set([
  "player_development_summary",
  "coach_copilot",
  "parent_update_draft",
  "roster_attention_report",
  "development_alert_review",
]);
const supportedActions = new Set([
  "build_evidence_pack",
  "generate_report",
  "run_alert_detection",
  "list_player_reports",
  "list_organization_reports",
  "get_report",
  "review_report",
  "list_player_alerts",
  "list_organization_alerts",
  "roster_attention",
  "get_alert",
  "review_alert",
  "generate_player_report",
  "get_player_report",
  "archive_player_report",
  "get_player_alert",
  "dismiss_player_alert",
]);

function json(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });
}

function safeMessage(code: string): string {
  const messages: Record<string, string> = {
    invalid_auth: "Your session could not be verified. Sign in and try again.",
    feature_disabled:
      "Player Development AI and Copilot are currently disabled by Home Plate.",
    invalid_json: "The Player Development AI request could not be read.",
    request_too_large: "The Player Development AI request is too large.",
    invalid_request: "The Player Development AI request is invalid.",
    organization_unavailable: "The selected organization is unavailable.",
    staff_access_required: "Active organization staff access is required.",
    player_access_denied:
      "You do not have access to this player in the selected organization.",
    report_not_found: "The development report is unavailable.",
    alert_not_found: "The development alert is unavailable.",
    unsupported_action: "This Player Development AI action is not supported.",
    development_report_idempotency_conflict:
      "This retry no longer matches the original report request.",
    invalid_report_transition:
      "That report review action is not valid for its current status.",
    invalid_alert_transition:
      "That alert action is not valid for its current status.",
  };
  return messages[code] ??
    "Player Development AI could not complete the request.";
}

function exactISODateMilliseconds(value: string): number | null {
  if (!datePattern.test(value)) return null;
  const milliseconds = Date.parse(`${value}T00:00:00.000Z`);
  if (!Number.isFinite(milliseconds)) return null;
  return new Date(milliseconds).toISOString().slice(0, 10) === value
    ? milliseconds
    : null;
}

async function readBoundedJSONObject(
  request: Request,
): Promise<Record<string, unknown>> {
  const declared = Number(request.headers.get("content-length") ?? "0");
  if (Number.isFinite(declared) && declared > DEVELOPMENT_MAX_REQUEST_BYTES) {
    throw new Error("request_too_large");
  }
  if (!request.body) throw new Error("invalid_json");
  const reader = request.body.getReader();
  const chunks: Uint8Array[] = [];
  let total = 0;
  while (true) {
    const { value, done } = await reader.read();
    if (done) break;
    if (!value) continue;
    total += value.byteLength;
    if (total > DEVELOPMENT_MAX_REQUEST_BYTES) {
      await reader.cancel();
      throw new Error("request_too_large");
    }
    chunks.push(value);
  }
  const bytes = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }
  const parsed = JSON.parse(new TextDecoder().decode(bytes));
  if (!isObject(parsed)) throw new Error("invalid_json");
  return parsed;
}

function average(values: number[]): number | null {
  if (values.length === 0) return null;
  return values.reduce((sum, value) => sum + value, 0) / values.length;
}

export async function evidencePackFingerprint(
  pack: DevelopmentEvidencePack,
): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(JSON.stringify(pack)),
  );
  return Array.from(new Uint8Array(digest)).map((byte) =>
    byte.toString(16).padStart(2, "0")
  ).join("");
}

export function safePercentageChange(
  prior: number,
  latest: number,
): number | null {
  if (
    !Number.isFinite(prior) || !Number.isFinite(latest) ||
    Math.abs(prior) < 0.000001
  ) return null;
  return ((latest - prior) / Math.abs(prior)) * 100;
}

function dayDistance(a: string, b: string): number {
  return Math.max(0, Math.round((Date.parse(b) - Date.parse(a)) / 86_400_000));
}

function freshness(lastDate: string | null, cutoff: string): string {
  if (!lastDate) return "unavailable";
  const days = dayDistance(lastDate.slice(0, 10), cutoff.slice(0, 10));
  if (days <= 30) return "current";
  if (days <= 90) return "aging";
  return "stale";
}

function interpretTrend(
  definition: MetricDefinition,
  change: number | null,
  recent: number | null,
  prior: number | null,
): DevelopmentTrend["interpretation"] {
  if (change === null) return "insufficient";
  if (
    definition.preferred_direction === "informational" ||
    definition.preferred_direction === "context_dependent"
  ) return "informational";
  if (definition.preferred_direction === "target_range") {
    if (
      recent === null || prior === null || definition.target_min === null ||
      definition.target_max === null
    ) return "insufficient";
    const distance = (value: number) =>
      value < definition.target_min!
        ? definition.target_min! - value
        : value > definition.target_max!
        ? value - definition.target_max!
        : 0;
    const priorDistance = distance(prior);
    const recentDistance = distance(recent);
    const tolerance = Math.max(Math.abs(recent) * 0.02, 0.01);
    if (Math.abs(recentDistance - priorDistance) <= tolerance) return "stable";
    return recentDistance < priorDistance ? "improvement" : "regression";
  }
  const tolerance = Math.max(Math.abs(recent ?? 0) * 0.02, 0.01);
  if (Math.abs(change) <= tolerance) return "stable";
  switch (definition.preferred_direction) {
    case "higher_is_better":
      return change > 0 ? "improvement" : "regression";
    case "lower_is_better":
      return change < 0 ? "improvement" : "regression";
    default:
      return "informational";
  }
}

type Point = {
  value: number;
  date: string;
  evidenceKey: string;
  unit: string | null;
};

export function calculateTrend(
  definition: MetricDefinition,
  input: Point[],
  cutoff: string,
): DevelopmentTrend | null {
  const points = input.filter((point) => Number.isFinite(point.value)).sort((
    a,
    b,
  ) => a.date.localeCompare(b.date));
  if (points.length === 0) return null;
  const values = points.map((point) => point.value);
  const latest = points.at(-1)!;
  const prior = points.length > 1 ? points.at(-2)! : null;
  const rollingValues = values.slice(-Math.min(5, values.length));
  const split = Math.max(1, Math.floor(values.length / 2));
  const priorWindow = values.slice(0, split);
  const recentWindow = values.slice(split);
  const recentAverage = average(
    recentWindow.length > 0 ? recentWindow : values,
  );
  const priorAverage = values.length > 1 ? average(priorWindow) : null;
  const change = prior ? latest.value - prior.value : null;
  const units = new Set(
    points.map((point) => point.unit).filter((unit): unit is string =>
      Boolean(unit)
    ),
  );
  const hasUnitConflict = units.size > 1;
  const frequency = points.length > 1
    ? average(
      points.slice(1).map((point, index) =>
        dayDistance(points[index].date.slice(0, 10), point.date.slice(0, 10))
      ),
    )
    : null;
  const quality: DevelopmentQualityStatus = hasUnitConflict
    ? "conflicting"
    : points.length < definition.minimum_sample_size
    ? "limited"
    : freshness(latest.date, cutoff) === "stale"
    ? "stale"
    : "sufficient";
  const comparable = !hasUnitConflict;
  const directionalBestWorst = () => {
    if (!comparable) return { best: null, worst: null };
    if (definition.preferred_direction === "lower_is_better") {
      return { best: Math.min(...values), worst: Math.max(...values) };
    }
    if (definition.preferred_direction === "higher_is_better") {
      return { best: Math.max(...values), worst: Math.min(...values) };
    }
    if (
      definition.preferred_direction === "target_range" &&
      definition.target_min !== null && definition.target_max !== null
    ) {
      const distance = (value: number) =>
        value < definition.target_min!
          ? definition.target_min! - value
          : value > definition.target_max!
          ? value - definition.target_max!
          : 0;
      const ordered = [...values].sort((a, b) => distance(a) - distance(b));
      return { best: ordered[0]!, worst: ordered.at(-1)! };
    }
    return { best: null, worst: null };
  };
  const extremes = directionalBestWorst();
  return {
    canonical_metric_key: definition.canonical_key,
    display_name: definition.display_name,
    unit: hasUnitConflict ? null : definition.canonical_unit,
    latest_value: latest.value,
    prior_value: comparable ? prior?.value ?? null : null,
    absolute_change: comparable ? change : null,
    percentage_change: comparable && prior
      ? safePercentageChange(prior.value, latest.value)
      : null,
    rolling_average: comparable ? average(rollingValues) : null,
    recent_window_average: comparable ? recentAverage : null,
    prior_window_average: comparable ? priorAverage : null,
    best_value: extremes.best,
    worst_value: extremes.worst,
    sample_count: points.length,
    observation_frequency_days: frequency,
    freshness: freshness(latest.date, cutoff),
    quality,
    interpretation: comparable
      ? interpretTrend(definition, change, recentAverage, priorAverage)
      : "insufficient",
    rule_id: `trend.${definition.preferred_direction}.v1`,
    evidence_keys: points.slice(-2).map((point) => point.evidenceKey),
  };
}

const testingMetrics: Array<[keyof TestingEntry, string, string]> = [
  ["height_in", "physical.height", "in"],
  ["weight_lb", "physical.body_weight", "lb"],
  ["squat_1rm", "strength.squat_1rm", "lb"],
  ["bench_1rm", "strength.bench_1rm", "lb"],
  ["deadlift_1rm", "strength.deadlift_1rm", "lb"],
  ["max_exit_velo", "hitting.max_exit_velocity", "mph"],
  ["avg_exit_velo", "hitting.average_exit_velocity", "mph"],
  ["hip_er_diff", "mobility.hip_external_rotation_difference", "deg"],
  ["hip_ir_diff", "mobility.hip_internal_rotation_difference", "deg"],
  ["shoulder_ir_diff", "mobility.shoulder_internal_rotation_difference", "deg"],
  ["shoulder_er_diff", "mobility.shoulder_external_rotation_difference", "deg"],
];

export function buildEvidencePack(input: {
  orgId: string;
  playerId: string;
  reportType: string;
  windowStart: string;
  windowEnd: string;
  cutoff: string;
  definitions: MetricDefinition[];
  source: DevelopmentEvidenceSource;
}): DevelopmentEvidencePack {
  const definitionByKey = new Map(
    input.definitions.map((
      definition,
    ) => [definition.canonical_key, definition]),
  );
  const evidence: DevelopmentEvidence[] = [];
  const points = new Map<string, Point[]>();
  const demoProvenance = {
    demo_seed: true,
    demo_version: "phase_11a.v1",
    verification_status: "synthetic_unverified",
  };
  const noteIsDemo = (value: string | null | undefined) =>
    value?.includes("home_plate_demo_seed") === true;
  const addPoint = (
    metricKey: string,
    value: number,
    date: string,
    sourceType: string,
    sourceId: string,
    unit: string | null,
    raw: string,
    sourceMetadata: Record<string, unknown> = {},
  ) => {
    const key = `${sourceType}:${sourceId}:${metricKey}:${date}`;
    evidence.push({
      evidence_key: key,
      section_key: "metrics",
      source_entity_type: sourceType,
      source_record_id: sourceId,
      canonical_metric_key: metricKey,
      raw_observed_value: raw,
      normalized_numeric_value: value,
      unit,
      observation_date: date,
      comparison_value: null,
      comparison_period: null,
      direction: null,
      sample_size: 1,
      freshness: freshness(date, input.cutoff),
      quality: "sufficient",
      deterministic_rule_id: "source_adapter.v1",
      display_label: definitionByKey.get(metricKey)?.display_name ?? metricKey,
      explanation: `Observed ${raw}${unit ? ` ${unit}` : ""} on ${
        date.slice(0, 10)
      }.`,
      source_metadata: { source_type: sourceType, ...sourceMetadata },
      evidence_snapshot: {
        metric_key: metricKey,
        value,
        unit,
        observed_at: date,
        ...(sourceMetadata.demo_seed === true ? demoProvenance : {}),
      },
    });
    points.set(metricKey, [...(points.get(metricKey) ?? []), {
      value,
      date,
      evidenceKey: key,
      unit,
    }]);
  };

  for (const entry of input.source.testing_entries) {
    for (const [column, metricKey, unit] of testingMetrics) {
      const value = entry[column];
      if (typeof value === "number" && Number.isFinite(value)) {
        addPoint(
          metricKey,
          value,
          entry.entry_date,
          "sd_testing_entries",
          entry.id,
          unit,
          String(value),
          noteIsDemo(entry.notes) ? demoProvenance : {},
        );
      }
    }
  }
  for (const observation of input.source.metric_observations) {
    if (observation.normalized_value !== null) {
      addPoint(
        observation.canonical_key,
        observation.normalized_value,
        observation.observed_at,
        observation.source_entity_type,
        observation.source_record_id,
        observation.unit,
        observation.observed_value ?? String(observation.normalized_value),
        observation.context_metadata?.demo_seed === true
          ? {
            demo_seed: true,
            demo_version: observation.context_metadata.demo_version,
            verification_status:
              observation.context_metadata.verification_status,
            source_system: observation.source_system,
          }
          : {
            source_system: observation.source_system,
            provider: observation.source_system,
            import_job_id: observation.import_job_id,
            verification_status: observation.verification_status,
            original_unit: observation.original_unit,
            canonical_unit: observation.canonical_unit ?? observation.unit,
            parser_version: observation.parser_version,
            mapping_version: observation.mapping_version,
            source_row_number: observation.source_row_number,
          },
      );
    }
  }
  for (const assignment of input.source.program_assignments) {
    const evidenceKey =
      `sd_program_assignments:${assignment.id}:program_assignment:${assignment.start_date}`;
    evidence.push({
      evidence_key: evidenceKey,
      section_key: "program_context",
      source_entity_type: "sd_program_assignments",
      source_record_id: assignment.id,
      canonical_metric_key: null,
      raw_observed_value: null,
      normalized_numeric_value: null,
      unit: null,
      observation_date: assignment.start_date,
      comparison_value: null,
      comparison_period: null,
      direction: null,
      sample_size: 1,
      freshness: freshness(assignment.start_date, input.cutoff),
      quality: "sufficient",
      deterministic_rule_id: "program_assignment.context.v1",
      display_label: "Program assignment",
      explanation: `A program assignment started on ${
        assignment.start_date.slice(0, 10)
      }. Assignment evidence does not prove attendance or completion.`,
      source_metadata: {
        source_type: "sd_program_assignments",
        template_id: assignment.template_id,
        ...(noteIsDemo(assignment.notes) ? demoProvenance : {}),
      },
      evidence_snapshot: {
        assignment_id: assignment.id,
        template_id: assignment.template_id,
        start_date: assignment.start_date,
        ended_at: assignment.ended_at,
        completion_inferred: false,
        ...(noteIsDemo(assignment.notes) ? demoProvenance : {}),
      },
    });
  }
  for (const session of input.source.bp_sessions) {
    const velocities = session.events.map((event) => event.exit_velo).filter((
      value,
    ): value is number => typeof value === "number");
    if (velocities.length > 0) {
      addPoint(
        "hitting.max_exit_velocity",
        Math.max(...velocities),
        session.session_date,
        "sd_bp_sessions",
        session.id,
        "mph",
        String(Math.max(...velocities)),
        session.events.every((event) => event.raw?.demo_seed === true)
          ? demoProvenance
          : {},
      );
      addPoint(
        "hitting.average_exit_velocity",
        average(velocities)!,
        session.session_date,
        "sd_bp_sessions",
        session.id,
        "mph",
        String(average(velocities)!),
        session.events.every((event) => event.raw?.demo_seed === true)
          ? demoProvenance
          : {},
      );
    }
  }
  if (input.source.daily_logs.length > 0) {
    const processValues = input.source.daily_logs.map((log) =>
      log.stuck_to_process
    ).filter((value): value is boolean => value !== null);
    if (processValues.length > 0) {
      addPoint(
        "consistency.process_adherence_rate",
        processValues.filter(Boolean).length / processValues.length * 100,
        input.source.daily_logs.map((log) => log.log_date).sort().at(-1)!,
        "sd_daily_logs_window",
        `${input.playerId}:${input.windowStart}:${input.windowEnd}`,
        "percent",
        String(
          processValues.filter(Boolean).length / processValues.length * 100,
        ),
        input.source.daily_logs.every((log) => noteIsDemo(log.notes))
          ? demoProvenance
          : {},
      );
    }
  }

  const unitConflicts: string[] = [];
  for (const metricKey of points.keys()) {
    const units = new Set(
      evidence.filter((item) => item.canonical_metric_key === metricKey).map((
        item,
      ) => item.unit).filter(Boolean),
    );
    if (units.size > 1) {
      unitConflicts.push(
        `${metricKey} has conflicting units: ${[...units].join(", ")}.`,
      );
    }
  }
  const trends = [...points.entries()].flatMap(([key, metricPoints]) => {
    const definition = definitionByKey.get(key);
    if (!definition) return [];
    const trend = calculateTrend(definition, metricPoints, input.cutoff);
    return trend ? [trend] : [];
  });
  for (const trend of trends) {
    const latestEvidenceKey = trend.evidence_keys.at(-1);
    const latestEvidence = evidence.find((item) =>
      item.evidence_key === latestEvidenceKey
    );
    if (!latestEvidence) continue;
    latestEvidence.comparison_value = trend.prior_value;
    latestEvidence.comparison_period = trend.prior_value === null
      ? null
      : "prior comparable observation";
    latestEvidence.direction = trend.interpretation;
    latestEvidence.sample_size = trend.sample_count;
    latestEvidence.freshness = trend.freshness;
    latestEvidence.quality = trend.quality;
    latestEvidence.deterministic_rule_id = trend.rule_id;
    latestEvidence.evidence_snapshot = {
      ...latestEvidence.evidence_snapshot,
      prior_value: trend.prior_value,
      absolute_change: trend.absolute_change,
      percentage_change: trend.percentage_change,
      sample_count: trend.sample_count,
      freshness: trend.freshness,
      quality: trend.quality,
      interpretation: trend.interpretation,
      deterministic_rule_id: trend.rule_id,
    };
  }
  const lastObservation = evidence.map((item) => item.observation_date).filter((
    value,
  ): value is string => Boolean(value)).sort().at(-1) ?? null;
  const staleWarnings = [
    ...(freshness(lastObservation, input.cutoff) === "stale"
      ? [
        "The newest available development observation is more than 90 days old.",
      ]
      : []),
    ...trends.filter((trend) => trend.freshness === "stale").map((trend) =>
      `${trend.display_name} has no supported observation in the last 90 days.`
    ),
  ].filter((warning, index, all) => all.indexOf(warning) === index);
  const lowSampleWarnings = trends.filter((trend) =>
    trend.quality === "limited"
  ).map((trend) =>
    `${trend.display_name} has fewer than the recommended observations.`
  );
  const missing = [
    ...(input.source.source_warnings ?? []),
    ...(input.source.testing_entries.length === 0
      ? ["No testing entries were available for this reporting window."]
      : []),
    ...(input.source.daily_logs.length === 0
      ? ["No daily logs were available for this reporting window."]
      : []),
    ...(input.source.program_assignments.length === 0
      ? ["No program assignment overlapped this reporting window."]
      : []),
    ...(evidence.some((item) =>
        item.canonical_metric_key?.startsWith("hitting.")
      )
      ? []
      : [
        "No supported hitting observations were available for this reporting window.",
      ]),
    ...(evidence.some((item) =>
        item.canonical_metric_key?.startsWith("pitching.")
      )
      ? []
      : [
        "No supported pitching observations were available for this reporting window.",
      ]),
    "No authoritative attendance table is available.",
    "No explicit program-completion ledger is available.",
  ];
  const quality: DevelopmentQualityStatus = evidence.length === 0
    ? "unavailable"
    : unitConflicts.length > 0
    ? "conflicting"
    : staleWarnings.length > 0
    ? "stale"
    : lowSampleWarnings.length > 0
    ? "limited"
    : "sufficient";
  return {
    schema_version: "player_development_evidence_pack.v1",
    organization_id: input.orgId,
    player_id: input.playerId,
    player_name: input.source.player.full_name?.trim() ||
      `Player ${input.playerId.replaceAll("-", "").slice(0, 6).toUpperCase()}`,
    report_type: input.reportType,
    window_start: input.windowStart,
    window_end: input.windowEnd,
    evidence_cutoff: input.cutoff,
    quality_status: quality,
    data_freshness: freshness(lastObservation, input.cutoff),
    coverage: {
      testing_entries: input.source.testing_entries.length,
      metric_observations: input.source.metric_observations.length,
      daily_logs: input.source.daily_logs.length,
      program_assignments: input.source.program_assignments.length,
      bp_sessions: input.source.bp_sessions.length,
    },
    trends,
    evidence,
    missing_data_warnings: missing,
    stale_data_warnings: staleWarnings,
    unit_conflicts: unitConflicts,
    low_sample_warnings: lowSampleWarnings,
  };
}

export interface DevelopmentGenerationProvider {
  readonly provider: string;
  readonly mode: "deterministic" | "model" | "hybrid";
  readonly generatorVersion: string;
  generate(pack: DevelopmentEvidencePack): Promise<DevelopmentReportContent>;
}

export class DeterministicTemplateProvider
  implements DevelopmentGenerationProvider {
  readonly provider = "deterministic_template";
  readonly mode = "deterministic" as const;
  readonly generatorVersion: string;

  constructor(
    private readonly audience: DevelopmentRecordAudience = "staff",
  ) {
    this.generatorVersion = audience === "player"
      ? PLAYER_DEVELOPMENT_GENERATOR_VERSION
      : DEVELOPMENT_GENERATOR_VERSION;
  }

  async generate(
    pack: DevelopmentEvidencePack,
  ): Promise<DevelopmentReportContent> {
    const positive = pack.trends.filter((trend) =>
      trend.interpretation === "improvement"
    ).map((trend) => ({
      title: `${trend.display_name} moved in its preferred direction`,
      explanation:
        `${trend.display_name} changed from ${trend.prior_value} to ${trend.latest_value}${
          trend.unit ? ` ${trend.unit}` : ""
        } across comparable observations.`,
      evidence_keys: trend.evidence_keys,
    }));
    const priorities = pack.trends.filter((trend) =>
      trend.interpretation === "regression"
    ).map((trend) => ({
      title: this.audience === "player"
        ? `Discuss ${trend.display_name} with your coach`
        : `Review ${trend.display_name}`,
      explanation: this.audience === "player"
        ? `${trend.display_name} changed in a direction worth discussing with your coach. The cited measurements do not by themselves explain why it changed.`
        : `${trend.display_name} moved away from its configured preferred direction. A coach should review context before changing training.`,
      evidence_keys: trend.evidence_keys,
    }));
    const overview = pack.evidence.length === 0
      ? "There is not enough recorded development evidence to produce a substantive summary."
      : this.audience === "player"
      ? `This deterministic summary reviewed ${pack.evidence.length} player-visible evidence snapshots across ${pack.trends.length} supported metric trends. Facts and calculations are evidence-backed; interpretations should be discussed with a coach.`
      : `This deterministic draft reviewed ${pack.evidence.length} evidence snapshots across ${pack.trends.length} supported metric trends. It is advisory and requires coach review.`;
    return {
      overview,
      positive_trends: positive,
      development_priorities: priorities,
      consistency_and_attendance: pack.coverage.daily_logs > 0
        ? `${pack.coverage.daily_logs} daily logs were available. Attendance was not evaluated because Home Plate has no authoritative attendance table.`
        : "Consistency and attendance could not be evaluated from authoritative records.",
      data_gaps: [
        ...pack.missing_data_warnings,
        ...pack.stale_data_warnings,
        ...pack.unit_conflicts,
        ...pack.low_sample_warnings,
      ],
      coach_review_questions: this.audience === "player"
        ? [
          "Which cited measurement should I discuss with my coach?",
          "Are recent sessions or observations missing from my Home Plate record?",
        ]
        : [
          "Does the recorded context support these deterministic trend interpretations?",
          "Are there recent sessions or observations missing from Home Plate?",
        ],
      evidence_summary: pack.evidence.slice(0, 20).map((item) => ({
        label: item.display_label,
        explanation: item.explanation,
        evidence_key: item.evidence_key,
      })),
    };
  }
}

export function detectDeterministicAlerts(
  pack: DevelopmentEvidencePack,
  reportsAwaitingReview: number,
  audience: DevelopmentRecordAudience = "staff",
): AlertCandidate[] {
  const common = {
    org_id: pack.organization_id,
    player_id: pack.player_id,
    report_id: null,
    audience,
    status: "active" as const,
    evidence_window_start: pack.window_start,
    evidence_window_end: pack.window_end,
    rule_version: "development-alerts.v1",
    data_freshness: pack.data_freshness,
    evidence_quality: pack.quality_status,
  };
  const alerts: AlertCandidate[] = [];
  if (pack.coverage.testing_entries === 0) {
    alerts.push({
      ...common,
      alert_type: "no_recent_testing",
      severity: "attention",
      explanation: audience === "player"
        ? "You may benefit from updated testing. No testing result is available in this evidence window."
        : "No testing entry was recorded in the selected evidence window.",
      recommended_human_action: audience === "player"
        ? "Discuss with your coach whether updated testing would be useful."
        : "Confirm whether testing is due or whether recent results have not been entered.",
      deduplication_key: `no_recent_testing:${pack.window_end.slice(0, 7)}`,
      evidence: [],
    });
  } else if (
    freshness(
      pack.evidence.filter((item) =>
        item.source_entity_type === "sd_testing_entries"
      )
        .map((item) => item.observation_date).filter((value): value is string =>
          Boolean(value)
        ).sort().at(-1) ?? null,
      pack.evidence_cutoff,
    ) === "stale"
  ) {
    alerts.push({
      ...common,
      alert_type: "stale_testing",
      severity: "attention",
      explanation: audience === "player"
        ? "Your latest supported testing is more than 90 days old."
        : "The newest supported development observation is more than 90 days old.",
      recommended_human_action: audience === "player"
        ? "Ask your coach whether updated testing would help clarify your current progress."
        : "Review whether updated testing should be scheduled or entered.",
      deduplication_key: `stale_testing:${pack.window_end.slice(0, 7)}`,
      evidence: pack.evidence.slice(-1),
    });
  }
  for (const trend of pack.trends) {
    if (
      trend.interpretation !== "improvement" &&
      trend.interpretation !== "regression"
    ) continue;
    if (trend.sample_count < 2 || trend.absolute_change === null) continue;
    alerts.push({
      ...common,
      alert_type: trend.interpretation === "improvement"
        ? "meaningful_metric_improvement"
        : "meaningful_metric_regression",
      severity: trend.interpretation === "improvement" ? "info" : "attention",
      explanation: audience === "player" &&
          trend.interpretation === "regression"
        ? `${trend.display_name} changed from ${trend.prior_value} to ${trend.latest_value}${
          trend.unit ? ` ${trend.unit}` : ""
        }. This metric changed in a direction worth discussing with your coach.`
        : `${trend.display_name} changed from ${trend.prior_value} to ${trend.latest_value}${
          trend.unit ? ` ${trend.unit}` : ""
        }.`,
      recommended_human_action: audience === "player"
        ? "Review the cited measurements with your coach before changing any training plan or official record."
        : trend.interpretation === "improvement"
        ? "Confirm context and reinforce the process that supported the change."
        : "Review context, sample size, and measurement quality before adjusting the development plan.",
      deduplication_key:
        `${trend.interpretation}:${trend.canonical_metric_key}:${
          pack.window_end.slice(0, 7)
        }`,
      evidence: pack.evidence.filter((item) =>
        trend.evidence_keys.includes(item.evidence_key)
      ),
    });
  }
  if (pack.unit_conflicts.length > 0) {
    alerts.push({
      ...common,
      alert_type: "inconsistent_units",
      severity: audience === "player" ? "attention" : "high",
      explanation: audience === "player"
        ? "This measurement uses conflicting units and should be reviewed."
        : pack.unit_conflicts.join(" "),
      recommended_human_action: audience === "player"
        ? "Ask your coach to review the units before interpreting this metric."
        : "Resolve the unit conflict before interpreting this metric.",
      deduplication_key: `inconsistent_units:${pack.window_end.slice(0, 7)}`,
      evidence: pack.evidence.filter((item) =>
        pack.unit_conflicts.some((warning) =>
          item.canonical_metric_key &&
          warning.includes(item.canonical_metric_key)
        )
      ),
    });
  }
  for (
    const trend of pack.trends.filter((item) => item.quality === "limited")
  ) {
    alerts.push({
      ...common,
      alert_type: "insufficient_sample_size",
      severity: "info",
      explanation: audience === "player"
        ? `This metric has limited recent evidence. ${trend.display_name} has ${trend.sample_count} supported observation${
          trend.sample_count === 1 ? "" : "s"
        }.`
        : `${trend.display_name} has ${trend.sample_count} supported observation${
          trend.sample_count === 1 ? "" : "s"
        }, below the configured guidance.`,
      recommended_human_action: audience === "player"
        ? "Discuss whether more comparable measurements would make this trend clearer."
        : "Collect comparable observations before treating this as a reliable trend.",
      deduplication_key: `insufficient_sample:${trend.canonical_metric_key}:${
        pack.window_end.slice(0, 7)
      }`,
      evidence: pack.evidence.filter((item) =>
        trend.evidence_keys.includes(item.evidence_key)
      ),
    });
  }
  if (audience === "staff" && reportsAwaitingReview > 0) {
    alerts.push({
      ...common,
      alert_type: "report_awaiting_coach_review",
      severity: "info",
      explanation: `${reportsAwaitingReview} development report${
        reportsAwaitingReview === 1 ? " is" : "s are"
      } awaiting staff review.`,
      recommended_human_action:
        "Review the evidence and approve, edit, reject, or archive the draft.",
      deduplication_key: `report_awaiting_review:${
        pack.window_end.slice(0, 7)
      }`,
      evidence: [],
    });
  }
  return alerts;
}

function renderedText(content: DevelopmentReportContent): string {
  const lines = [content.overview];
  if (content.positive_trends.length > 0) {
    lines.push(
      "Positive trends",
      ...content.positive_trends.map((item) =>
        `• ${item.title}: ${item.explanation}`
      ),
    );
  }
  if (content.development_priorities.length > 0) {
    lines.push(
      "Development priorities",
      ...content.development_priorities.map((item) =>
        `• ${item.title}: ${item.explanation}`
      ),
    );
  }
  lines.push("Consistency and attendance", content.consistency_and_attendance);
  if (content.data_gaps.length > 0) {
    lines.push(
      "Data gaps",
      ...content.data_gaps.map((item) => `• ${item}`),
    );
  }
  return lines.join("\n\n");
}

function isObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

export function createPlayerDevelopmentAIHandler(
  store: PlayerDevelopmentAIStore,
  now: () => Date = () => new Date(),
  logStage: (
    event: string,
    fields: Record<string, string | number | boolean>,
  ) => void = () => {},
) {
  return async (request: Request): Promise<Response> => {
    if (request.method !== "POST") {
      return json(405, {
        error: "unsupported_action",
        message: safeMessage("unsupported_action"),
      });
    }
    const actorId = await store.authenticate(request);
    if (!actorId) {
      return json(401, {
        error: "invalid_auth",
        message: safeMessage("invalid_auth"),
      });
    }
    if (
      !await store.platformFeatureEnabled(
        PLAYER_DEVELOPMENT_COPILOT_FEATURE_KEY,
      )
    ) {
      return json(503, {
        error: "feature_disabled",
        message: safeMessage("feature_disabled"),
        retryable: false,
      });
    }
    let body: Record<string, unknown>;
    try {
      body = await readBoundedJSONObject(request);
    } catch (error) {
      const code =
        error instanceof Error && error.message === "request_too_large"
          ? "request_too_large"
          : "invalid_json";
      return json(code === "request_too_large" ? 413 : 400, {
        error: code,
        message: safeMessage(code),
      });
    }
    const action = typeof body.action === "string" ? body.action : "";
    const orgId = typeof body.org_id === "string"
      ? body.org_id.toLowerCase()
      : "";
    if (!uuidPattern.test(orgId)) {
      return json(400, {
        error: "invalid_request",
        message: safeMessage("invalid_request"),
      });
    }
    if (!supportedActions.has(action)) {
      return json(400, {
        error: "unsupported_action",
        message: safeMessage("unsupported_action"),
      });
    }
    if (action === "generate_report") {
      logStage("generate_request_received", { org_id: orgId });
      logStage("actor_verified", { org_id: orgId, actor_id: actorId });
    }
    try {
      if (await store.organizationStatus(orgId) !== "active") {
        return json(404, {
          error: "organization_unavailable",
          message: safeMessage("organization_unavailable"),
        });
      }
      if (action === "generate_report") {
        logStage("organization_authorized", { org_id: orgId });
      }
      const membership = await store.membership(orgId, actorId);
      const isStaff = membership?.status === "active" &&
        ["owner", "admin", "coach"].includes(membership.role);
      const isSelfPlayer = membership?.status === "active" &&
        membership.role === "player";
      if (!isStaff && !isSelfPlayer) {
        return json(403, {
          error: "staff_access_required",
          message: safeMessage("staff_access_required"),
        });
      }
      const playerActions = new Set([
        "generate_player_report",
        "list_player_reports",
        "get_player_report",
        "archive_player_report",
        "list_player_alerts",
        "get_player_alert",
        "dismiss_player_alert",
      ]);
      if (isSelfPlayer && !playerActions.has(action)) {
        return json(403, {
          error: "staff_access_required",
          message: safeMessage("staff_access_required"),
        });
      }
      if (
        isStaff && [
          "generate_player_report",
          "get_player_report",
          "archive_player_report",
          "get_player_alert",
          "dismiss_player_alert",
        ].includes(action)
      ) {
        return json(403, {
          error: "player_access_denied",
          message: safeMessage("player_access_denied"),
        });
      }
      const audience: DevelopmentRecordAudience = isSelfPlayer
        ? "player"
        : "staff";
      const authorizedPlayers = isSelfPlayer
        ? new Set([actorId])
        : await store.authorizedPlayerIds(orgId, actorId);
      let playerId = typeof body.player_id === "string"
        ? body.player_id.toLowerCase()
        : undefined;
      if (isSelfPlayer && playerId && playerId !== actorId) {
        return json(403, {
          error: "player_access_denied",
          message: safeMessage("player_access_denied"),
        });
      }
      if (isSelfPlayer && playerActions.has(action)) playerId = actorId;
      if (
        playerId &&
        (!uuidPattern.test(playerId) || !authorizedPlayers.has(playerId))
      ) {
        return json(403, {
          error: "player_access_denied",
          message: safeMessage("player_access_denied"),
        });
      }
      if (action === "generate_report" && playerId) {
        logStage("player_authorized", { org_id: orgId, player_id: playerId });
      }

      if (
        [
          "build_evidence_pack",
          "generate_report",
          "generate_player_report",
          "run_alert_detection",
        ]
          .includes(action)
      ) {
        if (!playerId) {
          return json(400, {
            error: "invalid_request",
            message: safeMessage("invalid_request"),
          });
        }
        const reportType = audience === "player"
          ? "player_development_summary"
          : typeof body.report_type === "string"
          ? body.report_type
          : "player_development_summary";
        const windowStart = typeof body.window_start === "string"
          ? body.window_start
          : "";
        const windowEnd = typeof body.window_end === "string"
          ? body.window_end
          : "";
        const cutoff = typeof body.evidence_cutoff === "string"
          ? body.evidence_cutoff
          : now().toISOString();
        const windowStartMilliseconds = exactISODateMilliseconds(windowStart);
        const windowEndMilliseconds = exactISODateMilliseconds(windowEnd);
        const cutoffMilliseconds = Date.parse(cutoff);
        if (
          !supportedReportTypes.has(reportType) ||
          windowStartMilliseconds === null || windowEndMilliseconds === null ||
          windowStartMilliseconds > windowEndMilliseconds ||
          windowEndMilliseconds - windowStartMilliseconds >
            DEVELOPMENT_MAX_REPORTING_WINDOW_DAYS * 86_400_000 ||
          !Number.isFinite(cutoffMilliseconds) ||
          cutoffMilliseconds < windowEndMilliseconds ||
          cutoffMilliseconds > now().getTime() + 300_000
        ) {
          return json(400, {
            error: "invalid_request",
            message: safeMessage("invalid_request"),
          });
        }
        const [definitions, source] = await Promise.all([
          store.metricDefinitions(),
          store.evidenceSource(orgId, playerId, windowStart, windowEnd, cutoff),
        ]);
        const sourcePack = buildEvidencePack({
          orgId,
          playerId,
          reportType,
          windowStart,
          windowEnd,
          cutoff,
          definitions,
          source,
        });
        const pack = audience === "player"
          ? playerVisibleEvidencePack(sourcePack)
          : sourcePack;
        if (action === "generate_report") {
          logStage("evidence_pack_built", {
            org_id: orgId,
            player_id: playerId,
            evidence_count: pack.evidence.length,
            trend_count: pack.trends.length,
          });
        }
        if (action === "build_evidence_pack") {
          return json(200, { evidence_pack: pack });
        }
        if (action === "run_alert_detection") {
          const alerts = await store.persistAlerts(
            actorId,
            orgId,
            detectDeterministicAlerts(
              pack,
              source.reports_awaiting_review,
              "staff",
            ),
            "staff",
          );
          return json(200, { alerts, detected_count: alerts.length });
        }
        const idempotencyKey = typeof body.idempotency_key === "string"
          ? body.idempotency_key.toLowerCase()
          : "";
        if (!uuidPattern.test(idempotencyKey)) {
          return json(400, {
            error: "invalid_request",
            message: safeMessage("invalid_request"),
          });
        }
        const intendedAudience = audience === "player"
          ? "player"
          : typeof body.intended_audience === "string"
          ? body.intended_audience
          : "coach";
        const allowedIntendedAudiences = audience === "player"
          ? ["player"]
          : ["coach", "staff", "parent_draft", "internal"];
        if (!allowedIntendedAudiences.includes(intendedAudience)) {
          return json(400, {
            error: "invalid_request",
            message: safeMessage("invalid_request"),
          });
        }
        const provider = new DeterministicTemplateProvider(audience);
        const content = await provider.generate(pack);
        logStage("deterministic_report_built", {
          org_id: orgId,
          player_id: playerId,
          evidence_count: pack.evidence.length,
        });
        const evidenceFingerprint = await evidencePackFingerprint(pack);
        const confidence = pack.quality_status === "sufficient"
          ? 0.85
          : pack.quality_status === "limited"
          ? 0.55
          : pack.quality_status === "unavailable"
          ? 0
          : 0.35;
        logStage("report_rpc_started", {
          org_id: orgId,
          player_id: playerId,
          evidence_count: pack.evidence.length,
        });
        let result: { report: DevelopmentReportRecord; reused: boolean };
        try {
          result = await store.createReport({
            actorId,
            orgId,
            playerId,
            reportType,
            intendedAudience,
            audience,
            windowStart,
            windowEnd,
            cutoff,
            idempotencyKey,
            evidenceFingerprint,
            qualityStatus: pack.quality_status,
            content,
            renderedText: renderedText(content),
            confidence,
            dataFreshness: pack.data_freshness,
            warnings: [
              ...pack.missing_data_warnings,
              ...pack.stale_data_warnings,
              ...pack.unit_conflicts,
              ...pack.low_sample_warnings,
            ],
            evidence: pack.evidence,
            promptVersion: audience === "player"
              ? PLAYER_DEVELOPMENT_PROMPT_VERSION
              : DEVELOPMENT_PROMPT_VERSION,
            generatorVersion: provider.generatorVersion,
          });
        } catch (error) {
          logStage("report_rpc_failed", {
            org_id: orgId,
            player_id: playerId,
            error_code: error instanceof Error &&
                error.message.includes(
                  "development_report_idempotency_conflict",
                )
              ? "development_report_idempotency_conflict"
              : "development_report_create_failed",
          });
          throw error;
        }
        logStage("report_rpc_succeeded", {
          org_id: orgId,
          player_id: playerId,
          reused: result.reused,
        });
        const playerAlerts = audience === "player"
          ? await store.persistAlerts(
            actorId,
            orgId,
            detectDeterministicAlerts(pack, 0, "player"),
            "player",
          )
          : [];
        return json(200, {
          ...result,
          evidence_pack: pack,
          player_alerts: playerAlerts,
        });
      }

      if (
        action === "list_player_reports" ||
        action === "list_organization_reports"
      ) {
        const reports = await store.listReports(
          orgId,
          [...authorizedPlayers],
          action === "list_player_reports" ? playerId : undefined,
          audience,
        );
        return json(200, { reports });
      }
      if (action === "get_report" || action === "get_player_report") {
        const reportId = typeof body.report_id === "string"
          ? body.report_id
          : "";
        if (!uuidPattern.test(reportId)) {
          return json(400, {
            error: "invalid_request",
            message: safeMessage("invalid_request"),
          });
        }
        const detail = await store.reportDetail(
          orgId,
          reportId,
          [...authorizedPlayers],
          audience,
        );
        if (
          !detail ||
          (detail.report.player_id &&
            !authorizedPlayers.has(detail.report.player_id))
        ) {
          return json(404, {
            error: "report_not_found",
            message: safeMessage("report_not_found"),
          });
        }
        return json(200, detail as unknown as Record<string, unknown>);
      }
      if (action === "review_report") {
        const reportId = typeof body.report_id === "string"
          ? body.report_id
          : "";
        const reviewAction = typeof body.review_action === "string"
          ? body.review_action
          : "";
        const notes = typeof body.review_notes === "string"
          ? body.review_notes.trim().slice(0, 2000)
          : null;
        const edits = isObject(body.coach_edits) ? body.coach_edits : {};
        if (
          !uuidPattern.test(reportId) ||
          !["review", "approve", "reject", "archive", "edit"].includes(
            reviewAction,
          )
        ) {
          return json(400, {
            error: "invalid_request",
            message: safeMessage("invalid_request"),
          });
        }
        return json(200, {
          report: await store.reviewReport(
            actorId,
            orgId,
            reportId,
            reviewAction,
            notes,
            edits,
            "staff",
          ),
        });
      }
      if (action === "archive_player_report") {
        const reportId = typeof body.report_id === "string"
          ? body.report_id
          : "";
        if (!uuidPattern.test(reportId)) {
          return json(400, {
            error: "invalid_request",
            message: safeMessage("invalid_request"),
          });
        }
        return json(200, {
          report: await store.reviewReport(
            actorId,
            orgId,
            reportId,
            "archive",
            null,
            {},
            "player",
          ),
        });
      }
      if (
        ["list_player_alerts", "list_organization_alerts", "roster_attention"]
          .includes(action)
      ) {
        const alerts = await store.listAlerts(
          orgId,
          [...authorizedPlayers],
          action === "list_player_alerts" ? playerId : undefined,
          audience,
        );
        const reports = action === "roster_attention"
          ? await store.listReports(
            orgId,
            [...authorizedPlayers],
            undefined,
            "staff",
          )
          : [];
        if (action === "roster_attention") {
          return json(200, {
            alerts: alerts.filter((alert) =>
              ["active", "acknowledged"].includes(alert.status)
            ),
            reports_awaiting_review: reports.filter((report) =>
              ["draft", "reviewed"].includes(report.status)
            ),
          });
        }
        return json(200, { alerts });
      }
      if (action === "get_alert" || action === "get_player_alert") {
        const alertId = typeof body.alert_id === "string" ? body.alert_id : "";
        if (!uuidPattern.test(alertId)) {
          return json(400, {
            error: "invalid_request",
            message: safeMessage("invalid_request"),
          });
        }
        const detail = await store.alertDetail(
          orgId,
          alertId,
          [...authorizedPlayers],
          audience,
        );
        if (!detail || !authorizedPlayers.has(detail.alert.player_id)) {
          return json(404, {
            error: "alert_not_found",
            message: safeMessage("alert_not_found"),
          });
        }
        return json(200, detail as unknown as Record<string, unknown>);
      }
      if (action === "review_alert") {
        const alertId = typeof body.alert_id === "string" ? body.alert_id : "";
        const reviewAction = typeof body.review_action === "string"
          ? body.review_action
          : "";
        const notes = typeof body.review_notes === "string"
          ? body.review_notes.trim().slice(0, 2000)
          : null;
        if (
          !uuidPattern.test(alertId) ||
          !["acknowledge", "dismiss", "resolve", "archive"].includes(
            reviewAction,
          )
        ) {
          return json(400, {
            error: "invalid_request",
            message: safeMessage("invalid_request"),
          });
        }
        return json(200, {
          alert: await store.reviewAlert(
            actorId,
            orgId,
            alertId,
            reviewAction,
            notes,
            "staff",
          ),
        });
      }
      if (action === "dismiss_player_alert") {
        const alertId = typeof body.alert_id === "string" ? body.alert_id : "";
        if (!uuidPattern.test(alertId)) {
          return json(400, {
            error: "invalid_request",
            message: safeMessage("invalid_request"),
          });
        }
        return json(200, {
          alert: await store.reviewAlert(
            actorId,
            orgId,
            alertId,
            "dismiss",
            null,
            "player",
          ),
        });
      }
      return json(400, {
        error: "unsupported_action",
        message: safeMessage("unsupported_action"),
      });
    } catch (error) {
      const text = error instanceof Error ? error.message : "";
      for (
        const code of [
          "development_report_idempotency_conflict",
          "invalid_report_transition",
          "invalid_alert_transition",
          "report_not_found",
          "alert_not_found",
        ]
      ) {
        if (text.includes(code)) {
          return json(code.includes("not_found") ? 404 : 409, {
            error: code,
            message: safeMessage(code),
          });
        }
      }
      return json(500, {
        error: "development_ai_failed",
        message: safeMessage("development_ai_failed"),
      });
    }
  };
}
