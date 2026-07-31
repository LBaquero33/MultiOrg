import {
  createClient,
  type SupabaseClient,
} from "npm:@supabase/supabase-js@2.49.1";

type JsonRecord = Record<string, unknown>;

const url = Deno.env.get("SUPABASE_URL");
const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

if (!url || !anonKey || !serviceKey) {
  throw new Error(
    "Set SUPABASE_URL, SUPABASE_ANON_KEY, and SUPABASE_SERVICE_ROLE_KEY from `supabase status -o env`.",
  );
}

const admin = createClient(url, serviceKey, {
  auth: { persistSession: false, autoRefreshToken: false },
});

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

function requireData<T>(
  result: { data: T | null; error: { message: string } | null },
  label: string,
): T {
  if (result.error) throw new Error(`${label}: ${result.error.message}`);
  if (result.data === null) throw new Error(`${label}: missing data`);
  return result.data;
}

async function signIn(
  email: string,
  password: string,
): Promise<SupabaseClient> {
  const client = createClient(url!, anonKey!, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data, error } = await client.auth.signInWithPassword({
    email,
    password,
  });
  if (error) throw new Error(`sign in ${email}: ${error.message}`);
  assert(data.session, `sign in ${email}: missing session`);
  client.realtime.setAuth(data.session.access_token);
  return client;
}

async function waitFor(
  predicate: () => boolean,
  label: string,
  timeoutMs = 10_000,
): Promise<void> {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    if (predicate()) return;
    await new Promise((resolve) => setTimeout(resolve, 25));
  }
  throw new Error(`Timed out waiting for ${label}`);
}

async function subscribe(
  client: SupabaseClient,
  table: string,
  gameId: string,
  onInsert: (row: JsonRecord) => void,
) {
  let state = "";
  const channel = client
    .channel(`${table}:${gameId}:${crypto.randomUUID()}`)
    .on(
      "postgres_changes",
      {
        event: "INSERT",
        schema: "public",
        table,
        filter: `game_id=eq.${gameId}`,
      },
      (payload) => onInsert(payload.new as JsonRecord),
    )
    .subscribe((status) => {
      state = status;
    });
  await waitFor(() => state === "SUBSCRIBED", `${table} subscription`);
  return channel;
}

async function removeChannels(
  clients: SupabaseClient[],
): Promise<void> {
  await Promise.all(clients.map((client) => client.removeAllChannels()));
}

async function simultaneous<T>(
  left: () => Promise<T>,
  right: () => Promise<T>,
): Promise<[PromiseSettledResult<T>, PromiseSettledResult<T>]> {
  let release!: () => void;
  const barrier = new Promise<void>((resolve) => {
    release = resolve;
  });
  const run = (operation: () => Promise<T>) =>
    (async () => {
      await barrier;
      return await operation();
    })();
  const leftPromise = run(left);
  const rightPromise = run(right);
  release();
  return await Promise.allSettled([leftPromise, rightPromise]) as [
    PromiseSettledResult<T>,
    PromiseSettledResult<T>,
  ];
}

async function rpc(
  client: SupabaseClient,
  name: string,
  parameters: JsonRecord,
): Promise<unknown> {
  const { data, error } = await client.rpc(name, parameters);
  if (error) throw new Error(`${name}: ${error.message}`);
  return data;
}

function controlState(value: unknown): {
  state: string;
  control_token?: string;
  request_id?: string;
} {
  assert(
    value && typeof value === "object",
    "control RPC returned invalid JSON",
  );
  const record = value as JsonRecord;
  assert(typeof record.state === "string", "control state missing");
  return record as {
    state: string;
    control_token?: string;
    request_id?: string;
  };
}

Deno.test({
  name:
    "Realtime game fan-out and scorekeeper lease races use independent authenticated clients",
  sanitizeOps: false,
  sanitizeResources: false,
  fn: async () => {
    const suffix = crypto.randomUUID();
    const password = "Local-realtime-test-42!";
    const emails = {
      owner: `game-owner-${suffix}@test.local`,
      coach: `game-coach-${suffix}@test.local`,
      player: `game-player-${suffix}@test.local`,
      outsider: `game-outsider-${suffix}@test.local`,
      otherOwner: `game-other-owner-${suffix}@test.local`,
    };
    const userIds: string[] = [];
    const orgId = crypto.randomUUID();
    const otherOrgId = crypto.randomUUID();
    const teamId = crypto.randomUUID();
    const clients: SupabaseClient[] = [];

    try {
      const createdUsers: Record<string, string> = {};
      for (const [role, email] of Object.entries(emails)) {
        const { data, error } = await admin.auth.admin.createUser({
          email,
          password,
          email_confirm: true,
          user_metadata: {
            full_name: `Realtime ${role}`,
            role: role.includes("player") || role === "outsider"
              ? "player"
              : "coach",
          },
        });
        if (error) throw new Error(`create ${role}: ${error.message}`);
        assert(data.user, `create ${role}: missing user`);
        createdUsers[role] = data.user.id;
        userIds.push(data.user.id);
      }

      requireData(
        await admin.from("sd_orgs").insert([
          { id: orgId, slug: `realtime-${suffix}`, name: "Realtime Test Org" },
          {
            id: otherOrgId,
            slug: `realtime-other-${suffix}`,
            name: "Other Realtime Org",
          },
        ]).select(),
        "create organizations",
      );
      requireData(
        await admin.from("sd_org_memberships").insert([
          {
            org_id: orgId,
            user_id: createdUsers.owner,
            role: "owner",
            status: "active",
          },
          {
            org_id: orgId,
            user_id: createdUsers.coach,
            role: "coach",
            status: "active",
          },
          {
            org_id: orgId,
            user_id: createdUsers.player,
            role: "player",
            status: "active",
          },
          {
            org_id: otherOrgId,
            user_id: createdUsers.otherOwner,
            role: "owner",
            status: "active",
          },
        ]).select(),
        "create memberships",
      );
      requireData(
        await admin.from("sd_teams").insert({
          id: teamId,
          org_id: orgId,
          name: `Realtime Team ${suffix.slice(0, 8)}`,
          created_by: createdUsers.owner,
        }).select(),
        "create team",
      );

      const owner = await signIn(emails.owner, password);
      const ownerSecondSession = await signIn(emails.owner, password);
      const coach = await signIn(emails.coach, password);
      const player = await signIn(emails.player, password);
      const outsider = await signIn(emails.outsider, password);
      const otherOwner = await signIn(emails.otherOwner, password);
      clients.push(
        owner,
        ownerSecondSession,
        coach,
        player,
        outsider,
        otherOwner,
      );

      const now = Date.now();
      const game = requireData(
        await owner.rpc("sd_create_game", {
          p_org_id: orgId,
          p_team_id: teamId,
          p_title: "Realtime Validation Game",
          p_opponent_name: "Visitors",
          p_scheduled_start: new Date(now + 3_600_000).toISOString(),
          p_scheduled_end: new Date(now + 10_800_000).toISOString(),
          p_arrival_time: new Date(now + 1_800_000).toISOString(),
          p_timezone: "America/New_York",
          p_site: "home",
          p_venue_name: "Local Test Field",
          p_facility_id: null,
          p_scheduled_innings: 7,
          p_visibility: "team",
        }),
        "create game",
      ) as JsonRecord;
      const gameId = game.id as string;
      const eventId = game.event_id as string;
      assert(gameId && eventId, "created game identifiers missing");

      requireData(
        await admin.from("sd_event_participants").insert([
          {
            org_id: orgId,
            event_id: eventId,
            participant_type: "scorekeeper",
            user_id: createdUsers.coach,
            role: "scorekeeper",
            can_view: true,
            can_edit: true,
            can_score: true,
            invited_by: createdUsers.owner,
          },
          {
            org_id: orgId,
            event_id: eventId,
            participant_type: "player",
            user_id: createdUsers.player,
            role: "player",
            can_view: true,
            can_edit: false,
            can_score: false,
            invited_by: createdUsers.owner,
          },
        ]).select(),
        "create game participants",
      );

      const ownerDevice = crypto.randomUUID();
      const ownerControl = controlState(
        await rpc(owner, "sd_acquire_scorekeeping_control", {
          p_game_id: gameId,
          p_device_id: ownerDevice,
          p_authenticated_session_id: "realtime-fanout-owner",
        }),
      );
      assert(
        ownerControl.state === "liveScorekeeper" && ownerControl.control_token,
        "owner did not acquire initial scoring control",
      );

      const viewerEvents: JsonRecord[] = [];
      const outsiderEvents: JsonRecord[] = [];
      const crossOrgEvents: JsonRecord[] = [];
      await subscribe(
        player,
        "sd_game_scoring_events",
        gameId,
        (row) => viewerEvents.push(row),
      );
      await subscribe(
        outsider,
        "sd_game_scoring_events",
        gameId,
        (row) => outsiderEvents.push(row),
      );
      await subscribe(
        otherOwner,
        "sd_game_scoring_events",
        gameId,
        (row) => crossOrgEvents.push(row),
      );

      // A freshly reset local Realtime tenant reports SUBSCRIBED before its
      // Postgres CDC stream has always finished its first cold start.
      await new Promise((resolve) => setTimeout(resolve, 1_000));
      assert(
        viewerEvents.length === 0 &&
          outsiderEvents.length === 0 &&
          crossOrgEvents.length === 0,
        "a local pending gesture was broadcast before an authoritative commit",
      );

      const firstEventId = crypto.randomUUID();
      await rpc(owner, "sd_append_game_scoring_event", {
        p_game_id: gameId,
        p_canonical_event_id: eventId,
        p_scoring_event_id: firstEventId,
        p_expected_version: 0,
        p_event_type: "pitch",
        p_actor_device_id: ownerDevice,
        p_control_token: ownerControl.control_token,
        p_payload: { result: "strike" },
        p_idempotency_key: `realtime-first-${suffix}`,
        p_correction_of_event_id: null,
        p_supersedes_event_id: null,
      });
      await waitFor(
        () => viewerEvents.length === 1,
        "authorized scoring event",
      );
      await new Promise((resolve) => setTimeout(resolve, 500));
      assert(
        Array.from(viewerEvents).length === 1,
        "authorized viewer received a duplicate",
      );
      assert(
        viewerEvents[0].game_version === 1,
        "authorized viewer received the wrong game version",
      );
      assert(
        outsiderEvents.length === 0,
        "unauthorized user received game data",
      );
      assert(
        crossOrgEvents.length === 0,
        "cross-organization user received game data",
      );

      await player.removeAllChannels();
      const reconnectEvents: JsonRecord[] = [];
      await subscribe(
        player,
        "sd_game_scoring_events",
        gameId,
        (row) => reconnectEvents.push(row),
      );
      const secondEventId = crypto.randomUUID();
      await rpc(owner, "sd_append_game_scoring_event", {
        p_game_id: gameId,
        p_canonical_event_id: eventId,
        p_scoring_event_id: secondEventId,
        p_expected_version: 1,
        p_event_type: "play",
        p_actor_device_id: ownerDevice,
        p_control_token: ownerControl.control_token,
        p_payload: { result: "single" },
        p_idempotency_key: `realtime-second-${suffix}`,
        p_correction_of_event_id: null,
        p_supersedes_event_id: null,
      });
      await waitFor(
        () => reconnectEvents.length === 1,
        "reconnected scoring event",
      );
      assert(
        reconnectEvents[0].id === secondEventId &&
          reconnectEvents[0].game_version === 2,
        "reconnected viewer replayed or mis-versioned an event",
      );

      const decisionId = crypto.randomUUID();
      const decision = requireData(
        await owner.rpc("sd_append_game_scoring_decision", {
          p_game_id: gameId,
          p_physical_event_id: secondEventId,
          p_root_decision_id: decisionId,
          p_supersedes_decision_id: null,
          p_decision_type: "hit",
          p_preliminary_value: null,
          p_final_value: "single",
          p_decision_status: "final",
          p_rule_reference: "realtime-test",
          p_reasoning_note: "Initial official scoring",
          p_review_requested: false,
        }),
        "create official scoring decision",
      ) as JsonRecord;
      const finalDecisionId = decision.id as string;
      assert(finalDecisionId, "official scoring decision ID missing");

      await rpc(owner, "sd_append_game_scoring_event", {
        p_game_id: gameId,
        p_canonical_event_id: eventId,
        p_scoring_event_id: crypto.randomUUID(),
        p_expected_version: 2,
        p_event_type: "game_ended",
        p_actor_device_id: ownerDevice,
        p_control_token: ownerControl.control_token,
        p_payload: { reason: "completed" },
        p_idempotency_key: `realtime-ended-${suffix}`,
        p_correction_of_event_id: null,
        p_supersedes_event_id: null,
      });
      await rpc(owner, "sd_finalize_game", {
        p_game_id: gameId,
        p_expected_version: 3,
        p_actor_device_id: ownerDevice,
        p_control_token: ownerControl.control_token,
        p_idempotency_key: `realtime-finalize-${suffix}`,
        p_statistics: {
          batting: {},
          pitching: {},
          fielding: {},
          team_totals: {},
        },
        p_validation: { issues: [] },
      });

      const correctionEvents: JsonRecord[] = [];
      await subscribe(
        player,
        "sd_game_audit_log",
        gameId,
        (row) => {
          if (row.action === "final_game_corrected") correctionEvents.push(row);
        },
      );
      await rpc(owner, "sd_correct_final_game_decision", {
        p_game_id: gameId,
        p_superseded_decision_id: finalDecisionId,
        p_replacement_value: "error",
        p_reason: "Postgame scoring review",
        p_idempotency_key: `realtime-correction-${suffix}`,
        p_statistics: {
          batting: {},
          pitching: {},
          fielding: {},
          team_totals: {},
        },
        p_validation: { issues: [] },
      });
      await waitFor(
        () => correctionEvents.length === 1,
        "final correction audit event",
      );
      await new Promise((resolve) => setTimeout(resolve, 500));
      assert(
        correctionEvents.length === 1,
        "final correction reached the viewer more than once",
      );

      const raceGame = requireData(
        await owner.rpc("sd_create_game", {
          p_org_id: orgId,
          p_team_id: teamId,
          p_title: "Lease Race Validation Game",
          p_opponent_name: "Race Visitors",
          p_scheduled_start: new Date(now + 86_400_000).toISOString(),
          p_scheduled_end: new Date(now + 97_200_000).toISOString(),
          p_arrival_time: null,
          p_timezone: "America/New_York",
          p_site: "home",
          p_venue_name: "Local Test Field",
          p_facility_id: null,
          p_scheduled_innings: 7,
          p_visibility: "team",
        }),
        "create lease race game",
      ) as JsonRecord;
      const raceGameId = raceGame.id as string;
      const raceEventId = raceGame.event_id as string;
      requireData(
        await admin.from("sd_event_participants").insert({
          org_id: orgId,
          event_id: raceEventId,
          participant_type: "scorekeeper",
          user_id: createdUsers.coach,
          role: "scorekeeper",
          can_view: true,
          can_edit: true,
          can_score: true,
          invited_by: createdUsers.owner,
        }).select(),
        "create race scorekeeper",
      );

      for (let iteration = 0; iteration < 25; iteration += 1) {
        const { error: clearError } = await admin
          .from("sd_game_scorekeeper_sessions")
          .delete()
          .eq("game_id", raceGameId);
        if (clearError) {
          throw new Error(`clear lease race: ${clearError.message}`);
        }
        const ownerRaceDevice = crypto.randomUUID();
        const coachRaceDevice = crypto.randomUUID();
        const results = await simultaneous(
          () =>
            rpc(owner, "sd_acquire_scorekeeping_control", {
              p_game_id: raceGameId,
              p_device_id: ownerRaceDevice,
              p_authenticated_session_id: `owner-race-${iteration}`,
            }),
          () =>
            rpc(coach, "sd_acquire_scorekeeping_control", {
              p_game_id: raceGameId,
              p_device_id: coachRaceDevice,
              p_authenticated_session_id: `coach-race-${iteration}`,
            }),
        );
        assert(
          results.every((result) => result.status === "fulfilled"),
          `lease acquisition iteration ${iteration} rejected unexpectedly`,
        );
        const states = results.map((result) =>
          controlState((result as PromiseFulfilledResult<unknown>).value)
        );
        assert(
          states.filter((state) => state.state === "liveScorekeeper").length ===
            1,
          `iteration ${iteration} did not produce exactly one scorekeeper`,
        );
        assert(
          states.filter((state) => state.state === "liveViewer").length === 1,
          `iteration ${iteration} did not produce exactly one viewer`,
        );
        const sessionRows = requireData(
          await admin.from("sd_game_scorekeeper_sessions")
            .select("*")
            .eq("game_id", raceGameId),
          `read lease iteration ${iteration}`,
        ) as JsonRecord[];
        assert(
          sessionRows.length === 1 &&
            sessionRows[0].session_status === "active",
          `iteration ${iteration} left an invalid active-session count`,
        );

        const losingClient = states[0].state === "liveViewer" ? owner : coach;
        const losingDevice = states[0].state === "liveViewer"
          ? ownerRaceDevice
          : coachRaceDevice;
        const { error: loserMutationError } = await losingClient.rpc(
          "sd_append_game_scoring_event",
          {
            p_game_id: raceGameId,
            p_canonical_event_id: raceEventId,
            p_scoring_event_id: crypto.randomUUID(),
            p_expected_version: 0,
            p_event_type: "pitch",
            p_actor_device_id: losingDevice,
            p_control_token: "not-a-valid-control-token",
            p_payload: {},
            p_idempotency_key: `loser-${suffix}-${iteration}`,
            p_correction_of_event_id: null,
            p_supersedes_event_id: null,
          },
        );
        assert(
          loserMutationError?.message.includes("scorekeeper_lease_invalid"),
          `iteration ${iteration} loser mutation was not rejected`,
        );
      }

      await admin.from("sd_game_scorekeeper_sessions")
        .delete()
        .eq("game_id", raceGameId);
      const initialForceDevice = crypto.randomUUID();
      await rpc(owner, "sd_acquire_scorekeeping_control", {
        p_game_id: raceGameId,
        p_device_id: initialForceDevice,
        p_authenticated_session_id: "force-initial",
      });
      const forceDeviceA = crypto.randomUUID();
      const forceDeviceB = crypto.randomUUID();
      const forceResults = await simultaneous(
        () =>
          rpc(owner, "sd_force_scorekeeping_takeover", {
            p_game_id: raceGameId,
            p_device_id: forceDeviceA,
            p_authenticated_session_id: "force-a",
          }),
        () =>
          rpc(ownerSecondSession, "sd_force_scorekeeping_takeover", {
            p_game_id: raceGameId,
            p_device_id: forceDeviceB,
            p_authenticated_session_id: "force-b",
          }),
      );
      assert(
        forceResults.every((result) => result.status === "fulfilled"),
        "concurrent admin force takeover failed",
      );
      const forceSession = requireData(
        await admin.from("sd_game_scorekeeper_sessions")
          .select("*")
          .eq("game_id", raceGameId)
          .single(),
        "read force-takeover session",
      ) as JsonRecord;
      const activeForceDevice = String(forceSession.active_device_id);
      assert(
        activeForceDevice === forceDeviceA ||
          activeForceDevice === forceDeviceB,
        "force takeover did not retain either competing device",
      );

      const winningForce = activeForceDevice === forceDeviceA
        ? controlState(
          (forceResults[0] as PromiseFulfilledResult<unknown>).value,
        )
        : controlState(
          (forceResults[1] as PromiseFulfilledResult<unknown>).value,
        );
      const losingForce = activeForceDevice === forceDeviceA
        ? controlState(
          (forceResults[1] as PromiseFulfilledResult<unknown>).value,
        )
        : controlState(
          (forceResults[0] as PromiseFulfilledResult<unknown>).value,
        );
      assert(
        winningForce.control_token && losingForce.control_token,
        "force takeover control tokens missing",
      );
      const { error: staleForceError } = await owner.rpc(
        "sd_append_game_scoring_event",
        {
          p_game_id: raceGameId,
          p_canonical_event_id: raceEventId,
          p_scoring_event_id: crypto.randomUUID(),
          p_expected_version: 0,
          p_event_type: "pitch",
          p_actor_device_id: forceSession.active_device_id === forceDeviceA
            ? forceDeviceB
            : forceDeviceA,
          p_control_token: losingForce.control_token,
          p_payload: {},
          p_idempotency_key: `stale-force-${suffix}`,
          p_correction_of_event_id: null,
          p_supersedes_event_id: null,
        },
      );
      assert(
        staleForceError?.message.includes("scorekeeper_lease_invalid"),
        "superseded force-takeover token remained usable",
      );

      const { error: expireError } = await admin
        .from("sd_game_scorekeeper_sessions")
        .update({
          lease_expires_at: new Date(Date.now() - 1_000).toISOString(),
        })
        .eq("game_id", raceGameId);
      if (expireError) throw new Error(`expire lease: ${expireError.message}`);
      const expirationResults = await simultaneous(
        () =>
          rpc(owner, "sd_acquire_scorekeeping_control", {
            p_game_id: raceGameId,
            p_device_id: crypto.randomUUID(),
            p_authenticated_session_id: "expired-owner",
          }),
        () =>
          rpc(coach, "sd_acquire_scorekeeping_control", {
            p_game_id: raceGameId,
            p_device_id: crypto.randomUUID(),
            p_authenticated_session_id: "expired-coach",
          }),
      );
      const expirationStates = expirationResults.map((result) => {
        assert(result.status === "fulfilled", "expiration race rejected");
        return controlState(result.value);
      });
      assert(
        expirationStates.filter((state) => state.state === "liveScorekeeper")
          .length === 1,
        "lease-expiration boundary produced multiple scorekeepers",
      );

      await admin.from("sd_game_scorekeeper_sessions")
        .delete()
        .eq("game_id", raceGameId);
      const heartbeatDevice = crypto.randomUUID();
      const heartbeatControl = controlState(
        await rpc(owner, "sd_acquire_scorekeeping_control", {
          p_game_id: raceGameId,
          p_device_id: heartbeatDevice,
          p_authenticated_session_id: "heartbeat-owner",
        }),
      );
      assert(heartbeatControl.control_token, "heartbeat token missing");
      const heartbeatResults = await simultaneous(
        () =>
          rpc(owner, "sd_renew_scorekeeping_control", {
            p_game_id: raceGameId,
            p_device_id: heartbeatDevice,
            p_control_token: heartbeatControl.control_token,
          }),
        () =>
          rpc(ownerSecondSession, "sd_renew_scorekeeping_control", {
            p_game_id: raceGameId,
            p_device_id: heartbeatDevice,
            p_control_token: heartbeatControl.control_token,
          }),
      );
      assert(
        heartbeatResults.every((result) =>
          result.status === "fulfilled" && result.value === true
        ),
        "duplicate heartbeat was not idempotently accepted",
      );

      const transferCoachDevice = crypto.randomUUID();
      const request = controlState(
        await rpc(coach, "sd_request_scorekeeping_control", {
          p_game_id: raceGameId,
          p_device_id: transferCoachDevice,
        }),
      );
      assert(
        request.request_id && request.control_token,
        "control transfer request proof missing",
      );
      const transferRace = await simultaneous(
        () =>
          rpc(owner, "sd_resolve_scorekeeping_control_request", {
            p_request_id: request.request_id,
            p_approve: true,
            p_active_device_id: heartbeatDevice,
            p_control_token: heartbeatControl.control_token,
          }),
        async () => {
          const result = await owner.rpc("sd_append_game_scoring_event", {
            p_game_id: raceGameId,
            p_canonical_event_id: raceEventId,
            p_scoring_event_id: crypto.randomUUID(),
            p_expected_version: 0,
            p_event_type: "pitch",
            p_actor_device_id: heartbeatDevice,
            p_control_token: heartbeatControl.control_token,
            p_payload: { transfer_race: true },
            p_idempotency_key: `transfer-race-${suffix}`,
            p_correction_of_event_id: null,
            p_supersedes_event_id: null,
          });
          if (result.error) throw new Error(result.error.message);
          return result.data;
        },
      );
      assert(
        transferRace[0].status === "fulfilled",
        "control transfer was not approved",
      );
      const postTransferSession = requireData(
        await admin.from("sd_game_scorekeeper_sessions")
          .select("*")
          .eq("game_id", raceGameId)
          .single(),
        "read transferred session",
      ) as JsonRecord;
      assert(
        postTransferSession.active_user_id === createdUsers.coach &&
          postTransferSession.active_device_id === transferCoachDevice,
        "approved transfer did not install the requesting coach",
      );
      const { error: oldTokenError } = await owner.rpc(
        "sd_append_game_scoring_event",
        {
          p_game_id: raceGameId,
          p_canonical_event_id: raceEventId,
          p_scoring_event_id: crypto.randomUUID(),
          p_expected_version: postTransferSession.current_game_version,
          p_event_type: "pitch",
          p_actor_device_id: heartbeatDevice,
          p_control_token: heartbeatControl.control_token,
          p_payload: {},
          p_idempotency_key: `old-token-${suffix}`,
          p_correction_of_event_id: null,
          p_supersedes_event_id: null,
        },
      );
      assert(
        oldTokenError?.message.includes("scorekeeper_lease_invalid"),
        "old token remained usable after control transfer",
      );
      const coachEvent = await rpc(
        coach,
        "sd_append_game_scoring_event",
        {
          p_game_id: raceGameId,
          p_canonical_event_id: raceEventId,
          p_scoring_event_id: crypto.randomUUID(),
          p_expected_version: postTransferSession.current_game_version,
          p_event_type: "pitch",
          p_actor_device_id: transferCoachDevice,
          p_control_token: request.control_token,
          p_payload: { after_transfer: true },
          p_idempotency_key: `coach-after-transfer-${suffix}`,
          p_correction_of_event_id: null,
          p_supersedes_event_id: null,
        },
      ) as JsonRecord;
      assert(coachEvent.game_version, "new scorekeeper could not mutate");

      const reconnect = controlState(
        await rpc(owner, "sd_acquire_scorekeeping_control", {
          p_game_id: raceGameId,
          p_device_id: heartbeatDevice,
          p_authenticated_session_id: "old-owner-reconnect",
        }),
      );
      assert(
        reconnect.state === "liveViewer" && !reconnect.control_token,
        "old device did not reconnect as a viewer after takeover",
      );
    } finally {
      await removeChannels(clients);
      await admin.from("sd_orgs").delete().in("id", [orgId, otherOrgId]);
      for (const userId of userIds) {
        await admin.auth.admin.deleteUser(userId);
      }
    }
  },
});
