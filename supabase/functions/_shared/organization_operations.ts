export type Row = Record<string, unknown>;

export const seasonTransitions: Readonly<Record<string, readonly string[]>> = {
  planning: ["registration_open", "archived"],
  registration_open: ["roster_building", "planning"],
  roster_building: ["active", "registration_open"],
  active: ["playoffs", "completed"],
  playoffs: ["completed"],
  completed: ["archived"],
  archived: [],
};

export function mayTransitionSeason(from: string, to: string): boolean {
  return seasonTransitions[from]?.includes(to) ?? false;
}

export function registrationIsOpen(
  offering: Row,
  now = new Date(),
): boolean {
  if (offering.state !== "active") return false;
  const opens = new Date(String(offering.opens_at));
  const closes = new Date(String(offering.closes_at));
  return Number.isFinite(opens.getTime()) &&
    Number.isFinite(closes.getTime()) &&
    opens <= now && now <= closes;
}

export function registrationPlacement(
  capacity: number | null,
  approved: number,
  waitlistCapacity: number | null,
  waiting: number,
): "submitted" | "waitlisted" | "full" {
  if (capacity == null || approved < capacity) return "submitted";
  if (waitlistCapacity == null || waiting < waitlistCapacity) {
    return "waitlisted";
  }
  return "full";
}

export function invoiceNextStatus(
  current: string,
  action: string,
): string | null {
  if (action === "issue" && current === "draft") return "issued";
  if (["issued", "partially_paid", "overdue"].includes(current)) {
    if (action === "void") return "void";
    if (action === "cancel") return "cancelled";
    if (action === "write_off") return "written_off";
  }
  return null;
}

export function balanceStatus(
  total: number,
  paid: number,
  due: string | null,
  now = new Date(),
): string {
  if (paid >= total) return "paid";
  if (paid > 0) return "partially_paid";
  if (due && new Date(`${due}T23:59:59Z`) < now) return "overdue";
  return "issued";
}

export type Preference = {
  in_app_enabled?: boolean;
  push_enabled?: boolean;
  quiet_hours_start?: string | null;
  quiet_hours_end?: string | null;
};

function minutes(value: string): number {
  const [hour, minute] = value.split(":").map(Number);
  return hour * 60 + minute;
}

export function notificationDecision(
  preference: Preference | null,
  localHHMM: string,
  required: boolean,
): { inApp: boolean; push: boolean; reason: string } {
  const inApp = required || preference?.in_app_enabled !== false;
  let quiet = false;
  const start = preference?.quiet_hours_start;
  const end = preference?.quiet_hours_end;
  if (start && end) {
    const current = minutes(localHHMM);
    const from = minutes(start);
    const until = minutes(end);
    quiet = from < until
      ? current >= from && current < until
      : current >= from || current < until;
  }
  const push = preference?.push_enabled !== false && !quiet;
  return {
    inApp,
    push,
    reason: !inApp ? "preference" : quiet ? "quiet_hours" : "deliver",
  };
}

export function sanitizeRegistration(
  row: Row,
  role: string,
  callerId: string,
): Row {
  const isFinanceAdmin = role === "owner" || role === "admin";
  const isParty = [
    row.applicant_user_id,
    row.player_user_id,
    row.guardian_user_id,
  ].includes(callerId);
  const copy = { ...row };
  if (!isFinanceAdmin && !isParty) {
    delete copy.sensitive_answers;
    delete copy.consent_metadata;
    delete copy.reviewer_notes;
    delete copy.payment_responsible_user_id;
    delete copy.balance_cents;
    delete copy.fee_status;
  }
  return copy;
}

export function financialLayerIncluded(layer: unknown): boolean {
  return layer === "organization_customer" || layer === "organization_expense";
}

export function ratio(numerator: number, denominator: number): number | null {
  return denominator === 0
    ? null
    : Math.round((numerator / denominator) * 10_000) / 10_000;
}

export function csvCell(value: unknown): string {
  const raw = value == null
    ? ""
    : typeof value === "object"
    ? JSON.stringify(value)
    : String(value);
  return /[",\n\r]/.test(raw) ? `"${raw.replaceAll('"', '""')}"` : raw;
}

export function rowsToCSV(rows: Row[], allowedColumns: string[]): string {
  const header = allowedColumns.map(csvCell).join(",");
  return [
    header,
    ...rows.map((row) =>
      allowedColumns.map((key) => csvCell(row[key])).join(",")
    ),
  ].join("\r\n");
}
