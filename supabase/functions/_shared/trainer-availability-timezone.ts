export type TrainerAvailabilityTimezone = {
  weekday: number;
  starts_at: string;
  ends_at: string;
  timezone: string;
  effective_from: string | null;
  effective_until: string | null;
  location_id: string | null;
  is_override?: boolean;
};

function localScheduleParts(instant: Date, timezone: string) {
  const parts = new Intl.DateTimeFormat("en-US", {
    timeZone: timezone,
    weekday: "short",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
    hourCycle: "h23",
  }).formatToParts(instant);
  const value = (key: string) => parts.find((part) => part.type === key)?.value ?? "";
  const weekdays: Record<string, number> = {
    Sun: 0, Mon: 1, Tue: 2, Wed: 3, Thu: 4, Fri: 5, Sat: 6,
  };
  return {
    date: `${value("year")}-${value("month")}-${value("day")}`,
    weekday: weekdays[value("weekday")] ?? -1,
    time: `${value("hour")}:${value("minute")}:${value("second")}`,
  };
}

export function trainerTimezoneForSlot(
  rows: TrainerAvailabilityTimezone[],
  startsAt: Date,
  endsAt: Date,
  locationIds: string[],
): string | null {
  const candidates = rows.filter((row) =>
    (!row.location_id || !locationIds.length || locationIds.includes(row.location_id))
  ).map((row) => {
    const start = localScheduleParts(startsAt, row.timezone);
    const end = localScheduleParts(endsAt, row.timezone);
    return { row, start, end };
  }).filter(({ row, start, end }) =>
    start.weekday === Number(row.weekday) &&
    (!row.effective_from || row.effective_from <= start.date) &&
    (!row.effective_until || row.effective_until >= start.date) &&
    start.time >= row.starts_at && end.date === start.date && end.time <= row.ends_at
  );
  candidates.sort((a, b) =>
    Number(Boolean(b.row.is_override)) - Number(Boolean(a.row.is_override)) ||
    Number(Boolean(b.row.location_id)) - Number(Boolean(a.row.location_id)) ||
    a.row.timezone.localeCompare(b.row.timezone)
  );
  return candidates[0]?.row.timezone ?? null;
}
