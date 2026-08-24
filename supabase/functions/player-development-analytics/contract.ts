export const ANALYTICS_SCHEMA_VERSION = 2;
export const ANALYTICS_MODEL_VERSION = "homeplate-r-analytics.v2";

export const ANALYTICS_DISCIPLINES = ["hitting", "pitching"] as const;
export type AnalyticsDiscipline = typeof ANALYTICS_DISCIPLINES[number];

export const PITCHING_MODULES = [
  "overview_arsenal",
  "velocity_extension",
  "pitch_break_shape",
  "release_location",
  "counts_finish",
  "pitch_log",
] as const;

export const HITTING_MODULES = [
  "overview_quality",
  "contact_spray",
  "swing_decisions",
  "count_approach",
  "velocity_exposure",
  "zone_maps",
  "two_strikes",
] as const;

export type AnalyticsModule =
  | typeof PITCHING_MODULES[number]
  | typeof HITTING_MODULES[number];

export type AnalyticsFilters = {
  start_date?: string;
  end_date?: string;
  pitch_types?: string[];
  counts?: string[];
  batter_sides?: string[];
  pitcher_throws?: string[];
};

export type AnalyticsRequest = {
  action?:
    | "get_catalog"
    | "list_sources"
    | "run_analysis"
    | "get_cached_analysis"
    | "invalidate_player_cache";
  org_id?: string;
  player_id?: string;
  import_job_id?: string;
  discipline?: AnalyticsDiscipline;
  module?: AnalyticsModule;
  provider?: string;
  filters?: AnalyticsFilters;
};

export type AnalyticsTable = {
  id: string;
  title: string;
  description?: string | null;
  columns: Array<{ key: string; label: string }>;
  rows: Array<Record<string, unknown>>;
};

export type AnalyticsChart = {
  id: string;
  title: string;
  description?: string | null;
  type: string;
  x?: string | null;
  y?: string | null;
  series?: string | null;
  data: Array<Record<string, unknown>>;
  options?: Record<string, unknown>;
};

export type AnalyticsSource = {
  id: string;
  provider: string;
  file_name: string;
  row_count: number;
  completed_at: string;
};

export type AnalyticsResponse = {
  schema_version: number;
  model_version: string;
  benchmark_version: string;
  generated_at: string;
  discipline: AnalyticsDiscipline;
  module: AnalyticsModule;
  filters: AnalyticsFilters;
  sample_summary: Record<string, unknown>;
  source_coverage: Record<string, unknown>;
  benchmark_summary: Record<string, unknown>;
  summary_metrics: Array<Record<string, unknown>>;
  tables: AnalyticsTable[];
  charts: AnalyticsChart[];
  guidance: Record<string, unknown>;
  warnings: unknown[];
  unavailable_reasons: Array<Record<string, unknown>>;
  cache_status?: "hit" | "miss";
};

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export function normalizedUuid(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const normalized = value.trim().toLowerCase();
  return UUID_PATTERN.test(normalized) ? normalized : null;
}

export function validModule(
  discipline: AnalyticsDiscipline,
  module: unknown,
): module is AnalyticsModule {
  if (typeof module !== "string") return false;
  return discipline === "pitching"
    ? (PITCHING_MODULES as readonly string[]).includes(module)
    : (HITTING_MODULES as readonly string[]).includes(module);
}

export function normalizedFilters(value: unknown): AnalyticsFilters {
  if (!value || typeof value !== "object" || Array.isArray(value)) return {};
  const source = value as Record<string, unknown>;
  const output: AnalyticsFilters = {};
  const date = (candidate: unknown) =>
    typeof candidate === "string" && /^\d{4}-\d{2}-\d{2}$/.test(candidate)
      ? candidate
      : undefined;
  const list = (candidate: unknown) =>
    Array.isArray(candidate)
      ? candidate.filter((item): item is string =>
        typeof item === "string" && item.trim().length > 0
      ).map((item) => item.trim()).slice(0, 25)
      : undefined;
  output.start_date = date(source.start_date);
  output.end_date = date(source.end_date);
  output.pitch_types = list(source.pitch_types);
  output.counts = list(source.counts);
  output.batter_sides = list(source.batter_sides);
  output.pitcher_throws = list(source.pitcher_throws);
  return Object.fromEntries(
    Object.entries(output).filter(([, item]) => item !== undefined),
  ) as AnalyticsFilters;
}

export function stableStringify(value: unknown): string {
  if (value === null || typeof value !== "object") return JSON.stringify(value);
  if (Array.isArray(value)) {
    return `[${value.map((item) => stableStringify(item)).join(",")}]`;
  }
  const object = value as Record<string, unknown>;
  return `{${
    Object.keys(object).sort().map((key) =>
      `${JSON.stringify(key)}:${stableStringify(object[key])}`
    ).join(",")
  }}`;
}

export function canAccessPlayer(
  role: string,
  actorId: string,
  playerId: string,
  linkedChildIds: ReadonlySet<string>,
  coachTeamIds: ReadonlySet<string>,
  playerTeamIds: ReadonlySet<string>,
  organizationWideCoachAccess = false,
): boolean {
  const normalizedRole = role.trim().toLowerCase();
  if (normalizedRole === "owner" || normalizedRole === "admin") return true;
  if (normalizedRole === "player") return actorId === playerId;
  if (normalizedRole === "parent") return linkedChildIds.has(playerId);
  if (normalizedRole !== "coach") return false;
  if (organizationWideCoachAccess) return true;
  return [...playerTeamIds].some((teamId) => coachTeamIds.has(teamId));
}
