export type RegistrationStaffRole = "manager" | "evaluator" | "camp_staff";
export type RegistrationDecisionState =
  | "unreviewed"
  | "watchlist"
  | "undecided"
  | "offer_roster_spot"
  | "decline";
export type EvaluationInputType =
  | "letter_grade"
  | "twenty_eighty"
  | "one_hundred"
  | "comment_only";

export type RegistrationParticipantForRelease = {
  id: string;
  decision_state: string;
  contact_email?: string | null;
};

const FINAL_DECISIONS = new Set(["offer_roster_spot", "decline"]);
const LETTER_GRADES = new Set([
  "A+",
  "A",
  "A-",
  "B+",
  "B",
  "B-",
  "C+",
  "C",
  "C-",
  "D+",
  "D",
  "D-",
  "F",
]);

export function isFinalRegistrationDecision(value: unknown): boolean {
  return FINAL_DECISIONS.has(String(value ?? "").trim().toLowerCase());
}

export function validateDecisionRelease(
  participants: RegistrationParticipantForRelease[],
  releaseAll: boolean,
): { participantIds: string[] } {
  if (!participants.length) throw new Error("decision_release_empty");
  if (
    releaseAll &&
    participants.some((participant) =>
      !isFinalRegistrationDecision(participant.decision_state)
    )
  ) {
    throw new Error("decision_release_unresolved_participants");
  }
  const releasable = participants.filter((participant) =>
    isFinalRegistrationDecision(participant.decision_state)
  );
  if (!releasable.length) {
    throw new Error("decision_release_no_finalized_participants");
  }
  if (
    releasable.some((participant) =>
      !String(participant.contact_email ?? "").includes("@")
    )
  ) {
    throw new Error("decision_release_recipient_email_required");
  }
  return { participantIds: releasable.map((participant) => participant.id) };
}

export function normalizedPhoneDigits(value: unknown): string {
  return String(value ?? "").replace(/\D/g, "");
}

export function registrationPhoneLastFourMatches(
  storedPhone: unknown,
  submittedLastFour: unknown,
): boolean {
  const stored = normalizedPhoneDigits(storedPhone);
  const submitted = normalizedPhoneDigits(submittedLastFour);
  return stored.length >= 4 && submitted.length === 4 &&
    stored.slice(-4) === submitted;
}

export function validateEvaluationValue(
  inputType: EvaluationInputType,
  value: unknown,
): { valueText: string | null; valueNumber: number | null } {
  const raw = String(value ?? "").trim();
  if (inputType === "comment_only") {
    return { valueText: null, valueNumber: null };
  }
  if (!raw) throw new Error("evaluation_value_required");
  if (inputType === "letter_grade") {
    const grade = raw.toUpperCase();
    if (!LETTER_GRADES.has(grade)) {
      throw new Error("evaluation_letter_grade_invalid");
    }
    return { valueText: grade, valueNumber: null };
  }
  const number = Number(raw);
  if (!Number.isFinite(number)) throw new Error("evaluation_number_invalid");
  if (
    inputType === "twenty_eighty" &&
    (number < 20 || number > 80 || number % 5 !== 0)
  ) {
    throw new Error("evaluation_twenty_eighty_invalid");
  }
  if (inputType === "one_hundred" && (number < 1 || number > 100)) {
    throw new Error("evaluation_one_hundred_invalid");
  }
  return { valueText: null, valueNumber: number };
}

export function averageEvaluationValues(values: unknown[]): number | null {
  const numbers = values.map(Number).filter(Number.isFinite);
  if (!numbers.length) return null;
  return Math.round(
    (numbers.reduce((sum, value) => sum + value, 0) / numbers.length) * 10,
  ) / 10;
}

export function mayUseRegistrationOffering(
  organizationRole: string,
  assignmentRoles: RegistrationStaffRole[],
  operation: "manage" | "evaluate" | "camp",
): boolean {
  const role = organizationRole.trim().toLowerCase();
  if (role === "owner" || role === "admin") return true;
  if (operation === "manage") return assignmentRoles.includes("manager");
  if (operation === "evaluate") {
    return assignmentRoles.includes("manager") ||
      assignmentRoles.includes("evaluator");
  }
  return assignmentRoles.includes("manager") ||
    assignmentRoles.includes("camp_staff");
}

export function publicCheckInParticipant(value: Record<string, unknown>) {
  return {
    id: String(value.id ?? ""),
    display_name: String(value.display_name ?? "Registered player"),
    participant_number: Number(value.participant_number ?? 0) || null,
    age_group: String(value.age_group ?? "") || null,
    checked_in: value.checked_in === true,
  };
}
