import {
  buildDevelopmentDays,
  canUseOrganizationMembership,
  canUseStaffSections,
  completionStatus,
  normalizeWorkspaceUuid,
  scheduledDates,
  videoPlaybackStatus,
} from "./player_development_workspace.ts";

Deno.test("workspace UUID normalization makes Swift UUID casing safe", () => {
  assertEquals(
    normalizeWorkspaceUuid("800E22AE-2A9D-4109-9E11-1360EEAA8EA7"),
    "800e22ae-2a9d-4109-9e11-1360eeaa8ea7",
    "uppercase UUID normalized",
  );
  assertEquals(
    normalizeWorkspaceUuid("not-a-uuid"),
    null,
    "invalid UUID rejected",
  );
});

Deno.test("video playback compatibility handles legacy objects consistently", () => {
  assertEquals(
    videoPlaybackStatus("video/mp4", "ignored.mov"),
    "ready",
    "MP4 MIME accepted",
  );
  assertEquals(
    videoPlaybackStatus("video/quicktime", "clip.mp4"),
    "needs_conversion",
    "MOV MIME rejected",
  );
  assertEquals(
    videoPlaybackStatus(null, "sessions/clip.mp4"),
    "ready",
    "MP4 path accepted",
  );
  assertEquals(
    videoPlaybackStatus(null, "sessions/legacy.mov"),
    "needs_conversion",
    "legacy MOV path rejected",
  );
});

function assertEquals(actual: unknown, expected: unknown, message: string) {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(
      `${message}: expected ${JSON.stringify(expected)}, received ${
        JSON.stringify(actual)
      }`,
    );
  }
}

Deno.test("workspace membership fails closed and staff sections stay staff-only", () => {
  assertEquals(
    canUseOrganizationMembership(null),
    false,
    "missing membership denied",
  );
  assertEquals(
    canUseOrganizationMembership({ role: "owner", status: "disabled" }),
    false,
    "inactive owner denied",
  );
  assertEquals(
    canUseOrganizationMembership({ role: "player", status: "active" }),
    true,
    "active player allowed",
  );
  assertEquals(
    canUseStaffSections({ role: "player", status: "active" }),
    false,
    "player not staff",
  );
  assertEquals(
    canUseStaffSections({ role: "coach", status: "active" }),
    true,
    "coach staff",
  );
  for (const role of ["owner", "admin", "coach", "player", "parent"]) {
    assertEquals(
      canUseOrganizationMembership({ role, status: "active" }),
      true,
      `${role} active organization member`,
    );
  }
  for (const role of ["player", "parent", "platform_admin"]) {
    assertEquals(
      canUseStaffSections({ role, status: "active" }),
      false,
      `${role} denied staff sections`,
    );
  }
  for (const status of ["inactive", "invited", "disabled", "suspended"]) {
    assertEquals(
      canUseOrganizationMembership({ role: "admin", status }),
      false,
      `${status} membership denied`,
    );
  }
});

Deno.test("schedule uses canonical Monday through Sunday numbering", () => {
  assertEquals(
    scheduledDates({
      start_date: "2026-08-17",
      end_date: null,
      weeks: 2,
      lift_weekdays: [1, 3],
    }),
    ["2026-08-17", "2026-08-19", "2026-08-24", "2026-08-26"],
    "two-week schedule",
  );
});

Deno.test("video-only and provider-only days are submitted everywhere", () => {
  const days = buildDevelopmentDays(
    ["2026-08-20", "2026-08-22", "2026-08-25"],
    [{
      id: "provider-1",
      date: "2026-08-21",
      kind: "provider_import",
      source: "trackman",
      title: "TrackMan import",
      subtitle: null,
      details: {},
      warning: null,
    }],
    [{
      id: "video-1",
      date: "2026-08-22",
      kind: "session_video",
      title: "Bullpen video",
      file_name: "bullpen.mp4",
      mime_type: "video/mp4",
      source: "video",
      playback_status: "ready",
    }],
    "2026-08-23",
  );
  assertEquals(
    days.find((day) => day.date === "2026-08-20")?.status,
    "missed",
    "past empty scheduled day",
  );
  assertEquals(
    days.find((day) => day.date === "2026-08-21")?.status,
    "submitted",
    "provider activity submitted",
  );
  assertEquals(
    days.find((day) => day.date === "2026-08-22")?.status,
    "submitted",
    "video-only submitted",
  );
  assertEquals(
    days.find((day) => day.date === "2026-08-25")?.status,
    "upcoming",
    "future scheduled day",
  );
  assertEquals(
    completionStatus("2026-08-22", false, true, "2026-08-23"),
    "submitted",
    "unscheduled activity submitted",
  );
});
