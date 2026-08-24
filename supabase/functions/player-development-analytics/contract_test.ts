import {
  assert,
  assertEquals,
  assertFalse,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  canAccessPlayer,
  normalizedFilters,
  normalizedUuid,
  stableStringify,
  validModule,
} from "./contract.ts";
Deno.test("analytics modules remain discipline-specific", () => {
  assert(validModule("pitching", "velocity_extension"));
  assertFalse(validModule("pitching", "swing_decisions"));
  assert(validModule("hitting", "two_strikes"));
});

Deno.test("analytics identifiers and filters are normalized", () => {
  assertEquals(
    normalizedUuid(" 800E22AE-2A9D-4109-9E11-1360EEAA8EA7 "),
    "800e22ae-2a9d-4109-9e11-1360eeaa8ea7",
  );
  assertEquals(normalizedFilters({
    start_date: "2026-08-01",
    end_date: "bad",
    pitch_types: [" Fastball ", "", 7],
  }), { start_date: "2026-08-01", pitch_types: ["Fastball"] });
});

Deno.test("stable JSON is independent of object insertion order", () => {
  assertEquals(
    stableStringify({ filters: { end: 2, start: 1 }, module: "zone_maps" }),
    stableStringify({ module: "zone_maps", filters: { start: 1, end: 2 } }),
  );
});

Deno.test("analytics player scope denies unrelated roles and teams", () => {
  const actor = "10000000-0000-4000-8000-000000000001";
  const player = "20000000-0000-4000-8000-000000000002";
  assert(canAccessPlayer("owner", actor, player, new Set(), new Set(), new Set()));
  assert(canAccessPlayer("player", player, player, new Set(), new Set(), new Set()));
  assert(canAccessPlayer("parent", actor, player, new Set([player]), new Set(), new Set()));
  assert(canAccessPlayer("coach", actor, player, new Set(), new Set(["team-a"]), new Set(["team-a"])));
  assertFalse(canAccessPlayer("coach", actor, player, new Set(), new Set(["team-a"]), new Set(["team-b"])));
  assertFalse(canAccessPlayer("platform_admin", actor, player, new Set(), new Set(), new Set()));
});
