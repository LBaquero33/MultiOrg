export const OPERATION_STATUSES = [
  "not_started",
  "ready",
  "in_progress",
  "paused",
  "completed",
  "cancelled",
] as const;
export type OperationStatus = typeof OPERATION_STATUSES[number];

export const AVAILABILITY_STATUSES = [
  "unknown",
  "available",
  "unavailable",
  "tentative",
  "late",
  "leaving_early",
] as const;
export type AvailabilityStatus = typeof AVAILABILITY_STATUSES[number];

export const ATTENDANCE_STATUSES = [
  "not_recorded",
  "present",
  "absent",
  "late",
  "excused",
  "injured",
  "partial",
] as const;
export type AttendanceStatus = typeof ATTENDANCE_STATUSES[number];

export function operationTypeForEvent(eventType: string) {
  switch (eventType) {
    case "practice":
      return "practice_day";
    case "game":
      return "game_day";
    case "tournament":
      return "tournament_day";
    case "meeting":
      return "meeting_day";
    case "travel":
      return "travel_day";
    default:
      return "general_event_day";
  }
}

export function isOperationStatus(value: unknown): value is OperationStatus {
  return OPERATION_STATUSES.includes(String(value) as OperationStatus);
}

export function isAvailabilityStatus(
  value: unknown,
): value is AvailabilityStatus {
  return AVAILABILITY_STATUSES.includes(String(value) as AvailabilityStatus);
}

export function isAttendanceStatus(
  value: unknown,
): value is AttendanceStatus {
  return ATTENDANCE_STATUSES.includes(String(value) as AttendanceStatus);
}

export function mayTransition(
  from: OperationStatus,
  to: OperationStatus,
): boolean {
  const allowed: Record<OperationStatus, OperationStatus[]> = {
    not_started: ["ready", "in_progress"],
    ready: ["in_progress", "completed"],
    in_progress: ["paused", "completed"],
    paused: ["in_progress", "completed"],
    completed: ["ready"],
    cancelled: [],
  };
  return allowed[from].includes(to);
}

export function operationPrimaryAction(status: OperationStatus, type: string) {
  switch (status) {
    case "not_started":
      return "Prepare";
    case "ready":
      return type === "game_day"
        ? "Start Game Day"
        : type === "practice_day"
        ? "Start Practice"
        : "Start Check-In";
    case "in_progress":
      return "Complete Event";
    case "paused":
      return "Resume";
    case "completed":
      return "Review Event";
    case "cancelled":
      return "Review Event";
  }
}

export function completionBlockers(
  participants: Array<Record<string, unknown>>,
  checklist: Array<Record<string, unknown>>,
) {
  const attendance =
    participants.filter((participant) =>
      participant.expected === true &&
      participant.participant_type === "player" &&
      participant.attendance_status === "not_recorded"
    ).length;
  const requiredChecklist =
    checklist.filter((item) =>
      item.required === true && !item.completed_at && !item.overridden_at
    ).length;
  return { attendance, requiredChecklist };
}

export function sanitizeParticipantForConsumer(
  participant: Record<string, unknown>,
) {
  const {
    attendance_notes: _attendanceNotes,
    private_notes: _privateNotes,
    checked_in_by: _checkedInBy,
    ...safe
  } = participant;
  return safe;
}

export function sanitizeOperationForConsumer(
  operation: Record<string, unknown>,
) {
  const { internal_notes: _internalNotes, ...safe } = operation;
  return safe;
}

export function isNearEventStart(startAt: string, now = new Date()) {
  const delta = new Date(startAt).getTime() - now.getTime();
  return delta <= 24 * 60 * 60 * 1000 && delta >= -6 * 60 * 60 * 1000;
}
