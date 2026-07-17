import {
  type AlertCandidate,
  buildEvidencePack,
  calculateTrend,
  createPlayerDevelopmentAIHandler,
  detectDeterministicAlerts,
  DeterministicTemplateProvider,
  type DevelopmentAlert,
  type DevelopmentEvidenceSource,
  type DevelopmentMembership,
  type DevelopmentReportDetail,
  type DevelopmentReportRecord,
  evidencePackFingerprint,
  type MetricDefinition,
  type PlayerDevelopmentAIStore,
  safePercentageChange,
} from "./player_development_ai.ts";

function assert(condition: boolean, message = "assertion failed") {
  if (!condition) throw new Error(message);
}

function assertEqual<T>(actual: T, expected: T, message: string) {
  if (actual !== expected) {
    throw new Error(`${message}: expected ${expected}, received ${actual}`);
  }
}

const orgId = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const otherOrgId = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb";
const ownerId = "11111111-1111-4111-8111-111111111111";
const coachId = "22222222-2222-4222-8222-222222222222";
const parentId = "33333333-3333-4333-8333-333333333333";
const playerId = "44444444-4444-4444-8444-444444444444";
const otherPlayerId = "55555555-5555-4555-8555-555555555555";
const now = new Date("2026-07-15T12:00:00.000Z");

const definitions: MetricDefinition[] = [
  {
    id: "1",
    canonical_key: "hitting.max_exit_velocity",
    display_name: "Maximum Exit Velocity",
    category: "hitting",
    canonical_unit: "mph",
    preferred_direction: "higher_is_better",
    target_min: null,
    target_max: null,
    minimum_sample_size: 2,
  },
  {
    id: "2",
    canonical_key: "pitching.miss_distance",
    display_name: "Miss Distance",
    category: "pitching",
    canonical_unit: "in",
    preferred_direction: "lower_is_better",
    target_min: null,
    target_max: null,
    minimum_sample_size: 2,
  },
  {
    id: "3",
    canonical_key: "hitting.launch_angle",
    display_name: "Launch Angle",
    category: "hitting",
    canonical_unit: "deg",
    preferred_direction: "target_range",
    target_min: 10,
    target_max: 25,
    minimum_sample_size: 2,
  },
  {
    id: "4",
    canonical_key: "physical.body_weight",
    display_name: "Body Weight",
    category: "physical",
    canonical_unit: "lb",
    preferred_direction: "informational",
    target_min: null,
    target_max: null,
    minimum_sample_size: 2,
  },
];

function source(
  overrides: Partial<DevelopmentEvidenceSource> = {},
): DevelopmentEvidenceSource {
  return {
    player: { id: playerId, full_name: "Test Player" },
    testing_entries: [
      {
        id: "test-1",
        org_id: orgId,
        player_id: playerId,
        entry_date: "2026-05-01",
        height_in: null,
        weight_lb: 150,
        squat_1rm: null,
        bench_1rm: null,
        deadlift_1rm: null,
        max_exit_velo: 80,
        avg_exit_velo: null,
        hip_er_diff: null,
        hip_ir_diff: null,
        shoulder_ir_diff: null,
        shoulder_er_diff: null,
      },
      {
        id: "test-2",
        org_id: orgId,
        player_id: playerId,
        entry_date: "2026-07-01",
        height_in: null,
        weight_lb: 151,
        squat_1rm: null,
        bench_1rm: null,
        deadlift_1rm: null,
        max_exit_velo: 85,
        avg_exit_velo: null,
        hip_er_diff: null,
        hip_ir_diff: null,
        shoulder_ir_diff: null,
        shoulder_er_diff: null,
      },
    ],
    metric_observations: [],
    daily_logs: [{
      id: "daily-1",
      org_id: orgId,
      player_id: playerId,
      log_date: "2026-07-01",
      feel: 7,
      hit_daily_goals: true,
      stuck_to_process: true,
    }],
    program_assignments: [],
    bp_sessions: [],
    reports_awaiting_review: 0,
    ...overrides,
  };
}

function report(
  id = "66666666-6666-4666-8666-666666666666",
): DevelopmentReportRecord {
  return {
    id,
    org_id: orgId,
    player_id: playerId,
    team_id: null,
    report_type: "player_development_summary",
    requested_by: ownerId,
    intended_audience: "coach",
    audience: "staff",
    reporting_window_start: "2026-04-01",
    reporting_window_end: "2026-07-15",
    status: "draft",
    quality_status: "sufficient",
    structured_content: {
      overview: "Evidence-backed draft.",
      positive_trends: [],
      development_priorities: [],
      consistency_and_attendance: "One log.",
      data_gaps: [],
      coach_review_questions: [],
      evidence_summary: [],
    },
    rendered_text: "Evidence-backed draft.",
    generation_mode: "deterministic",
    provider: "deterministic_template",
    model_identifier: null,
    generator_version: "deterministic-template.v1",
    prompt_version: "none.deterministic.v1",
    input_cutoff: now.toISOString(),
    generated_at: now.toISOString(),
    reviewed_at: null,
    reviewed_by: null,
    approved_at: null,
    rejected_at: null,
    archived_at: null,
    coach_edits: {},
    review_notes: null,
    confidence: 0.85,
    data_freshness: "current",
    missing_data_warnings: [],
    evidence_fingerprint: "a".repeat(64),
    created_at: now.toISOString(),
    updated_at: now.toISOString(),
  };
}

class FakeStore implements PlayerDevelopmentAIStore {
  actorId: string | null = ownerId;
  featureEnabled = true;
  organizations = new Map([[orgId, "active"], [otherOrgId, "active"]]);
  memberships = new Map<string, DevelopmentMembership>([[
    `${orgId}:${ownerId}`,
    { role: "owner", status: "active" },
  ]]);
  allowed = new Set([playerId]);
  sourceData = source();
  reports = new Map<string, DevelopmentReportRecord>();
  keys = new Map<
    string,
    { material: string; report: DevelopmentReportRecord }
  >();
  alerts = new Map<string, DevelopmentAlert>();
  createCalls = 0;
  lastMutationActor: string | null = null;

  async authenticate(request: Request) {
    return request.headers.has("authorization") ? this.actorId : null;
  }
  async platformFeatureEnabled() {
    return this.featureEnabled;
  }
  async organizationStatus(id: string) {
    return this.organizations.get(id) ?? null;
  }
  async membership(org: string, actor: string) {
    return this.memberships.get(`${org}:${actor}`) ?? null;
  }
  async authorizedPlayerIds() {
    return new Set(this.allowed);
  }
  async metricDefinitions() {
    return definitions;
  }
  async evidenceSource(org: string, player: string) {
    if (org !== orgId || player !== playerId) {
      throw new Error("cross_org_evidence_rejected");
    }
    return structuredClone(this.sourceData);
  }
  async createReport(
    input: Parameters<PlayerDevelopmentAIStore["createReport"]>[0],
  ) {
    this.createCalls += 1;
    this.lastMutationActor = input.actorId;
    const material = JSON.stringify([
      input.orgId,
      input.playerId,
      input.reportType,
      input.audience,
      input.windowStart,
      input.windowEnd,
      input.cutoff,
    ]);
    const scopedKey =
      `${input.actorId}:${input.audience}:${input.idempotencyKey}`;
    const prior = this.keys.get(scopedKey);
    if (prior) {
      if (prior.material !== material) {
        throw new Error("development_report_idempotency_conflict");
      }
      return { report: prior.report, reused: true };
    }
    const created = report(
      `66666666-6666-4666-8666-${
        this.createCalls.toString().padStart(12, "0")
      }`,
    );
    created.requested_by = input.actorId;
    created.quality_status = input.qualityStatus;
    created.audience = input.audience;
    created.intended_audience = input.intendedAudience;
    created.structured_content = input.content;
    created.rendered_text = input.renderedText;
    created.missing_data_warnings = input.warnings;
    this.keys.set(scopedKey, { material, report: created });
    this.reports.set(created.id, created);
    return { report: created, reused: false };
  }
  async listReports(
    _org: string,
    players: string[],
    player?: string,
    audience: "staff" | "player" = "staff",
  ) {
    return [...this.reports.values()].filter((item) =>
      item.player_id && players.includes(item.player_id) &&
      (!player || item.player_id === player) && item.audience === audience
    );
  }
  async reportDetail(
    _org: string,
    id: string,
    players: string[],
    audience: "staff" | "player" = "staff",
  ): Promise<DevelopmentReportDetail | null> {
    const item = this.reports.get(id);
    return item?.player_id && players.includes(item.player_id) &&
        item.audience === audience
      ? { report: item, evidence: [], review_history: [] }
      : null;
  }
  async reviewReport(
    _actor: string,
    _org: string,
    id: string,
    action: string,
    notes: string | null,
    _edits: Record<string, unknown>,
    audience: "staff" | "player" = "staff",
  ) {
    const item = this.reports.get(id);
    if (!item || item.audience !== audience) {
      throw new Error("report_not_found");
    }
    if (audience === "player" && action !== "archive") {
      throw new Error("invalid_report_transition");
    }
    const transitions: Record<string, string> = {
      review: "reviewed",
      edit: "reviewed",
      approve: "approved",
      reject: "rejected",
      archive: "archived",
    };
    if (
      !transitions[action] ||
      ["failed", "rejected", "archived"].includes(item.status) ||
      (item.status === "approved" && action !== "archive")
    ) throw new Error("invalid_report_transition");
    item.status = transitions[action];
    item.review_notes = notes;
    return item;
  }
  async listAlerts(
    _org: string,
    players: string[],
    player?: string,
    audience: "staff" | "player" = "staff",
  ) {
    return [...this.alerts.values()].filter((item) =>
      players.includes(item.player_id) &&
      (!player || item.player_id === player) &&
      item.audience === audience
    );
  }
  async alertDetail(
    _org: string,
    id: string,
    players: string[],
    audience: "staff" | "player" = "staff",
  ) {
    const item = [...this.alerts.values()].find((alert) => alert.id === id);
    return item && players.includes(item.player_id) &&
        item.audience === audience
      ? { alert: item, evidence: [], review_history: [] }
      : null;
  }
  async persistAlerts(
    _actor: string,
    _org: string,
    candidates: AlertCandidate[],
    audience: "staff" | "player" = "staff",
  ) {
    return candidates.map((candidate, index) => {
      const key =
        `${candidate.player_id}:${audience}:${candidate.deduplication_key}`;
      const existing = this.alerts.get(key);
      if (existing) return existing;
      const saved: DevelopmentAlert = {
        ...candidate,
        id: `77777777-7777-4777-8777-${index.toString().padStart(12, "0")}`,
        first_detected_at: now.toISOString(),
        last_detected_at: now.toISOString(),
      };
      this.alerts.set(key, saved);
      return saved;
    });
  }
  async reviewAlert(
    _actor: string,
    _org: string,
    id: string,
    action: string,
    _notes: string | null,
    audience: "staff" | "player" = "staff",
  ) {
    const item = [...this.alerts.values()].find((alert) => alert.id === id);
    if (!item || item.audience !== audience) throw new Error("alert_not_found");
    if (audience === "player" && action !== "dismiss") {
      throw new Error("invalid_alert_transition");
    }
    const transitions: Record<string, DevelopmentAlert["status"]> = {
      acknowledge: "acknowledged",
      dismiss: "dismissed",
      resolve: "resolved",
      archive: "archived",
    };
    if (!transitions[action]) throw new Error("invalid_alert_transition");
    item.status = transitions[action];
    return item;
  }
}

function request(
  action: string,
  body: Record<string, unknown> = {},
  authorization = true,
) {
  return new Request("https://example.test/player-development-ai", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      ...(authorization ? { authorization: "Bearer test" } : {}),
    },
    body: JSON.stringify({ action, org_id: orgId, ...body }),
  });
}

const generationBody = {
  player_id: playerId,
  report_type: "player_development_summary",
  window_start: "2026-04-01",
  window_end: "2026-07-15",
  evidence_cutoff: now.toISOString(),
  idempotency_key: "88888888-8888-4888-8888-888888888888",
};

Deno.test("Phase 11A denies missing JWT, unrelated users, parents, players, and platform-only support", async () => {
  const store = new FakeStore();
  const handler = createPlayerDevelopmentAIHandler(store, () => now);
  assertEqual(
    (await handler(request("build_evidence_pack", generationBody, false)))
      .status,
    401,
    "missing JWT",
  );
  for (
    const [role, actor] of [["parent", parentId], ["player", playerId], [
      "platform_support",
      coachId,
    ]] as const
  ) {
    store.actorId = actor;
    if (role !== "platform_support") {
      store.memberships.set(`${orgId}:${actor}`, { role, status: "active" });
    }
    assertEqual(
      (await handler(request("build_evidence_pack", generationBody))).status,
      403,
      `${role} denied`,
    );
  }
});

Deno.test("disabled platform feature rejects Player Development AI without mutating official records", async () => {
  const store = new FakeStore();
  store.featureEnabled = false;
  const handler = createPlayerDevelopmentAIHandler(store, () => now);
  const response = await handler(request("generate_report", generationBody));
  const payload = await response.json();
  assertEqual(response.status, 503, "disabled status");
  assertEqual(payload.error, "feature_disabled", "stable disabled code");
  assertEqual(payload.retryable, false, "disabled response is not retryable");
  assertEqual(store.createCalls, 0, "no report or official-record mutation");
});

Deno.test("request size, calendar dates, reporting window, cutoff, and unknown actions fail closed", async () => {
  const handler = createPlayerDevelopmentAIHandler(new FakeStore(), () => now);
  const oversized = request("build_evidence_pack", {
    ...generationBody,
    padding: "x".repeat(66_000),
  });
  assertEqual((await handler(oversized)).status, 413, "body size bounded");
  assertEqual(
    (await handler(request("build_evidence_pack", {
      ...generationBody,
      window_start: "2026-02-30",
    }))).status,
    400,
    "invalid calendar date",
  );
  assertEqual(
    (await handler(request("build_evidence_pack", {
      ...generationBody,
      window_start: "2020-01-01",
    }))).status,
    400,
    "reporting window bounded",
  );
  assertEqual(
    (await handler(request("build_evidence_pack", {
      ...generationBody,
      evidence_cutoff: "2027-01-01T00:00:00.000Z",
    }))).status,
    400,
    "future cutoff denied",
  );
  assertEqual(
    (await handler(request("not_an_action", generationBody))).status,
    400,
    "unknown action denied",
  );
});

Deno.test("authorized owner and scoped coach can build evidence while cross-organization players are denied", async () => {
  const store = new FakeStore();
  const handler = createPlayerDevelopmentAIHandler(store, () => now);
  assertEqual(
    (await handler(request("build_evidence_pack", generationBody))).status,
    200,
    "owner evidence access",
  );
  store.actorId = coachId;
  store.memberships.set(`${orgId}:${coachId}`, {
    role: "coach",
    status: "active",
  });
  assertEqual(
    (await handler(request("build_evidence_pack", generationBody))).status,
    200,
    "coach evidence access",
  );
  assertEqual(
    (await handler(
      request("build_evidence_pack", {
        ...generationBody,
        player_id: otherPlayerId,
      }),
    )).status,
    403,
    "other player denied",
  );
  const otherOrgRequest = request("build_evidence_pack", {
    ...generationBody,
    org_id: otherOrgId,
  });
  assertEqual(
    (await handler(otherOrgRequest)).status,
    403,
    "other organization denied",
  );
});

Deno.test("evidence pack preserves organization/player integrity and explicit gaps without private notes", () => {
  const pack = buildEvidencePack({
    orgId,
    playerId,
    reportType: "parent_update_draft",
    windowStart: "2026-04-01",
    windowEnd: "2026-07-15",
    cutoff: now.toISOString(),
    definitions,
    source: source(),
  });
  assertEqual(pack.organization_id, orgId, "organization integrity");
  assertEqual(pack.player_id, playerId, "player integrity");
  assert(
    pack.missing_data_warnings.some((warning) =>
      warning.includes("attendance")
    ),
    "attendance gap explicit",
  );
  assert(
    pack.missing_data_warnings.some((warning) =>
      warning.includes("completion")
    ),
    "completion gap explicit",
  );
  assert(
    !JSON.stringify(pack).includes("private coach note"),
    "private notes excluded",
  );
  assert(
    pack.evidence.every((item) =>
      item.source_metadata.private_note === undefined
    ),
    "limited metadata only",
  );
});

Deno.test("trend engine handles preferred direction, target range, informational metrics, zero baselines, and low samples", () => {
  const points = (values: number[]) =>
    values.map((value, index) => ({
      value,
      date: `2026-07-0${index + 1}`,
      evidenceKey: `e${index}`,
      unit: "unit",
    }));
  assertEqual(
    calculateTrend(definitions[0], points([80, 85]), now.toISOString())
      ?.interpretation,
    "improvement",
    "higher is better",
  );
  assertEqual(
    calculateTrend(definitions[1], points([8, 6]), now.toISOString())
      ?.interpretation,
    "improvement",
    "lower is better",
  );
  assertEqual(
    calculateTrend(definitions[2], points([8, 15]), now.toISOString())
      ?.interpretation,
    "improvement",
    "target range",
  );
  assertEqual(
    calculateTrend(definitions[2], points([15, 20]), now.toISOString())
      ?.interpretation,
    "stable",
    "movement inside target range is stable",
  );
  assertEqual(
    calculateTrend(definitions[2], points([15, 30]), now.toISOString())
      ?.interpretation,
    "regression",
    "movement away from target range",
  );
  assertEqual(
    calculateTrend(definitions[3], points([150, 151]), now.toISOString())
      ?.interpretation,
    "informational",
    "informational",
  );
  assertEqual(
    calculateTrend(
      { ...definitions[3], preferred_direction: "context_dependent" },
      points([150, 151]),
      now.toISOString(),
    )?.interpretation,
    "informational",
    "context dependent",
  );
  assertEqual(safePercentageChange(0, 10), null, "zero percentage baseline");
  assertEqual(
    safePercentageChange(0.0000001, 10),
    null,
    "near-zero percentage baseline",
  );
  assertEqual(
    calculateTrend(definitions[0], points([80]), now.toISOString())?.quality,
    "limited",
    "low sample quality",
  );
  assertEqual(
    calculateTrend(
      definitions[0],
      points([80, 85]).map((point) => ({ ...point, date: "2026-07-01" })),
      now.toISOString(),
    )?.latest_value,
    85,
    "equal timestamps retain deterministic input order",
  );
  assertEqual(
    calculateTrend(definitions[0], points([80, 81, 500]), now.toISOString())
      ?.latest_value,
    500,
    "extreme observations remain explicit rather than silently removed",
  );
  assertEqual(
    calculateTrend(
      definitions[0],
      [
        ...points([80]),
        { ...points([85])[0]!, date: "2026-07-02", unit: "m/s" },
      ],
      now.toISOString(),
    )?.absolute_change,
    null,
    "unit conflict blocks comparison",
  );
});

Deno.test("evidence pack reports stale data, unit conflicts, and low samples", () => {
  const stale = buildEvidencePack({
    orgId,
    playerId,
    reportType: "player_development_summary",
    windowStart: "2025-01-01",
    windowEnd: "2026-07-15",
    cutoff: now.toISOString(),
    definitions,
    source: source({
      testing_entries: [{
        ...source().testing_entries[0]!,
        entry_date: "2025-01-01",
      }],
    }),
  });
  assertEqual(stale.quality_status, "stale", "stale quality");
  const conflicting = buildEvidencePack({
    orgId,
    playerId,
    reportType: "player_development_summary",
    windowStart: "2026-01-01",
    windowEnd: "2026-07-15",
    cutoff: now.toISOString(),
    definitions,
    source: source({
      metric_observations: [
        {
          id: "o1",
          org_id: orgId,
          player_id: playerId,
          canonical_key: "hitting.max_exit_velocity",
          normalized_value: 84,
          observed_value: "84",
          unit: "m/s",
          observed_at: "2026-07-10T00:00:00Z",
          source_system: "import",
          source_entity_type: "sd_player_metric_observations",
          source_record_id: "o1",
          quality_status: "sufficient",
          sample_size: 1,
        },
      ],
    }),
  });
  assertEqual(conflicting.quality_status, "conflicting", "conflicting quality");
  assert(conflicting.unit_conflicts.length > 0, "unit warning");
  const conflictingTrend = conflicting.trends.find((trend) =>
    trend.canonical_metric_key === "hitting.max_exit_velocity"
  );
  assertEqual(
    conflictingTrend?.interpretation,
    "insufficient",
    "conflicting units cannot become performance direction",
  );
  assertEqual(
    conflictingTrend?.rolling_average,
    null,
    "conflicting units cannot become a combined average",
  );
  const low = buildEvidencePack({
    orgId,
    playerId,
    reportType: "player_development_summary",
    windowStart: "2026-01-01",
    windowEnd: "2026-07-15",
    cutoff: now.toISOString(),
    definitions,
    source: source({ testing_entries: [source().testing_entries[0]!] }),
  });
  assert(low.low_sample_warnings.length > 0, "low sample warning");
});

Deno.test("missing normalized and nonnumeric raw observations are not guessed", () => {
  const pack = buildEvidencePack({
    orgId,
    playerId,
    reportType: "player_development_summary",
    windowStart: "2026-07-01",
    windowEnd: "2026-07-15",
    cutoff: now.toISOString(),
    definitions,
    source: source({
      testing_entries: [],
      daily_logs: [],
      bp_sessions: [],
      metric_observations: [{
        id: "invalid-observation",
        org_id: orgId,
        player_id: playerId,
        canonical_key: "hitting.max_exit_velocity",
        normalized_value: null,
        observed_value: "not-a-number",
        unit: "mph",
        observed_at: "2026-07-10T00:00:00Z",
        source_system: "future_import",
        source_entity_type: "sd_player_metric_observations",
        source_record_id: "invalid-observation",
        quality_status: "limited",
        sample_size: 1,
      }],
    }),
  });
  assert(
    !pack.evidence.some((item) =>
      item.source_record_id === "invalid-observation"
    ),
    "raw text is never silently converted",
  );
});

Deno.test("deterministic provider is useful with evidence, explicit without it, and never fabricates or stores hidden reasoning", async () => {
  const provider = new DeterministicTemplateProvider();
  const pack = buildEvidencePack({
    orgId,
    playerId,
    reportType: "player_development_summary",
    windowStart: "2026-04-01",
    windowEnd: "2026-07-15",
    cutoff: now.toISOString(),
    definitions,
    source: source(),
  });
  const content = await provider.generate(pack);
  const serialized = JSON.stringify(content);
  assert(serialized.includes("Maximum Exit Velocity"), "uses supported metric");
  assert(!serialized.includes("spin rate"), "does not fabricate absent metric");
  assert(
    !serialized.includes("chain_of_thought") &&
      !serialized.includes("reasoning_trace"),
    "no hidden reasoning storage",
  );
  const empty = buildEvidencePack({
    orgId,
    playerId,
    reportType: "player_development_summary",
    windowStart: "2026-04-01",
    windowEnd: "2026-07-15",
    cutoff: now.toISOString(),
    definitions,
    source: source({
      testing_entries: [],
      metric_observations: [],
      daily_logs: [],
      bp_sessions: [],
    }),
  });
  assert(
    (await provider.generate(empty)).overview.includes("not enough"),
    "insufficient evidence explicit",
  );
  assertEqual(
    provider.provider,
    "deterministic_template",
    "no external provider secret needed",
  );
});

Deno.test("deterministic output fixtures remain evidence-bound across coverage and quality states", async () => {
  const provider = new DeterministicTemplateProvider();
  const build = (sourceData: DevelopmentEvidenceSource) =>
    buildEvidencePack({
      orgId,
      playerId,
      reportType: "player_development_summary",
      windowStart: "2025-01-01",
      windowEnd: "2026-07-15",
      cutoff: now.toISOString(),
      definitions,
      source: sourceData,
    });
  const strong = await provider.generate(build(source()));
  assert(strong.positive_trends.length > 0, "strong supported trend");

  const limited = await provider.generate(build(source({
    testing_entries: [source().testing_entries[0]!],
  })));
  assert(
    limited.data_gaps.some((item) => item.includes("fewer")),
    "limited sample disclosed",
  );

  const stale = await provider.generate(build(source({
    testing_entries: source().testing_entries.map((item) => ({
      ...item,
      entry_date: "2025-01-01",
    })),
  })));
  assert(
    stale.data_gaps.some((item) => item.includes("90 days")),
    "stale evidence disclosed",
  );

  const conflicting = await provider.generate(build(source({
    metric_observations: [{
      id: "conflicting",
      org_id: orgId,
      player_id: playerId,
      canonical_key: "hitting.max_exit_velocity",
      normalized_value: 40,
      observed_value: "40",
      unit: "m/s",
      observed_at: "2026-07-10T00:00:00Z",
      source_system: "future_import",
      source_entity_type: "sd_player_metric_observations",
      source_record_id: "conflicting",
      quality_status: "conflicting",
      sample_size: 1,
    }],
  })));
  assert(
    conflicting.data_gaps.some((item) => item.includes("conflicting units")),
    "unit conflict disclosed",
  );

  const noTesting = await provider.generate(build(source({
    testing_entries: [],
  })));
  assert(
    noTesting.data_gaps.some((item) => item.includes("No testing")),
    "missing testing disclosed",
  );

  const regression = await provider.generate(build(source({
    testing_entries: source().testing_entries.map((item, index) => ({
      ...item,
      max_exit_velo: index === 0 ? 85 : 80,
    })),
  })));
  assert(
    regression.development_priorities.length > 0,
    "regression is review-only",
  );

  const onlyAssignment = await provider.generate(build(source({
    testing_entries: [],
    metric_observations: [],
    daily_logs: [],
    bp_sessions: [],
    program_assignments: [{
      id: "assignment-1",
      org_id: orgId,
      player_id: playerId,
      template_id: "template-1",
      start_date: "2026-07-01",
      ended_at: null,
      notes: "home_plate_demo_seed | phase_11a.v1 | synthetic_unverified",
    }],
  })));
  assert(
    onlyAssignment.evidence_summary.some((item) =>
      item.evidence_key.startsWith("sd_program_assignments:assignment-1:") &&
      item.explanation.includes("does not prove attendance or completion")
    ),
    "assignment is cited only as program context",
  );

  const empty = await provider.generate(build(source({
    testing_entries: [],
    metric_observations: [],
    daily_logs: [],
    bp_sessions: [],
    program_assignments: [],
  })));
  const serialized = JSON.stringify([
    strong,
    limited,
    stale,
    conflicting,
    noTesting,
    regression,
    onlyAssignment,
    empty,
  ]).toLowerCase();
  for (
    const unsupported of [
      "diagnosis",
      "guaranteed improvement",
      "professional player",
      "coach said",
      "completed the program",
      "attended every",
    ]
  ) {
    assert(
      !serialized.includes(unsupported),
      `unsupported output excluded: ${unsupported}`,
    );
  }
});

Deno.test("empty evidence follows the full generate path and persists an honest draft", async () => {
  const store = new FakeStore();
  store.sourceData = source({
    testing_entries: [],
    metric_observations: [],
    daily_logs: [],
    program_assignments: [],
    bp_sessions: [],
  });
  const stages: string[] = [];
  const handler = createPlayerDevelopmentAIHandler(
    store,
    () => now,
    (event) => stages.push(event),
  );
  const response = await handler(request("generate_report", generationBody));
  assertEqual(response.status, 200, "empty evidence generation succeeds");
  const body = await response.json();
  assertEqual(store.createCalls, 1, "draft persistence invoked once");
  assertEqual(body.report.quality_status, "unavailable", "SQL-safe quality");
  assertEqual(body.report.status, "draft", "SQL-safe lifecycle status");
  assert(
    body.report.structured_content.overview.includes("not enough"),
    "insufficient evidence is explicit",
  );
  assertEqual(body.evidence_pack.evidence.length, 0, "no evidence fabricated");
  assertEqual(body.evidence_pack.trends.length, 0, "no trends fabricated");
  for (
    const expected of [
      "generate_request_received",
      "actor_verified",
      "organization_authorized",
      "player_authorized",
      "evidence_pack_built",
      "deterministic_report_built",
      "report_rpc_started",
      "report_rpc_succeeded",
    ]
  ) {
    assert(stages.includes(expected), `missing stage ${expected}`);
  }
});

Deno.test("report generation is idempotent and concurrent retries converge", async () => {
  const store = new FakeStore();
  const handler = createPlayerDevelopmentAIHandler(store, () => now);
  const [first, second] = await Promise.all([
    handler(request("generate_report", {
      ...generationBody,
      actor_id: otherPlayerId,
      requested_by: otherPlayerId,
    })),
    handler(request("generate_report", generationBody)),
  ]);
  assertEqual(first.status, 200, "first generation");
  assertEqual(second.status, 200, "concurrent retry");
  assertEqual(store.lastMutationActor, ownerId, "verified actor transferred");
  assertEqual(store.reports.size, 1, "one report persisted");
  const secondBody = await second.json();
  assertEqual(secondBody.reused, true, "second reused");
  const conflict = await handler(
    request("generate_report", {
      ...generationBody,
      window_start: "2026-05-01",
    }),
  );
  assertEqual(conflict.status, 409, "changed material fails closed");
});

Deno.test("player report generation is self-only, player-safe, idempotent, and creates separate player alerts", async () => {
  const store = new FakeStore();
  store.actorId = playerId;
  store.memberships.set(`${orgId}:${playerId}`, {
    role: "player",
    status: "active",
  });
  const handler = createPlayerDevelopmentAIHandler(store, () => now);
  const body = {
    ...generationBody,
    intended_audience: "staff",
    audience: "staff",
  };
  const first = await handler(request("generate_player_report", body));
  assertEqual(first.status, 200, "player self generation succeeds");
  const firstBody = await first.json();
  assertEqual(firstBody.report.player_id, playerId, "forced self player");
  assertEqual(
    firstBody.report.requested_by,
    playerId,
    "verified actor persisted",
  );
  assertEqual(
    firstBody.report.audience,
    "player",
    "audience derived server-side",
  );
  assertEqual(
    firstBody.report.intended_audience,
    "player",
    "player prompt audience",
  );
  assert(
    firstBody.report.structured_content.coach_review_questions.every(
      (question: string) => !/approve|reject|staff review/i.test(question),
    ),
    "player follow-ups expose no staff review workflow",
  );
  assert(
    firstBody.player_alerts.every((alert: DevelopmentAlert) =>
      alert.audience === "player" &&
      alert.alert_type !== "report_awaiting_review"
    ),
    "player alerts are independently player-scoped",
  );
  const retry = await handler(request("generate_player_report", body));
  assertEqual(retry.status, 200, "safe retry succeeds");
  assertEqual((await retry.json()).reused, true, "safe retry reuses report");
  assertEqual(store.createCalls, 2, "both requests reach idempotent store");
  assertEqual(
    (await handler(request("generate_report", body))).status,
    403,
    "player cannot call staff generation",
  );
  assertEqual(
    (await handler(request("generate_player_report", {
      ...body,
      player_id: otherPlayerId,
    }))).status,
    403,
    "player cannot target another player",
  );
});

Deno.test("report and alert reads enforce exact actor-derived audience in both directions", async () => {
  const store = new FakeStore();
  const staffReport = report("66666666-6666-4666-8666-000000000001");
  const playerReport = report("66666666-6666-4666-8666-000000000002");
  playerReport.audience = "player";
  playerReport.intended_audience = "player";
  playerReport.requested_by = playerId;
  store.reports.set(staffReport.id, staffReport);
  store.reports.set(playerReport.id, playerReport);
  const staffAlert: DevelopmentAlert = {
    ...detectDeterministicAlerts(
      buildEvidencePack({
        orgId,
        playerId,
        reportType: "player_development_summary",
        windowStart: "2026-04-01",
        windowEnd: "2026-07-15",
        cutoff: now.toISOString(),
        definitions,
        source: source(),
      }),
      1,
      "staff",
    )[0],
    id: "77777777-7777-4777-8777-000000000001",
    first_detected_at: now.toISOString(),
    last_detected_at: now.toISOString(),
  };
  const playerAlert: DevelopmentAlert = {
    ...staffAlert,
    id: "77777777-7777-4777-8777-000000000002",
    audience: "player",
    alert_type: "stale_testing",
    explanation: "You may benefit from updated testing.",
    deduplication_key: "player:stale_testing",
  };
  store.alerts.set("staff", staffAlert);
  store.alerts.set("player", playerAlert);
  const handler = createPlayerDevelopmentAIHandler(store, () => now);

  store.actorId = playerId;
  store.memberships.set(`${orgId}:${playerId}`, {
    role: "player",
    status: "active",
  });
  let response = await handler(request("list_player_reports"));
  assertEqual(response.status, 200, "player report list succeeds");
  let body = await response.json();
  assertEqual(body.reports.length, 1, "one player report");
  assertEqual(body.reports[0].id, playerReport.id, "staff report excluded");
  assertEqual(
    (await handler(request("get_player_report", { report_id: staffReport.id })))
      .status,
    404,
    "player cannot read staff report",
  );
  response = await handler(request("list_player_alerts"));
  body = await response.json();
  assertEqual(body.alerts.length, 1, "one player alert");
  assertEqual(body.alerts[0].id, playerAlert.id, "staff alert excluded");
  assertEqual(
    (await handler(request("get_player_alert", { alert_id: staffAlert.id })))
      .status,
    404,
    "player cannot read staff alert",
  );

  store.actorId = ownerId;
  response = await handler(request("list_player_reports", {
    player_id: playerId,
  }));
  body = await response.json();
  assertEqual(body.reports.length, 1, "staff list remains staff audience");
  assertEqual(
    body.reports[0].id,
    staffReport.id,
    "player-private report excluded",
  );
  assertEqual(
    (await handler(
      request("get_player_report", { report_id: playerReport.id }),
    ))
      .status,
    403,
    "staff cannot use private player detail action",
  );
  response = await handler(request("list_player_alerts", {
    player_id: playerId,
  }));
  body = await response.json();
  assertEqual(
    body.alerts[0].id,
    staffAlert.id,
    "player-private alert excluded",
  );
});

Deno.test("player alert rules are objective, nonjudgmental, and exclude staff workflow alerts", () => {
  const evidencePack = buildEvidencePack({
    orgId,
    playerId,
    reportType: "player_development_summary",
    windowStart: "2026-04-01",
    windowEnd: "2026-07-15",
    cutoff: now.toISOString(),
    definitions,
    source: source(),
  });
  const alerts = detectDeterministicAlerts(evidencePack, 99, "player");
  const allowed = new Set([
    "no_recent_testing",
    "stale_testing",
    "meaningful_metric_improvement",
    "meaningful_metric_regression",
    "inconsistent_units",
    "insufficient_sample_size",
  ]);
  assert(alerts.every((alert) => alert.audience === "player"));
  assert(alerts.every((alert) => allowed.has(alert.alert_type)));
  assert(
    !alerts.some((alert) => alert.alert_type === "report_awaiting_review"),
  );
  assert(
    alerts.every((alert) =>
      !/(failure|bad player|risk flag|roster|compared to|staff review)/i.test(
        `${alert.explanation} ${alert.recommended_human_action}`,
      )
    ),
    "wording is nonjudgmental and contains no staff workflow language",
  );
});

Deno.test("report lifecycle supports review/approval/archive and retains evidence while invalid transitions fail", async () => {
  const store = new FakeStore();
  const item = report();
  store.reports.set(item.id, item);
  const handler = createPlayerDevelopmentAIHandler(store, () => now);
  assertEqual(
    (await handler(
      request("review_report", {
        report_id: item.id,
        review_action: "review",
        review_notes: "Checked",
      }),
    )).status,
    200,
    "review",
  );
  assertEqual(
    (await handler(
      request("review_report", {
        report_id: item.id,
        review_action: "approve",
      }),
    )).status,
    200,
    "approve",
  );
  assertEqual(
    (await handler(
      request("review_report", {
        report_id: item.id,
        review_action: "archive",
      }),
    )).status,
    200,
    "archive",
  );
  assert(store.reports.has(item.id), "archived report retained");
  assertEqual(
    (await handler(
      request("review_report", {
        report_id: item.id,
        review_action: "approve",
      }),
    )).status,
    409,
    "invalid transition rejected",
  );
});

Deno.test("deterministic alerts deduplicate improvements, regressions, stale testing, and awaiting review", async () => {
  const store = new FakeStore();
  const improving = buildEvidencePack({
    orgId,
    playerId,
    reportType: "development_alert_review",
    windowStart: "2026-01-01",
    windowEnd: "2026-07-15",
    cutoff: now.toISOString(),
    definitions,
    source: source(),
  });
  const first = await store.persistAlerts(
    ownerId,
    orgId,
    detectDeterministicAlerts(improving, 1),
  );
  const second = await store.persistAlerts(
    ownerId,
    orgId,
    detectDeterministicAlerts(improving, 1),
  );
  assertEqual(first.length, second.length, "same candidates");
  assertEqual(
    store.alerts.size,
    first.length,
    "improvement and review deduplicated",
  );
  const regressionSource = source({
    testing_entries: source().testing_entries.map((item, index) => ({
      ...item,
      max_exit_velo: index === 0 ? 85 : 80,
    })),
  });
  const regressing = buildEvidencePack({
    orgId,
    playerId,
    reportType: "development_alert_review",
    windowStart: "2026-01-01",
    windowEnd: "2026-07-15",
    cutoff: now.toISOString(),
    definitions,
    source: regressionSource,
  });
  const regressionAlerts = detectDeterministicAlerts(regressing, 0);
  assert(
    regressionAlerts.some((alert) =>
      alert.alert_type === "meaningful_metric_regression"
    ),
    "regression alert",
  );
  const stalePack = buildEvidencePack({
    orgId,
    playerId,
    reportType: "development_alert_review",
    windowStart: "2025-01-01",
    windowEnd: "2026-07-15",
    cutoff: now.toISOString(),
    definitions,
    source: source({
      testing_entries: source().testing_entries.map((item) => ({
        ...item,
        entry_date: "2025-01-01",
      })),
    }),
  });
  assertEqual(
    detectDeterministicAlerts(stalePack, 0).filter((alert) =>
      alert.alert_type === "stale_testing"
    ).length,
    1,
    "stale testing deduplicated candidate",
  );
});

Deno.test("alert list and lifecycle are staff scoped and support acknowledge, dismiss, and resolve", async () => {
  for (const action of ["acknowledge", "dismiss", "resolve"] as const) {
    const store = new FakeStore();
    const candidate = detectDeterministicAlerts(
      buildEvidencePack({
        orgId,
        playerId,
        reportType: "development_alert_review",
        windowStart: "2026-01-01",
        windowEnd: "2026-07-15",
        cutoff: now.toISOString(),
        definitions,
        source: source({ testing_entries: [] }),
      }),
      0,
    )[0]!;
    const saved = (await store.persistAlerts(ownerId, orgId, [candidate]))[0]!;
    const response = await createPlayerDevelopmentAIHandler(store, () => now)(
      request("review_alert", { alert_id: saved.id, review_action: action }),
    );
    assertEqual(response.status, 200, action);
    assertEqual(
      saved.status,
      action === "acknowledge"
        ? "acknowledged"
        : action === "dismiss"
        ? "dismissed"
        : "resolved",
      `${action} status`,
    );
  }
});

Deno.test("alert detail returns only scoped evidence and history", async () => {
  const store = new FakeStore();
  const candidate = detectDeterministicAlerts(
    buildEvidencePack({
      orgId,
      playerId,
      reportType: "development_alert_review",
      windowStart: "2026-01-01",
      windowEnd: "2026-07-15",
      cutoff: now.toISOString(),
      definitions,
      source: source(),
    }),
    0,
  )[0]!;
  const saved = (await store.persistAlerts(ownerId, orgId, [candidate]))[0]!;
  const handler = createPlayerDevelopmentAIHandler(store, () => now);
  assertEqual(
    (await handler(request("get_alert", { alert_id: saved.id }))).status,
    200,
    "authorized alert detail",
  );
  store.allowed.clear();
  assertEqual(
    (await handler(request("get_alert", { alert_id: saved.id }))).status,
    404,
    "unscoped alert hidden",
  );
});

Deno.test("roster attention is staff-only and cannot leak another player's reports or evidence", async () => {
  const store = new FakeStore();
  store.reports.set(report().id, report());
  store.reports.set("99999999-9999-4999-8999-999999999999", {
    ...report("99999999-9999-4999-8999-999999999999"),
    player_id: otherPlayerId,
  });
  const handler = createPlayerDevelopmentAIHandler(store, () => now);
  const response = await handler(request("roster_attention"));
  const body = await response.json();
  assertEqual(response.status, 200, "staff roster attention");
  assertEqual(
    body.reports_awaiting_review.length,
    1,
    "only authorized player report",
  );
  store.actorId = parentId;
  store.memberships.set(`${orgId}:${parentId}`, {
    role: "parent",
    status: "active",
  });
  assertEqual(
    (await handler(request("roster_attention"))).status,
    403,
    "parent denied",
  );
});

Deno.test("historical evidence snapshots remain stable after source records change", () => {
  const mutableSource = source();
  const pack = buildEvidencePack({
    orgId,
    playerId,
    reportType: "player_development_summary",
    windowStart: "2026-04-01",
    windowEnd: "2026-07-15",
    cutoff: now.toISOString(),
    definitions,
    source: mutableSource,
  });
  const snapshot = structuredClone(pack.evidence);
  mutableSource.testing_entries[1]!.max_exit_velo = 99;
  assertEqual(
    snapshot.find((item) =>
      item.source_record_id === "test-2" &&
      item.canonical_metric_key === "hitting.max_exit_velocity"
    )
      ?.normalized_numeric_value,
    85,
    "persistable snapshot is not a live source reference",
  );
  const trendSnapshot = snapshot.find((item) =>
    item.source_record_id === "test-2" &&
    item.canonical_metric_key === "hitting.max_exit_velocity"
  );
  assertEqual(trendSnapshot?.comparison_value, 80, "comparison persisted");
  assertEqual(
    trendSnapshot?.deterministic_rule_id,
    "trend.higher_is_better.v1",
    "trend rule persisted",
  );
  assertEqual(trendSnapshot?.sample_size, 2, "sample count persisted");
});

Deno.test("evidence-pack fingerprint is stable and changes with evidence", async () => {
  const original = buildEvidencePack({
    orgId,
    playerId,
    reportType: "player_development_summary",
    windowStart: "2026-04-01",
    windowEnd: "2026-07-15",
    cutoff: now.toISOString(),
    definitions,
    source: source(),
  });
  const changed = structuredClone(original);
  changed.evidence[0]!.normalized_numeric_value = 999;
  const first = await evidencePackFingerprint(original);
  assertEqual(first.length, 64, "sha-256 hex length");
  assertEqual(
    first,
    await evidencePackFingerprint(structuredClone(original)),
    "same pack fingerprint",
  );
  assert(
    first !== await evidencePackFingerprint(changed),
    "changed evidence changes fingerprint",
  );
});

Deno.test("Phase 11A migration is additive, staff-only, scoped, audited, idempotent, and hardened", async () => {
  const sql = (await Deno.readTextFile(
    new URL(
      "../../migrations/20260715060000_player_development_ai_foundation.sql",
      import.meta.url,
    ),
  )).toLowerCase();
  for (
    const table of [
      "sd_development_metric_definitions",
      "sd_development_import_jobs",
      "sd_player_metric_observations",
      "sd_development_reports",
      "sd_development_report_evidence",
      "sd_development_report_review_events",
      "sd_development_alerts",
      "sd_development_alert_evidence",
      "sd_development_alert_events",
    ]
  ) {
    assert(
      sql.includes(`create table if not exists public.${table}`),
      `${table} exists`,
    );
    assert(
      sql.includes(`alter table public.${table} enable row level security`),
      `${table} RLS`,
    );
  }
  for (
    const rpc of [
      "sd_create_development_report",
      "sd_review_development_report",
      "sd_upsert_development_alerts",
      "sd_review_development_alert",
    ]
  ) {
    const start = sql.indexOf(`create or replace function public.${rpc}`);
    assert(start >= 0, `${rpc} exists`);
    const body = sql.slice(start, sql.indexOf("$$;", start) + 3);
    assert(body.includes("security definer"), `${rpc} definer`);
    assert(body.includes("set search_path = ''"), `${rpc} safe search path`);
    assert(body.includes("p_actor_id"), `${rpc} receives verified actor`);
    assert(
      body.includes("sd_development_actor_can_manage_player"),
      `${rpc} repeats player authorization`,
    );
    assert(
      sql.includes(`revoke all on function public.${rpc}`),
      `${rpc} revoked`,
    );
    assert(
      sql.includes(`grant execute on function public.${rpc}`),
      `${rpc} minimum grant`,
    );
  }
  const lifecycleGrants = sql.slice(
    sql.indexOf("revoke all on function public.sd_create_development_report"),
    sql.indexOf("revoke all on table public.sd_development_metric_definitions"),
  );
  assert(
    lifecycleGrants.includes("to service_role;") &&
      !lifecycleGrants.includes("to authenticated;"),
    "lifecycle RPCs are service-role-only",
  );
  assert(sql.includes("unique (org_id, requested_by, idempotency_key)"));
  assert(sql.includes("pg_catalog.pg_advisory_xact_lock"));
  assert(sql.includes("p_window_end - p_window_start > 730"));
  assert(sql.includes("evidence_fingerprint text not null"));
  assert(
    sql.includes(
      "jsonb_array_length(coalesce(p_evidence, '[]'::jsonb)) > 5000",
    ),
  );
  assert(sql.includes("unique (org_id, player_id, deduplication_key)"));
  assert(sql.includes("development_report_evidence_scope_mismatch"));
  assert(sql.includes("development_alert_evidence_scope_mismatch"));
  for (
    const relationship of [
      "sd_player_metric_observation_import_job_fk",
      "sd_player_metric_observation_correction_fk",
      "sd_development_report_evidence_report_fk",
      "sd_development_report_review_event_report_fk",
      "sd_development_alert_report_fk",
      "sd_development_alert_evidence_alert_fk",
      "sd_development_alert_event_alert_fk",
    ]
  ) {
    assert(sql.includes(relationship), `${relationship} enforced`);
  }
  assert(
    sql.includes("before insert or update of org_id, player_id"),
    "player scope cannot be changed after insert",
  );
  assert(
    sql.includes("development_observation_import_scope_mismatch"),
    "import player scope enforced",
  );
  assert(
    sql.includes("development_report_team_scope_mismatch"),
    "report team scope enforced",
  );
  assert(
    sql.includes(
      "revoke all on table public.sd_development_metric_definitions",
    ),
    "direct table privileges explicitly revoked",
  );
  assert(sql.includes("team.is_active = true"), "inactive teams denied");
  assert(!sql.includes("from public.sd_platform_admins"));
  assert(!sql.includes("delete from public.sd_development"));
  assert(!sql.includes("for insert to authenticated"));
  assert(!sql.includes("for update to authenticated"));
  assert(!sql.includes("for delete to authenticated"));
});

Deno.test("unapplied Phase 11C migration makes reports and alerts audience-exact without exposing historical staff rows", async () => {
  const sql = (await Deno.readTextFile(
    new URL(
      "../../migrations/20260715100000_player_development_copilot.sql",
      import.meta.url,
    ),
  )).toLowerCase();
  for (const table of ["sd_development_reports", "sd_development_alerts"]) {
    assert(
      sql.includes(
        `alter table public.${table}\n  add column if not exists audience text not null default 'staff'`,
      ),
      `${table} historical default`,
    );
  }
  assert(sql.includes("check (audience in ('staff','player','parent'))"));
  assert(sql.includes("check (audience in ('staff','player'))"));
  assert(
    sql.includes(
      "unique (org_id,requested_by,audience,idempotency_key)",
    ),
    "report idempotency includes audience",
  );
  assert(
    sql.includes(
      "unique (org_id,player_id,audience,deduplication_key)",
    ),
    "alert deduplication includes audience",
  );
  assert(
    sql.includes(
      "foreign key (report_id,org_id,player_id,audience)\n  references public.sd_development_reports(id,org_id,player_id,audience)",
    ),
    "report evidence exact parent boundary",
  );
  assert(
    sql.includes(
      "foreign key (alert_id,org_id,player_id,audience)\n  references public.sd_development_alerts(id,org_id,player_id,audience)",
    ),
    "alert evidence exact parent boundary",
  );
  assert(sql.includes("development_record_audience_is_immutable"));
  assert(sql.includes("trg_sd_development_report_audience_immutable"));
  assert(sql.includes("trg_sd_development_alert_audience_immutable"));
  assert(
    sql.includes(
      "p_audience='player' and report.requested_by=auth.uid()",
    ),
    "player report read is exact self/requester",
  );
  assert(
    sql.includes(
      "p_audience='player' and public.sd_development_copilot_actor_can_access(auth.uid(),p_org_id,p_player_id,'player')",
    ),
    "active self membership required",
  );
  assert(sql.includes("sd_development_reports_audience_read"));
  assert(sql.includes("sd_development_report_evidence_audience_read"));
  assert(sql.includes("sd_development_alerts_audience_read"));
  assert(sql.includes("sd_development_alert_evidence_audience_read"));
  assert(
    sql.includes("audience='staff' and exists(") &&
      sql.includes("sd_development_report_review_events.report_id"),
    "review history remains staff-only and correlated",
  );
  assert(sql.includes("p_action<>'archive' or current_report.status<>'draft'"));
  assert(sql.includes("if p_action<>'dismiss'"));
  assert(sql.includes("invalid_player_alert_type"));
  assert(sql.includes("invalid_player_development_evidence"));
  assert(
    sql.includes(
      "revoke execute on function public.sd_create_development_report(",
    ),
    "legacy mutation grant retired",
  );
  assert(
    sql.includes(
      "grant execute on function public.sd_create_development_report_audience",
    ),
    "audience-aware RPC service-only",
  );
  assert(!sql.includes("insert into public.sd_notifications"));
  assert(!sql.includes("insert into public.sd_notification_deliveries"));
  assert(!sql.includes("delete from public.sd_development"));
});

Deno.test("Edge audience-aware create-report RPC arguments exactly match the unapplied SQL contract", async () => {
  const [sourceText, sqlText] = await Promise.all([
    Deno.readTextFile(
      new URL("../player-development-ai/index.ts", import.meta.url),
    ),
    Deno.readTextFile(
      new URL(
        "../../migrations/20260715100000_player_development_copilot.sql",
        import.meta.url,
      ),
    ),
  ]);
  const signatureStart = sqlText.indexOf(
    "create or replace function public.sd_create_development_report_audience(",
  );
  const signatureEnd = sqlText.indexOf(") returns jsonb", signatureStart);
  const sqlArguments = [
    ...sqlText.slice(signatureStart, signatureEnd).matchAll(
      /\b(p_[a-z_]+)\s+(?:uuid|text|date|timestamptz|jsonb|numeric|text\[\])/gi,
    ),
  ].map((match) => match[1]);
  const rpcStart = sourceText.indexOf(
    '"sd_create_development_report_audience"',
  );
  const rpcEnd = sourceText.indexOf("    );", rpcStart);
  const edgeArguments = [
    ...sourceText.slice(rpcStart, rpcEnd).matchAll(
      /\b(p_[a-z_]+):/g,
    ),
  ].map((match) => match[1]);
  assertEqual(
    [...edgeArguments].sort().join(","),
    [...sqlArguments].sort().join(","),
    "RPC argument names",
  );
  assertEqual(edgeArguments.length, 21, "complete RPC argument count");
});

Deno.test("Phase 11A function requires JWT verification and no external AI provider or secret", async () => {
  const [sourceText, sharedText, configText] = await Promise.all([
    Deno.readTextFile(
      new URL("../player-development-ai/index.ts", import.meta.url),
    ),
    Deno.readTextFile(new URL("./player_development_ai.ts", import.meta.url)),
    Deno.readTextFile(new URL("../../config.toml", import.meta.url)),
  ]);
  const normalized = `${sourceText}\n${sharedText}`.toLowerCase();
  assert(
    configText.includes(
      "[functions.player-development-ai]\nverify_jwt = true",
    ),
  );
  assert(normalized.includes("auth.getuser()"));
  assert(normalized.includes("p_actor_id"));
  assert(normalized.includes("this.admin.rpc"));
  assert(!normalized.includes("this.callerclient().rpc"));
  assert(normalized.includes("source_limits"));
  for (
    const stage of [
      "generate_request_received",
      "actor_verified",
      "organization_authorized",
      "player_authorized",
      "evidence_pack_built",
      "deterministic_report_built",
      "report_rpc_started",
      "report_rpc_succeeded",
      "report_rpc_failed",
    ]
  ) assert(normalized.includes(stage), `missing safe diagnostic ${stage}`);
  assert(!normalized.includes("api.openai.com"));
  assert(!normalized.includes("api.anthropic.com"));
  assert(!normalized.includes("openai_api_key"));
  assert(!normalized.includes("anthropic_api_key"));
});

Deno.test("demo sources retain sanitized synthetic provenance and assignment context", () => {
  const pack = buildEvidencePack({
    orgId,
    playerId,
    reportType: "player_development_summary",
    windowStart: "2026-04-16",
    windowEnd: "2026-07-15",
    cutoff: now.toISOString(),
    definitions,
    source: source({
      testing_entries: [{
        ...source().testing_entries[0]!,
        notes: "home_plate_demo_seed | phase_11a.v1 | synthetic_unverified",
      }],
      metric_observations: [{
        id: "demo-observation",
        org_id: orgId,
        player_id: playerId,
        canonical_key: "hitting.max_exit_velocity",
        normalized_value: 86,
        observed_value: "86",
        unit: "mph",
        observed_at: "2026-07-10T15:00:00Z",
        source_system: "home_plate_demo_seed",
        source_entity_type: "home_plate_demo_seed.max_exit_velocity",
        source_record_id: "demo-source-record",
        quality_status: "sufficient",
        sample_size: 1,
        context_metadata: {
          demo_seed: true,
          demo_version: "phase_11a.v1",
          verification_status: "synthetic_unverified",
        },
      }],
      daily_logs: [{
        ...source().daily_logs[0]!,
        notes: "home_plate_demo_seed | phase_11a.v1 | synthetic_unverified",
      }],
      program_assignments: [{
        id: "demo-assignment",
        org_id: orgId,
        player_id: playerId,
        template_id: "demo-template",
        start_date: "2026-06-15",
        ended_at: null,
        notes: "home_plate_demo_seed | phase_11a.v1 | synthetic_unverified",
      }],
      bp_sessions: [{
        id: "demo-bp-session",
        org_id: orgId,
        player_id: playerId,
        session_date: "2026-07-08",
        source: "trackman",
        reps_type: "practice",
        events: [{
          id: "demo-bp-event",
          exit_velo: 84,
          distance: 350,
          launch_angle: 20,
          raw: {
            demo_seed: true,
            demo_version: "phase_11a.v1",
            verification_status: "synthetic_unverified",
          },
        }],
      }],
    }),
  });
  const expectedTypes = [
    "sd_testing_entries",
    "home_plate_demo_seed.max_exit_velocity",
    "sd_program_assignments",
    "sd_bp_sessions",
    "sd_daily_logs_window",
  ];
  for (const sourceType of expectedTypes) {
    const item = pack.evidence.find((evidence) =>
      evidence.source_entity_type === sourceType
    );
    assert(item !== undefined, `missing ${sourceType} evidence`);
    assertEqual(
      item!.source_metadata.demo_seed,
      true,
      `${sourceType} demo provenance`,
    );
    assertEqual(
      item!.source_metadata.verification_status,
      "synthetic_unverified",
      `${sourceType} verification status`,
    );
    assertEqual(
      item!.evidence_snapshot.verification_status,
      "synthetic_unverified",
      `${sourceType} alert-safe verification status`,
    );
  }
  const assignment = pack.evidence.find((item) =>
    item.source_entity_type === "sd_program_assignments"
  );
  assert(
    assignment?.explanation.includes(
      "does not prove attendance or completion",
    ) ===
      true,
    "assignment stays contextual",
  );
});

Deno.test("Phase 11A demo SQL is guarded, idempotent, synthetic, and cleanup scoped", async () => {
  const [seed, cleanup, documentation] = await Promise.all([
    Deno.readTextFile(
      new URL(
        "../../../tools/sql/player_development_ai_demo_seed.sql",
        import.meta.url,
      ),
    ),
    Deno.readTextFile(
      new URL(
        "../../../tools/sql/player_development_ai_demo_cleanup.sql",
        import.meta.url,
      ),
    ),
    Deno.readTextFile(
      new URL(
        "../../../Docs/PLAYER_DEVELOPMENT_AI_DEMO_VALIDATION.md",
        import.meta.url,
      ),
    ),
  ]);
  const normalizedSeed = seed.toLowerCase();
  const normalizedCleanup = cleanup.toLowerCase();
  assertEqual(
    seed.match(/<ORG_ID>/g)?.length ?? 0,
    1,
    "one seed org placeholder",
  );
  assertEqual(
    seed.match(/<PLAYER_ID>/g)?.length ?? 0,
    1,
    "one seed player placeholder",
  );
  assert(normalizedSeed.includes("v_confirmation <> v_required_confirmation"));
  assert(
    normalizedSeed.includes("m.org_id = v_org_id and m.user_id = v_player_id"),
  );
  assert(normalizedSeed.includes("m.role = 'player' and m.status = 'active'"));
  assert(
    normalizedSeed.indexOf("raise exception 'a reserved demo uuid") <
      normalizedSeed.indexOf("insert into public.sd_program_templates"),
  );
  for (
    const table of [
      "sd_testing_entries",
      "sd_player_metric_observations",
      "sd_daily_logs",
      "sd_program_assignments",
      "sd_bp_sessions",
      "sd_bp_events",
    ]
  ) assert(normalizedSeed.includes(`public.${table}`), `missing ${table}`);
  assert(
    (normalizedSeed.match(/on conflict \(id\) do update/g) ?? []).length >= 7,
  );
  assert(normalizedSeed.includes("source_system, source_entity_type"));
  assert(normalizedSeed.includes("'home_plate_demo_seed'"));
  assert(normalizedSeed.includes("'phase_11a.v1'"));
  assert(normalizedSeed.includes("'synthetic_unverified'"));
  assert(normalizedSeed.includes("'hitting.max_exit_velocity'"));
  assert(normalizedSeed.includes("'physical.sprint_time'"));
  assert(normalizedSeed.includes("'strength.squat_1rm'"));
  assert(normalizedSeed.includes("'consistency.process_adherence_rate'"));
  assert(normalizedSeed.includes("'ai demo validation program'"));
  assert(normalizedSeed.includes("insert into public.sd_daily_logs"));
  assert(normalizedSeed.includes("insert into public.sd_bp_events"));
  assert(!normalizedSeed.includes("insert into public.sd_development_reports"));
  assert(!normalizedSeed.includes("insert into public.sd_development_alerts"));
  assert(!normalizedSeed.includes("sd_notifications"));
  assert(!normalizedSeed.includes("apns"));
  assertEqual(
    cleanup.match(/<ORG_ID>/g)?.length ?? 0,
    1,
    "one cleanup org placeholder",
  );
  assertEqual(
    cleanup.match(/<PLAYER_ID>/g)?.length ?? 0,
    1,
    "one cleanup player placeholder",
  );
  assert(
    normalizedCleanup.includes("v_confirmation <> v_required_confirmation"),
  );
  assert(normalizedCleanup.includes("source_system = v_source"));
  assert(normalizedCleanup.includes("e.raw @> jsonb_build_object"));
  assert(
    normalizedCleanup.indexOf("delete from public.sd_bp_events") <
      normalizedCleanup.indexOf("delete from public.sd_bp_sessions"),
  );
  assert(
    normalizedCleanup.indexOf("delete from public.sd_program_assignments") <
      normalizedCleanup.indexOf("delete from public.sd_program_templates"),
  );
  for (
    const auditTable of [
      "sd_development_reports",
      "sd_development_report_evidence",
      "sd_development_report_review_events",
      "sd_development_alerts",
      "sd_development_alert_evidence",
      "sd_development_alert_events",
    ]
  ) {
    assert(
      !normalizedCleanup.includes(`delete from public.${auditTable}`),
      `cleanup must preserve ${auditTable}`,
    );
  }
  assert(
    documentation.toLowerCase().includes("use the app/edge function path"),
  );
  assert(documentation.includes("having count(*) > 1"));
});
