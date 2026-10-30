import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { trainerTimezoneForSlot } from "./trainer-availability-timezone.ts";

Deno.test("daily trainer availability override timezone outranks recurring timezone", () => {
  const rows = [
    {
      weekday: 1, starts_at: "06:00:00", ends_at: "08:00:00",
      timezone: "America/New_York", effective_from: null, effective_until: null,
      location_id: "facility", is_override: false,
    },
    {
      weekday: 1, starts_at: "05:00:00", ends_at: "07:00:00",
      timezone: "America/Chicago", effective_from: "2026-10-19", effective_until: "2026-10-19",
      location_id: null, is_override: true,
    },
  ];
  assertEquals(
    trainerTimezoneForSlot(
      rows,
      new Date("2026-10-19T10:00:00Z"),
      new Date("2026-10-19T11:00:00Z"),
      ["facility"],
    ),
    "America/Chicago",
  );
});

Deno.test("trainer availability timezone is null when no stored schedule matches", () => {
  assertEquals(
    trainerTimezoneForSlot([], new Date("2026-10-19T10:00:00Z"), new Date("2026-10-19T11:00:00Z"), []),
    null,
  );
});
