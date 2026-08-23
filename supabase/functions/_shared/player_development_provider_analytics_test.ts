import {
  MARIST_PROVIDER_ANALYTICS_VERSION,
  summarizeProviderSession,
} from "./player_development_provider_analytics.ts";
import {
  detectProvider,
  parseImportText,
} from "./player_development_imports.ts";

function assert(condition: boolean, message = "assertion failed") {
  if (!condition) throw new Error(message);
}
function equal<T>(actual: T, expected: T, message: string) {
  if (actual !== expected) {
    throw new Error(`${message}: expected ${expected}, received ${actual}`);
  }
}

const fixtureRoot = new URL("./fixtures/player_imports/", import.meta.url);
const fixture = (name: string) => Deno.readTextFileSync(new URL(name, fixtureRoot));

Deno.test("HitTrax fixture produces hitting summaries with the Marist barrel rule", () => {
  const parsed = parseImportText(fixture("hittrax_hitting_sanitized.csv"), "csv");
  const detection = detectProvider(parsed);
  const summary = summarizeProviderSession(parsed, detection);
  equal(summary.schema_version, MARIST_PROVIDER_ANALYTICS_VERSION, "schema");
  equal(summary.provider, "hittrax", "provider");
  equal(summary.hitting?.exit_velocity.sample_count, 3, "exit velocity count");
  equal(summary.hitting?.exit_velocity.maximum, 101.2, "maximum exit velocity");
  equal(summary.hitting?.barrel_count, 1, "barrels");
  equal(summary.hitting?.barrel_rate, 0.333, "barrel rate");
  equal(summary.pitching, null, "no pitching summary");
});

Deno.test("Rapsodo hitting fixture produces provider-aware event summaries", () => {
  const parsed = parseImportText(fixture("rapsodo_hitting_sanitized.csv"), "csv");
  const summary = summarizeProviderSession(parsed, detectProvider(parsed));
  equal(summary.provider, "rapsodo", "provider");
  assert((summary.hitting?.exit_velocity.sample_count ?? 0) > 0, "hitting values");
  equal(summary.pitching, null, "no pitching summary");
});

Deno.test("Rapsodo pitching fixture groups velocity and spin by pitch type", () => {
  const parsed = parseImportText(fixture("rapsodo_pitching_sanitized.csv"), "csv");
  const summary = summarizeProviderSession(parsed, detectProvider(parsed));
  equal(summary.provider, "rapsodo", "provider");
  assert((summary.pitching?.velocity.sample_count ?? 0) > 0, "pitching velocity");
  assert((summary.pitching?.by_pitch_type.length ?? 0) > 0, "pitch groups");
});

Deno.test("TrackMan fixture summarizes hitting and pitching without conflating metrics", () => {
  const parsed = parseImportText(fixture("trackman_radar_sanitized.csv"), "csv");
  const summary = summarizeProviderSession(parsed, detectProvider(parsed));
  equal(summary.provider, "trackman", "provider");
  assert((summary.pitching?.velocity.sample_count ?? 0) > 0, "pitching velocity");
  assert((summary.pitching?.spin_rate.sample_count ?? 0) > 0, "spin rate");
  assert((summary.hitting?.exit_velocity.sample_count ?? 0) > 0, "exit velocity");
});
