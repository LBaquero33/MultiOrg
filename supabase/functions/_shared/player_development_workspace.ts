export const PLAYER_DEVELOPMENT_WORKSPACE_SCHEMA_VERSION = 1;

export function normalizeWorkspaceUuid(
  value: unknown,
): string | null {
  if (typeof value !== "string") return null;
  const normalized = value.trim().toLowerCase();
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/
      .test(normalized)
    ? normalized
    : null;
}

export const PLAYER_DEVELOPMENT_SECTIONS = [
  "Player Hub",
  "Calendar",
  "Programs",
  "Testing",
  "Sessions & Data",
  "Media",
  "Templates",
  "Testing Setup",
] as const;

export function videoPlaybackStatus(
  mimeType: string | null | undefined,
  objectPath: string | null | undefined,
): "ready" | "needs_conversion" {
  const normalizedMime = mimeType?.trim().toLowerCase();
  if (normalizedMime) {
    return normalizedMime === "video/mp4" ? "ready" : "needs_conversion";
  }
  return objectPath?.trim().toLowerCase().endsWith(".mp4")
    ? "ready"
    : "needs_conversion";
}

export type DevelopmentStatus = "submitted" | "missed" | "upcoming";
export type DevelopmentActivityKind =
  | "program"
  | "daily_log"
  | "testing"
  | "session"
  | "provider_import"
  | "provider_metric";
export type DevelopmentMediaKind =
  | "program_set_video"
  | "testing_field_video"
  | "session_video"
  | "import_file";

export type WorkspaceMembership = { role: string; status: string };
export type WorkspacePlayer = {
  id: string;
  name: string;
  avatar_path: string | null;
  bio: string | null;
  instagram_url: string | null;
  perfect_game_url: string | null;
  team_ids: string[];
};

export type ProgramAssignmentSummary = {
  id: string;
  template_id: string;
  template_name: string;
  program_kind: string;
  start_date: string;
  end_date: string;
  status: "active" | "ended";
  notes: string | null;
};

export type DevelopmentActivity = {
  id: string;
  date: string;
  kind: DevelopmentActivityKind;
  source: string;
  title: string;
  subtitle: string | null;
  details: Record<string, unknown>;
  warning: string | null;
};

export type DevelopmentMedia = {
  id: string;
  date: string;
  kind: DevelopmentMediaKind;
  title: string;
  file_name: string | null;
  mime_type: string | null;
  source: string;
  playback_status: "ready" | "needs_conversion";
};

export type DevelopmentDay = {
  date: string;
  status: DevelopmentStatus;
  scheduled: boolean;
  activity_count: number;
  media_count: number;
  activities: DevelopmentActivity[];
  media: DevelopmentMedia[];
};

export type ProviderSessionSummary = {
  id: string;
  date: string;
  provider: string;
  activity_type: string;
  status: string;
  metric_count: number;
  has_file: boolean;
  has_video: boolean;
};

export type PlayerDevelopmentWorkspace = {
  schema_version: number;
  organization_id: string;
  generated_at: string;
  sections: readonly string[];
  player: WorkspacePlayer;
  assignments: ProgramAssignmentSummary[];
  days: DevelopmentDay[];
  provider_sessions: ProviderSessionSummary[];
};

export type ScheduledDateInput = {
  start_date: string;
  end_date: string | null;
  weeks: number;
  lift_weekdays: number[];
};

function utcDate(value: string): Date {
  return new Date(`${value.slice(0, 10)}T12:00:00.000Z`);
}

export function dateOnly(value: unknown): string | null {
  if (typeof value !== "string" || value.length < 10) return null;
  const candidate = value.slice(0, 10);
  return /^\d{4}-\d{2}-\d{2}$/.test(candidate) ? candidate : null;
}

export function scheduledDates(input: ScheduledDateInput): string[] {
  const weekdays = [
    ...new Set(input.lift_weekdays.filter((day) => day >= 1 && day <= 7)),
  ].sort();
  if (!dateOnly(input.start_date) || weekdays.length === 0) return [];
  const cursor = utcDate(input.start_date);
  const expected = Math.max(1, input.weeks) * weekdays.length;
  const output: string[] = [];
  let guard = 0;
  while (output.length < expected && guard < 500) {
    const date = cursor.toISOString().slice(0, 10);
    const weekday = cursor.getUTCDay() || 7;
    if (weekdays.includes(weekday)) {
      if (input.end_date && date > input.end_date.slice(0, 10)) break;
      output.push(date);
    }
    cursor.setUTCDate(cursor.getUTCDate() + 1);
    guard += 1;
  }
  return output;
}

export function completionStatus(
  date: string,
  scheduled: boolean,
  hasActivity: boolean,
  today: string,
): DevelopmentStatus {
  if (hasActivity) return "submitted";
  if (scheduled && date < today) return "missed";
  return "upcoming";
}

export function buildDevelopmentDays(
  scheduled: Iterable<string>,
  activities: DevelopmentActivity[],
  media: DevelopmentMedia[],
  today = new Date().toISOString().slice(0, 10),
): DevelopmentDay[] {
  const scheduledSet = new Set(scheduled);
  const allDates = new Set(scheduledSet);
  for (const item of activities) allDates.add(item.date);
  for (const item of media) allDates.add(item.date);

  return [...allDates].sort().map((date) => {
    const dayActivities = activities.filter((item) => item.date === date);
    const dayMedia = media.filter((item) => item.date === date);
    const isScheduled = scheduledSet.has(date);
    return {
      date,
      status: completionStatus(
        date,
        isScheduled,
        dayActivities.length > 0 || dayMedia.length > 0,
        today,
      ),
      scheduled: isScheduled,
      activity_count: dayActivities.length,
      media_count: dayMedia.length,
      activities: dayActivities,
      media: dayMedia,
    };
  });
}

export function canUseOrganizationMembership(
  membership: WorkspaceMembership | null,
): boolean {
  if (!membership || membership.status.trim().toLowerCase() !== "active") {
    return false;
  }
  return ["owner", "admin", "coach", "player", "parent"].includes(
    membership.role.trim().toLowerCase(),
  );
}

export function canUseStaffSections(
  membership: WorkspaceMembership | null,
): boolean {
  if (!canUseOrganizationMembership(membership)) return false;
  return ["owner", "admin", "coach"].includes(
    membership!.role.trim().toLowerCase(),
  );
}
