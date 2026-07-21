export const EVENT_TYPES = [
  "practice",
  "game",
  "tournament",
  "meeting",
  "travel",
  "custom",
] as const;

export type EventType = typeof EVENT_TYPES[number];
export type RecurrenceFrequency = "daily" | "weekly";

export interface RecurrenceRule {
  frequency: RecurrenceFrequency;
  interval: number;
  weekdays?: number[];
  endsOn?: string | null;
  occurrenceCount?: number | null;
}

export interface MaterializedOccurrence {
  index: number;
  startAt: string;
  endAt: string;
  originalStartAt: string;
}

const DAY_MS = 86_400_000;
const MAX_OCCURRENCES = 366;

export function isEventType(value: unknown): value is EventType {
  return EVENT_TYPES.includes(String(value) as EventType);
}

export function requiredCapability(type: EventType): string | null {
  switch (type) {
    case "practice":
      return "manage_practice_event";
    case "game":
      return "manage_game_event";
    case "tournament":
      return "manage_tournament_event";
    case "meeting":
      return "manage_meeting_event";
    case "travel":
      return "manage_travel_event";
    case "custom":
      return null;
  }
}

export type ScheduleReadAuthority = {
  allowed: boolean;
  code: "allowed" | "permission_denied";
};

export function resolveScheduleReadAuthority(
  role: string,
  capabilities: string[],
): ScheduleReadAuthority {
  const normalizedRole = role.trim().toLowerCase();
  if (normalizedRole === "owner" || normalizedRole === "admin") {
    return { allowed: true, code: "allowed" };
  }
  if (
    normalizedRole === "coach" && capabilities.includes("view_team_schedule")
  ) {
    return { allowed: true, code: "allowed" };
  }
  return { allowed: false, code: "permission_denied" };
}

function utcDayKey(date: Date): string {
  return date.toISOString().slice(0, 10);
}

export function validateRecurrence(rule: RecurrenceRule): string | null {
  if (
    !Number.isInteger(rule.interval) || rule.interval < 1 || rule.interval > 52
  ) {
    return "invalid_recurrence_interval";
  }
  if (rule.endsOn && rule.occurrenceCount) return "ambiguous_recurrence_end";
  if (
    rule.occurrenceCount != null && (
      !Number.isInteger(rule.occurrenceCount) || rule.occurrenceCount < 1 ||
      rule.occurrenceCount > MAX_OCCURRENCES
    )
  ) return "invalid_occurrence_count";
  if (rule.frequency === "weekly") {
    const days = rule.weekdays ?? [];
    if (
      !days.length ||
      days.some((day) => !Number.isInteger(day) || day < 0 || day > 6)
    ) {
      return "invalid_recurrence_weekdays";
    }
  }
  if (rule.endsOn && !/^\d{4}-\d{2}-\d{2}$/.test(rule.endsOn)) {
    return "invalid_recurrence_end";
  }
  return null;
}

/**
 * Deterministic UTC occurrence materialization. The event instant is retained;
 * timezone is stored with the series for presentation and future local-time
 * edits. Selected weekdays use JavaScript weekday numbers (Sunday = 0).
 */
export function materializeOccurrences(
  startAt: string,
  endAt: string,
  rule?: RecurrenceRule | null,
): MaterializedOccurrence[] {
  const start = new Date(startAt);
  const end = new Date(endAt);
  if (
    !Number.isFinite(start.getTime()) || !Number.isFinite(end.getTime()) ||
    end <= start
  ) {
    throw new Error("invalid_event_times");
  }
  if (!rule) {
    return [{
      index: 0,
      startAt: start.toISOString(),
      endAt: end.toISOString(),
      originalStartAt: start.toISOString(),
    }];
  }
  const validation = validateRecurrence(rule);
  if (validation) throw new Error(validation);
  const duration = end.getTime() - start.getTime();
  const maxCount = rule.occurrenceCount ?? MAX_OCCURRENCES;
  const endDay = rule.endsOn ?? null;
  const output: MaterializedOccurrence[] = [];
  const weekdays = new Set(rule.weekdays ?? [start.getUTCDay()]);
  let cursor = new Date(start);
  let scanned = 0;
  while (
    output.length < maxCount && output.length < MAX_OCCURRENCES &&
    scanned < MAX_OCCURRENCES * 14
  ) {
    const dayKey = utcDayKey(cursor);
    if (endDay && dayKey > endDay) break;
    const elapsedDays = Math.floor(
      (Date.UTC(
        cursor.getUTCFullYear(),
        cursor.getUTCMonth(),
        cursor.getUTCDate(),
      ) -
        Date.UTC(
          start.getUTCFullYear(),
          start.getUTCMonth(),
          start.getUTCDate(),
        )) / DAY_MS,
    );
    const elapsedWeeks = Math.floor(elapsedDays / 7);
    const include = rule.frequency === "daily"
      ? elapsedDays % rule.interval === 0
      : elapsedWeeks % rule.interval === 0 && weekdays.has(cursor.getUTCDay());
    if (include && cursor >= start) {
      const occurrenceStart = new Date(cursor);
      occurrenceStart.setUTCHours(
        start.getUTCHours(),
        start.getUTCMinutes(),
        start.getUTCSeconds(),
        start.getUTCMilliseconds(),
      );
      output.push({
        index: output.length,
        startAt: occurrenceStart.toISOString(),
        endAt: new Date(occurrenceStart.getTime() + duration).toISOString(),
        originalStartAt: occurrenceStart.toISOString(),
      });
    }
    cursor = new Date(cursor.getTime() + DAY_MS);
    scanned += 1;
  }
  if (!output.length) throw new Error("recurrence_has_no_occurrences");
  return output;
}

export function sanitizeEventForConsumer(event: Record<string, unknown>) {
  const { notes: _notes, metadata: _metadata, ...safe } = event;
  return safe;
}

export function notificationIntent(
  before: Record<string, unknown> | null,
  after: Record<string, unknown>,
):
  | "new_event"
  | "time_change"
  | "location_change"
  | "cancellation"
  | "postponement"
  | null {
  if (
    (!before && after.status !== "draft") ||
    (before?.status === "draft" && after.status !== "draft")
  ) return "new_event";
  if (before?.status !== "cancelled" && after.status === "cancelled") {
    return "cancellation";
  }
  if (before?.status !== "postponed" && after.status === "postponed") {
    return "postponement";
  }
  if (
    before &&
    (before.start_at !== after.start_at || before.end_at !== after.end_at)
  ) return "time_change";
  if (
    before &&
    (before.location_name !== after.location_name ||
      before.address !== after.address)
  ) return "location_change";
  return null;
}
