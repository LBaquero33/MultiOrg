import {
  createClient,
  type SupabaseClient,
} from "https://esm.sh/@supabase/supabase-js@2.49.1";
import {
  type AlertCandidate,
  type BPSession,
  createPlayerDevelopmentAIHandler,
  type DailyLog,
  type DevelopmentAlert,
  type DevelopmentAlertDetail,
  type DevelopmentEvidence,
  type DevelopmentEvidenceSource,
  type DevelopmentMembership,
  type DevelopmentReportDetail,
  type DevelopmentReportRecord,
  type MetricDefinition,
  type MetricObservation,
  type PlayerDevelopmentAIStore,
  type ProgramAssignment,
  type TestingEntry,
} from "../_shared/player_development_ai.ts";

const env = (name: string) => (Deno.env.get(name) ?? "").trim();
const url = env("SUPABASE_URL") || env("DHD_SUPABASE_URL");
const anonKey = env("SUPABASE_ANON_KEY") || env("DHD_SUPABASE_ANON_KEY");
const serviceKey = env("DHD_SERVICE_ROLE_KEY") ||
  env("SUPABASE_SERVICE_ROLE_KEY");
const SOURCE_LIMITS = {
  testingEntries: 250,
  metricObservations: 1_000,
  dailyLogs: 731,
  programAssignments: 500,
  bpSessions: 500,
  bpEvents: 10_000,
  metricDefinitions: 1_000,
} as const;

type Row = Record<string, unknown>;

function asRows(value: unknown): Row[] {
  return Array.isArray(value)
    ? value.filter((item): item is Row =>
      typeof item === "object" && item !== null
    )
    : [];
}

function isObject(value: unknown): value is Row {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function logDevelopmentStage(
  event: string,
  fields: Record<string, string | number | boolean>,
) {
  console.log(JSON.stringify({ event, ...fields }));
}

function errorMessage(error: unknown, fallback: string): never {
  const message =
    typeof error === "object" && error !== null && "message" in error &&
      typeof error.message === "string"
      ? error.message
      : fallback;
  throw new Error(message || fallback);
}

async function sha256(value: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(value),
  );
  return Array.from(new Uint8Array(digest)).map((byte) =>
    byte.toString(16).padStart(2, "0")
  ).join("");
}

export class SupabasePlayerDevelopmentAIStore
  implements PlayerDevelopmentAIStore {
  private readonly admin: SupabaseClient;

  constructor() {
    this.admin = createClient(url, serviceKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
  }

  async authenticate(request: Request): Promise<string | null> {
    const authorization = request.headers.get("Authorization") ?? "";
    if (!authorization) return null;
    const caller = createClient(url, anonKey, {
      global: { headers: { Authorization: authorization } },
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data, error } = await caller.auth.getUser();
    if (error) return null;
    return data.user?.id ?? null;
  }

  async platformFeatureEnabled(key: string): Promise<boolean> {
    const { data, error } = await this.admin.from("sd_platform_feature_flags")
      .select("enabled").eq("key", key).maybeSingle();
    if (error) {
      console.error(JSON.stringify({
        event: "platform_feature_flag_lookup_failed",
        key,
      }));
      return false;
    }
    return data?.enabled === true;
  }

  async organizationStatus(orgId: string): Promise<string | null> {
    const { data, error } = await this.admin.from("sd_orgs").select("status")
      .eq("id", orgId).maybeSingle();
    if (error) errorMessage(error, "organization_lookup_failed");
    return typeof data?.status === "string" ? data.status : null;
  }

  async membership(
    orgId: string,
    actorId: string,
  ): Promise<DevelopmentMembership | null> {
    const { data, error } = await this.admin.from("sd_org_memberships")
      .select("role,status").eq("org_id", orgId).eq("user_id", actorId)
      .maybeSingle();
    if (error) errorMessage(error, "membership_lookup_failed");
    return data && typeof data.role === "string" &&
        typeof data.status === "string"
      ? { role: data.role, status: data.status }
      : null;
  }

  async authorizedPlayerIds(
    orgId: string,
    actorId: string,
  ): Promise<Set<string>> {
    const membership = await this.membership(orgId, actorId);
    if (
      !membership || membership.status !== "active" ||
      !["owner", "admin", "coach"].includes(membership.role)
    ) return new Set();
    const { data: players, error: playerError } = await this.admin.from(
      "sd_org_memberships",
    )
      .select("user_id").eq("org_id", orgId).eq("role", "player").eq(
        "status",
        "active",
      );
    if (playerError) {
      errorMessage(playerError, "player_membership_lookup_failed");
    }
    const allPlayers = asRows(players).map((row) => row.user_id).filter((
      id,
    ): id is string => typeof id === "string");
    if (["owner", "admin"].includes(membership.role)) {
      return new Set(allPlayers);
    }

    const { data: settings, error: settingsError } = await this.admin.from(
      "sd_org_settings",
    )
      .select("team_policy").eq("org_id", orgId).maybeSingle();
    if (settingsError) {
      errorMessage(settingsError, "organization_settings_lookup_failed");
    }
    const policy = settings?.team_policy;
    const restrict = typeof policy === "object" && policy !== null &&
        "restrictCoachActionsToTeam" in policy
      ? policy.restrictCoachActionsToTeam !== false
      : true;
    if (!restrict) return new Set(allPlayers);

    const { data: coachTeam, error: coachTeamError } = await this.admin.from(
      "sd_team_members",
    )
      .select("team_id").eq("org_id", orgId).eq("player_id", actorId)
      .maybeSingle();
    if (coachTeamError) {
      errorMessage(coachTeamError, "coach_team_lookup_failed");
    }
    if (!coachTeam || typeof coachTeam.team_id !== "string") return new Set();
    const { data: activeTeam, error: activeTeamError } = await this.admin.from(
      "sd_teams",
    ).select("id").eq("org_id", orgId).eq("id", coachTeam.team_id).eq(
      "is_active",
      true,
    ).maybeSingle();
    if (activeTeamError) {
      errorMessage(activeTeamError, "coach_team_lookup_failed");
    }
    if (!activeTeam) return new Set();
    const { data: teamPlayers, error: teamError } = await this.admin.from(
      "sd_team_members",
    )
      .select("player_id").eq("org_id", orgId).eq("team_id", coachTeam.team_id)
      .in("player_id", allPlayers);
    if (teamError) errorMessage(teamError, "team_player_lookup_failed");
    return new Set(
      asRows(teamPlayers).map((row) => row.player_id).filter((
        id,
      ): id is string => typeof id === "string"),
    );
  }

  async metricDefinitions(): Promise<MetricDefinition[]> {
    const { data, error } = await this.admin.from(
      "sd_development_metric_definitions",
    )
      .select(
        "id,canonical_key,display_name,category,canonical_unit,preferred_direction,target_min,target_max,minimum_sample_size",
      )
      .eq("status", "active").order("canonical_key").limit(
        SOURCE_LIMITS.metricDefinitions,
      );
    if (error) errorMessage(error, "metric_definition_lookup_failed");
    return (data ?? []) as MetricDefinition[];
  }

  async evidenceSource(
    orgId: string,
    playerId: string,
    start: string,
    end: string,
    cutoff: string,
  ): Promise<DevelopmentEvidenceSource> {
    const [
      profileResult,
      testingResult,
      observationResult,
      dailyResult,
      assignmentResult,
      bpResult,
      reportResult,
      definitionsResult,
    ] = await Promise.all([
      this.admin.from("profiles").select("id,full_name").eq("id", playerId)
        .single(),
      this.admin.from("sd_testing_entries").select(
        "id,org_id,player_id,entry_date,height_in,weight_lb,squat_1rm,bench_1rm,deadlift_1rm,max_exit_velo,avg_exit_velo,hip_er_diff,hip_ir_diff,shoulder_ir_diff,shoulder_er_diff,notes",
      )
        .eq("org_id", orgId).eq("player_id", playerId).gte("entry_date", start)
        .lte("entry_date", end).lte("created_at", cutoff).order("entry_date")
        .order("id").limit(SOURCE_LIMITS.testingEntries + 1),
      this.admin.from("sd_player_metric_observations").select(
        "id,org_id,player_id,metric_definition_id,normalized_value,observed_value,unit,observed_at,source_system,source_entity_type,source_record_id,import_job_id,original_unit,canonical_unit,verification_status,parser_version,mapping_version,source_row_number,quality_status,sample_size,context_metadata",
      )
        .eq("org_id", orgId).eq("player_id", playerId).gte(
          "observed_at",
          `${start}T00:00:00Z`,
        ).lte("observed_at", `${end}T23:59:59.999Z`).lte(
          "created_at",
          cutoff,
        ).order("observed_at").order("id").limit(
          SOURCE_LIMITS.metricObservations + 1,
        ),
      this.admin.from("sd_daily_logs").select(
        "id,org_id,player_id,log_date,feel,hit_daily_goals,stuck_to_process,notes",
      )
        .eq("org_id", orgId).eq("player_id", playerId).gte("log_date", start)
        .lte("log_date", end).lte("created_at", cutoff).order("log_date")
        .order("id").limit(SOURCE_LIMITS.dailyLogs + 1),
      this.admin.from("sd_program_assignments").select(
        "id,org_id,player_id,template_id,start_date,ended_at,notes",
      )
        .eq("org_id", orgId).eq("player_id", playerId).lte("start_date", end)
        .or(`ended_at.is.null,ended_at.gte.${start}T00:00:00Z`).lte(
          "created_at",
          cutoff,
        ).order("start_date").order("id").limit(
          SOURCE_LIMITS.programAssignments + 1,
        ),
      this.admin.from("sd_bp_sessions").select(
        "id,org_id,player_id,session_date,source,reps_type",
      )
        .eq("org_id", orgId).eq("player_id", playerId).gte(
          "session_date",
          start,
        ).lte("session_date", end).lte("created_at", cutoff).order(
          "session_date",
        ).order("id").limit(SOURCE_LIMITS.bpSessions + 1),
      this.admin.from("sd_development_reports").select("id", {
        count: "exact",
        head: true,
      })
        .eq("org_id", orgId).eq("player_id", playerId).in("status", [
          "draft",
          "reviewed",
        ]).eq("audience", "staff"),
      this.admin.from("sd_development_metric_definitions").select(
        "id,canonical_key",
      ).order("canonical_key").limit(SOURCE_LIMITS.metricDefinitions),
    ]);
    for (
      const result of [
        profileResult,
        testingResult,
        observationResult,
        dailyResult,
        assignmentResult,
        bpResult,
        reportResult,
        definitionsResult,
      ]
    ) {
      if (result.error) {
        errorMessage(result.error, "development_evidence_lookup_failed");
      }
    }
    const definitionKey = new Map(
      asRows(definitionsResult.data).map((row) => [row.id, row.canonical_key]),
    );
    const sourceWarnings: string[] = [];
    const testingRows = asRows(testingResult.data);
    const observationRows = asRows(observationResult.data);
    const dailyRows = asRows(dailyResult.data);
    const assignmentRows = asRows(assignmentResult.data);
    const bpRows = asRows(bpResult.data);
    for (
      const [rows, maximum, label] of [
        [testingRows, SOURCE_LIMITS.testingEntries, "testing entries"],
        [
          observationRows,
          SOURCE_LIMITS.metricObservations,
          "metric observations",
        ],
        [dailyRows, SOURCE_LIMITS.dailyLogs, "daily logs"],
        [
          assignmentRows,
          SOURCE_LIMITS.programAssignments,
          "program assignments",
        ],
        [bpRows, SOURCE_LIMITS.bpSessions, "batting-practice sessions"],
      ] as const
    ) {
      if (rows.length > maximum) {
        sourceWarnings.push(
          `The evidence window exceeded the ${maximum} ${label} safety limit; narrow the reporting window for complete coverage.`,
        );
      }
    }
    const observations: MetricObservation[] = observationRows.slice(
      0,
      SOURCE_LIMITS.metricObservations,
    )
      .map((row) => ({
        ...(row as Omit<MetricObservation, "canonical_key">),
        canonical_key: String(
          definitionKey.get(row.metric_definition_id) ?? "",
        ),
      })).filter((row) => row.canonical_key.length > 0);
    const sessions = bpRows.slice(
      0,
      SOURCE_LIMITS.bpSessions,
    ) as Omit<BPSession, "events">[];
    let eventsBySession = new Map<string, BPSession["events"]>();
    if (sessions.length > 0) {
      const { data: eventData, error: eventError } = await this.admin.from(
        "sd_bp_events",
      )
        .select("id,session_id,exit_velo,distance,launch_angle,raw").in(
          "session_id",
          sessions.map((session) => session.id),
        ).lte("created_at", cutoff).order("session_id").order("id").limit(
          SOURCE_LIMITS.bpEvents + 1,
        );
      if (eventError) errorMessage(eventError, "bp_event_lookup_failed");
      if ((eventData?.length ?? 0) > SOURCE_LIMITS.bpEvents) {
        sourceWarnings.push(
          `The evidence window exceeded the ${SOURCE_LIMITS.bpEvents} batting-practice event safety limit; narrow the reporting window for complete coverage.`,
        );
      }
      eventsBySession = new Map();
      for (const row of asRows(eventData).slice(0, SOURCE_LIMITS.bpEvents)) {
        if (typeof row.session_id !== "string" || typeof row.id !== "string") {
          continue;
        }
        eventsBySession.set(row.session_id, [
          ...(eventsBySession.get(row.session_id) ?? []),
          {
            id: row.id,
            exit_velo: typeof row.exit_velo === "number" ? row.exit_velo : null,
            distance: typeof row.distance === "number" ? row.distance : null,
            launch_angle: typeof row.launch_angle === "number"
              ? row.launch_angle
              : null,
            raw: row.raw && typeof row.raw === "object"
              ? row.raw as Record<string, unknown>
              : {},
          },
        ]);
      }
    }
    return {
      player: profileResult.data as { id: string; full_name: string | null },
      testing_entries: testingRows.slice(
        0,
        SOURCE_LIMITS.testingEntries,
      ) as TestingEntry[],
      metric_observations: observations,
      daily_logs: dailyRows.slice(0, SOURCE_LIMITS.dailyLogs) as DailyLog[],
      program_assignments: assignmentRows.slice(
        0,
        SOURCE_LIMITS.programAssignments,
      ) as ProgramAssignment[],
      bp_sessions: sessions.map((session) => ({
        ...session,
        events: eventsBySession.get(session.id) ?? [],
      })),
      reports_awaiting_review: reportResult.count ?? 0,
      source_warnings: sourceWarnings,
    };
  }

  async createReport(
    input: Parameters<PlayerDevelopmentAIStore["createReport"]>[0],
  ): Promise<{ report: DevelopmentReportRecord; reused: boolean }> {
    const fingerprint = await sha256(JSON.stringify({
      org_id: input.orgId,
      player_id: input.playerId,
      report_type: input.reportType,
      intended_audience: input.intendedAudience,
      audience: input.audience,
      window_start: input.windowStart,
      window_end: input.windowEnd,
      input_cutoff: input.cutoff,
      generator_version: input.generatorVersion,
      prompt_version: input.promptVersion,
    }));
    const { data, error } = await this.admin.rpc(
      "sd_create_development_report_audience",
      {
        p_actor_id: input.actorId,
        p_org_id: input.orgId,
        p_player_id: input.playerId,
        p_report_type: input.reportType,
        p_intended_audience: input.intendedAudience,
        p_audience: input.audience,
        p_window_start: input.windowStart,
        p_window_end: input.windowEnd,
        p_input_cutoff: input.cutoff,
        p_idempotency_key: input.idempotencyKey,
        p_request_fingerprint: fingerprint,
        p_evidence_fingerprint: input.evidenceFingerprint,
        p_quality_status: input.qualityStatus,
        p_structured_content: input.content,
        p_rendered_text: input.renderedText,
        p_confidence: input.confidence,
        p_data_freshness: input.dataFreshness,
        p_missing_data_warnings: input.warnings,
        p_evidence: input.evidence,
        p_prompt_version: input.promptVersion,
        p_generator_version: input.generatorVersion,
      },
    );
    if (error) errorMessage(error, "development_report_create_failed");
    if (
      !isObject(data) || !isObject(data.report) ||
      typeof data.reused !== "boolean"
    ) {
      throw new Error("development_report_response_invalid");
    }
    return {
      report: data.report as unknown as DevelopmentReportRecord,
      reused: data.reused,
    };
  }

  async listReports(
    orgId: string,
    playerIds: string[],
    playerId?: string,
    audience: "staff" | "player" = "staff",
  ): Promise<DevelopmentReportRecord[]> {
    const allowed = playerId
      ? playerIds.filter((id) => id === playerId)
      : playerIds;
    if (allowed.length === 0) return [];
    const { data, error } = await this.admin.from("sd_development_reports")
      .select("*")
      .eq("org_id", orgId).eq("audience", audience).in("player_id", allowed)
      .order("created_at", {
        ascending: false,
      }).limit(200);
    if (error) errorMessage(error, "development_report_list_failed");
    return (data ?? []) as DevelopmentReportRecord[];
  }

  async reportDetail(
    orgId: string,
    reportId: string,
    playerIds: string[],
    audience: "staff" | "player",
  ): Promise<DevelopmentReportDetail | null> {
    if (playerIds.length === 0) return null;
    const reportResult = await this.admin.from("sd_development_reports")
      .select("*").eq("org_id", orgId).eq("id", reportId).eq(
        "audience",
        audience,
      ).in(
        "player_id",
        playerIds,
      ).maybeSingle();
    if (reportResult.error) {
      errorMessage(reportResult.error, "development_report_detail_failed");
    }
    if (!reportResult.data) return null;
    const [evidenceResult, historyResult] = await Promise.all([
      this.admin.from("sd_development_report_evidence").select("*").eq(
        "org_id",
        orgId,
      ).eq("report_id", reportId).eq("audience", audience).order(
        "observation_date",
      ),
      audience === "staff"
        ? this.admin.from("sd_development_report_review_events").select("*")
          .eq("org_id", orgId).eq("report_id", reportId).eq(
            "audience",
            "staff",
          ).order("created_at")
        : Promise.resolve({ data: [], error: null }),
    ]);
    if (evidenceResult.error || historyResult.error) {
      errorMessage(
        evidenceResult.error ?? historyResult.error,
        "development_report_detail_failed",
      );
    }
    return {
      report: reportResult.data as DevelopmentReportRecord,
      evidence: (evidenceResult.data ?? []) as DevelopmentEvidence[],
      review_history: asRows(historyResult.data),
    };
  }

  async reviewReport(
    actorId: string,
    orgId: string,
    reportId: string,
    action: string,
    notes: string | null,
    edits: Record<string, unknown>,
    audience: "staff" | "player",
  ): Promise<DevelopmentReportRecord> {
    const { data, error } = await this.admin.rpc(
      "sd_review_development_report_audience",
      {
        p_actor_id: actorId,
        p_org_id: orgId,
        p_report_id: reportId,
        p_action: action,
        p_review_notes: notes,
        p_coach_edits: edits,
        p_audience: audience,
      },
    );
    if (error) errorMessage(error, "development_report_review_failed");
    return data as DevelopmentReportRecord;
  }

  async listAlerts(
    orgId: string,
    playerIds: string[],
    playerId?: string,
    audience: "staff" | "player" = "staff",
  ): Promise<DevelopmentAlert[]> {
    const allowed = playerId
      ? playerIds.filter((id) => id === playerId)
      : playerIds;
    if (allowed.length === 0) return [];
    const { data, error } = await this.admin.from("sd_development_alerts")
      .select("*")
      .eq("org_id", orgId).eq("audience", audience).in("player_id", allowed)
      .order("last_detected_at", {
        ascending: false,
      }).limit(500);
    if (error) errorMessage(error, "development_alert_list_failed");
    const alerts = (data ?? []) as DevelopmentAlert[];
    const { data: profiles, error: profileError } = await this.admin.from(
      "profiles",
    ).select("id,full_name").in("id", allowed);
    if (profileError) errorMessage(profileError, "profile_lookup_failed");
    const names = new Map(
      asRows(profiles).map((row) => [row.id, row.full_name]),
    );
    return alerts.map((alert) => ({
      ...alert,
      player_name: typeof names.get(alert.player_id) === "string"
        ? names.get(alert.player_id) as string
        : null,
    }));
  }

  async alertDetail(
    orgId: string,
    alertId: string,
    playerIds: string[],
    audience: "staff" | "player",
  ): Promise<DevelopmentAlertDetail | null> {
    if (playerIds.length === 0) return null;
    const alertResult = await this.admin.from("sd_development_alerts").select(
      "*",
    ).eq("org_id", orgId).eq("id", alertId).eq("audience", audience).in(
      "player_id",
      playerIds,
    ).maybeSingle();
    if (alertResult.error) {
      errorMessage(alertResult.error, "development_alert_detail_failed");
    }
    if (!alertResult.data) return null;
    const [evidenceResult, historyResult] = await Promise.all([
      this.admin.from("sd_development_alert_evidence").select("*").eq(
        "org_id",
        orgId,
      ).eq("alert_id", alertId).eq("audience", audience).order(
        "observation_date",
      ),
      audience === "staff"
        ? this.admin.from("sd_development_alert_events").select("*").eq(
          "org_id",
          orgId,
        ).eq("alert_id", alertId).eq("audience", "staff").order("created_at")
        : Promise.resolve({ data: [], error: null }),
    ]);
    if (evidenceResult.error || historyResult.error) {
      errorMessage(
        evidenceResult.error ?? historyResult.error,
        "development_alert_detail_failed",
      );
    }
    return {
      alert: alertResult.data as DevelopmentAlert,
      evidence:
        (evidenceResult.data ?? []) as DevelopmentAlertDetail["evidence"],
      review_history: asRows(historyResult.data),
    };
  }

  async persistAlerts(
    actorId: string,
    orgId: string,
    alerts: AlertCandidate[],
    audience: "staff" | "player",
  ): Promise<DevelopmentAlert[]> {
    if (alerts.length === 0) return [];
    const { data, error } = await this.admin.rpc(
      "sd_upsert_development_alerts_audience",
      {
        p_actor_id: actorId,
        p_org_id: orgId,
        p_alerts: alerts,
        p_audience: audience,
      },
    );
    if (error) errorMessage(error, "development_alert_persist_failed");
    return (data ?? []) as DevelopmentAlert[];
  }

  async reviewAlert(
    actorId: string,
    orgId: string,
    alertId: string,
    action: string,
    notes: string | null,
    audience: "staff" | "player",
  ): Promise<DevelopmentAlert> {
    const { data, error } = await this.admin.rpc(
      "sd_review_development_alert_audience",
      {
        p_actor_id: actorId,
        p_org_id: orgId,
        p_alert_id: alertId,
        p_action: action,
        p_notes: notes,
        p_audience: audience,
      },
    );
    if (error) errorMessage(error, "development_alert_review_failed");
    return data as DevelopmentAlert;
  }
}

if (import.meta.main) {
  Deno.serve((request) =>
    createPlayerDevelopmentAIHandler(
      new SupabasePlayerDevelopmentAIStore(),
      () => new Date(),
      logDevelopmentStage,
    )(request)
  );
}
