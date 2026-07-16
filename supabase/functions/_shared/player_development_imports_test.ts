import {
  buildImportStoragePath,
  buildPreview,
  buildValidationPersistencePayload,
  type ColumnMapping,
  convertUnit,
  decodeImportFile,
  detectDelimiter,
  detectProvider,
  headerFingerprint,
  IMPORT_LIMITS,
  ImportRequestError,
  mappingFingerprint,
  type MetricDefinition,
  normalizeExternalID,
  normalizeHeader,
  normalizeUsername,
  parseDelimitedText,
  parseImportText,
  parseObservationDate,
  type PlayerCandidate,
  PROVIDER_ADAPTERS,
  recommendedMapping,
  stableObservationUUID,
} from "./player_development_imports.ts";

function assert(condition: boolean, message = "assertion failed") {
  if (!condition) throw new Error(message);
}
function equal<T>(actual: T, expected: T, message: string) {
  if (actual !== expected) {
    throw new Error(`${message}: expected ${expected}, received ${actual}`);
  }
}
function throwsCode(fn: () => unknown, code: string) {
  try {
    fn();
  } catch (error) {
    if (error instanceof ImportRequestError && error.code === code) return;
    throw error;
  }
  throw new Error(`expected ${code}`);
}

const fixtureRoot = new URL("./fixtures/player_imports/", import.meta.url);
const fixture = (name: string) =>
  Deno.readTextFileSync(new URL(name, fixtureRoot));
const playerId = "44444444-4444-4444-8444-444444444444";
const players: PlayerCandidate[] = [{
  id: playerId,
  fullName: "Fictional Avery",
  username: "avery_demo",
  active: true,
}];
const definitions: MetricDefinition[] = [
  {
    id: "1",
    canonical_key: "hitting.max_exit_velocity",
    display_name: "Maximum Exit Velocity",
    category: "hitting",
    canonical_unit: "mph",
    preferred_direction: "higher_is_better",
    minimum_sample_size: 2,
    status: "active",
  },
  {
    id: "2",
    canonical_key: "hitting.bat_speed",
    display_name: "Bat Speed",
    category: "hitting",
    canonical_unit: "mph",
    preferred_direction: "context_dependent",
    minimum_sample_size: 3,
    status: "active",
  },
  {
    id: "3",
    canonical_key: "pitching.velocity",
    display_name: "Pitch Velocity",
    category: "pitching",
    canonical_unit: "mph",
    preferred_direction: "context_dependent",
    minimum_sample_size: 5,
    status: "active",
  },
  {
    id: "4",
    canonical_key: "physical.body_weight",
    display_name: "Body Weight",
    category: "physical",
    canonical_unit: "lb",
    preferred_direction: "informational",
    minimum_sample_size: 2,
    status: "active",
  },
  {
    id: "5",
    canonical_key: "old.metric",
    display_name: "Old",
    category: "old",
    canonical_unit: "mph",
    preferred_direction: "informational",
    minimum_sample_size: 1,
    status: "deprecated",
  },
];

const vendorMetricUnits: Record<string, string> = {
  "hitting.exit_velocity": "mph",
  "hitting.pitch_velocity_seen": "mph",
  "hitting.launch_angle": "deg",
  "hitting.exit_direction": "deg",
  "hitting.batted_ball_spin_rate": "rpm",
  "hitting.distance": "ft",
  "pitching.velocity": "mph",
  "pitching.spin_rate": "rpm",
  "pitching.true_spin": "rpm",
  "pitching.spin_efficiency": "percent",
  "pitching.release_height": "ft",
  "pitching.release_side": "ft",
  "pitching.horizontal_approach_angle": "deg",
  "pitching.vertical_approach_angle": "deg",
  "pitching.extension": "ft",
};
const persistenceDefinitions: MetricDefinition[] = [
  ...new Map(
    [
      ...definitions,
      ...Object.entries(vendorMetricUnits).map(([key, unit], index) => ({
        id: `vendor-${index}`,
        canonical_key: key,
        display_name: key,
        category: key.split(".")[0],
        canonical_unit: unit,
        preferred_direction: "context_dependent",
        minimum_sample_size: 1,
        status: "active",
      } satisfies MetricDefinition)),
    ].map((definition) => [definition.canonical_key, definition] as const),
  ).values(),
];

const longMapping: ColumnMapping = {
  shape: "long",
  timezone: "America/New_York",
  dateFormat: "ISO",
  columns: {
    player_name: "player",
    observation_date: "date",
    metric: "metric",
    value: "value",
    unit: "unit",
  },
};

Deno.test("comma and tab delimiters are detected outside quoted values", () => {
  equal(detectDelimiter('player,date,note\nA,2026-01-01,"x,y"'), ",", "comma");
  equal(detectDelimiter("player\tdate\tnote\nA\t2026-01-01\tx,y"), "\t", "tab");
  throwsCode(
    () => detectDelimiter("player,date\tmetric\nA,2026-01-01\tvelocity"),
    "ambiguous_delimiter",
  );
});

Deno.test("quoted delimiters, escaped quotes, CRLF, and blank rows parse safely", () => {
  const parsed = parseDelimitedText(
    'player,note\r\n"Diaz, Jr.","said ""go"""\r\n\r\n',
    "csv",
  );
  equal(parsed.rows[0][0], "Diaz, Jr.", "quoted name");
  equal(parsed.rows[0][1], 'said "go"', "escaped quote");
  equal(parsed.blankRows, 1, "blank row");
  throwsCode(
    () => parseDelimitedText('a,b\n"closed"suffix,x', "csv"),
    "malformed_csv",
  );
  throwsCode(
    () => parseDelimitedText('a,b\nunquoted"quote,x', "csv"),
    "malformed_csv",
  );
});

Deno.test("UTF-8 BOM is removed and invalid UTF-8 is rejected", () => {
  equal(normalizeHeader("\uFEFF Player Name "), "player_name", "BOM header");
  equal(
    decodeImportFile(new TextEncoder().encode("\uFEFFplayer,date")),
    "player,date",
    "BOM file",
  );
  throwsCode(
    () => decodeImportFile(new Uint8Array([0xff, 0xfe, 0x00])),
    "unsupported_file_encoding",
  );
});

Deno.test("missing and duplicate headers are rejected", () => {
  throwsCode(
    () => parseDelimitedText("onlyone\nvalue", "csv"),
    "missing_header",
  );
  throwsCode(
    () => parseDelimitedText(fixture("duplicate_headers.csv"), "csv"),
    "duplicate_header",
  );
});

Deno.test("file, row, column, and line bounds are enforced", () => {
  throwsCode(
    () => decodeImportFile(new Uint8Array(IMPORT_LIMITS.maxFileBytes + 1)),
    "file_too_large",
  );
  const headers = Array.from({ length: 251 }, (_, i) => `c${i}`).join(",");
  throwsCode(
    () => parseDelimitedText(`${headers}\n`, "csv"),
    "column_limit_exceeded",
  );
  const huge = `a,b\n${"x".repeat(IMPORT_LIMITS.maxLineCharacters + 1)},y`;
  throwsCode(() => parseDelimitedText(huge, "csv"), "row_too_large");
  const rows = `a,b\n${"x,y\n".repeat(IMPORT_LIMITS.maxRows + 1)}`;
  throwsCode(() => parseDelimitedText(rows, "csv"), "row_limit_exceeded");
  throwsCode(
    () =>
      parseDelimitedText(
        `${"h".repeat(IMPORT_LIMITS.maxHeaderCharacters + 1)},b\nx,y`,
        "csv",
      ),
    "missing_header",
  );
  throwsCode(
    () =>
      parseDelimitedText(
        `a,b\n${"x".repeat(IMPORT_LIMITS.maxCellCharacters + 1)},y`,
        "csv",
      ),
    "cell_too_large",
  );
  throwsCode(() => parseDelimitedText("a,b\nx,y,z", "csv"), "extra_columns");
});

Deno.test("wide and long fixtures inspect with expected shape", () => {
  const wide = parseDelimitedText(fixture("valid_wide.csv"), "csv");
  equal(wide.totalRows, 2, "wide rows");
  const long = parseDelimitedText(fixture("valid_long.csv"), "csv");
  equal(long.headers[3], "metric", "long metric header");
  const tab = parseDelimitedText(fixture("valid.tsv"), "tsv");
  equal(tab.fileType, "tsv", "TSV type");
});

Deno.test("safe exact unit registry conversions preserve dimensions", () => {
  equal(convertUnit(90, "mph", "mph").normalizedValue, 90, "mph identity");
  const velocity = convertUnit(100, "km/h", "mph");
  assert(
    Math.abs(velocity.normalizedValue - 62.13711922) < 0.00001,
    "km/h to mph",
  );
  assert(
    Math.abs(convertUnit(10, "kg", "lb").normalizedValue - 22.046226218) <
      0.00001,
    "kg to lb",
  );
  equal(convertUnit(10, "lb", "lb").normalizedValue, 10, "pounds identity");
  equal(convertUnit(12, "in", "in").normalizedValue, 12, "inches identity");
  assert(
    Math.abs(convertUnit(100, "cm", "in").normalizedValue - 39.37007874) <
      0.00001,
    "centimeters to inches",
  );
  equal(convertUnit(3, "ft", "in").normalizedValue, 36, "feet to inches");
  assert(
    Math.abs(convertUnit(1, "m", "in").normalizedValue - 39.37007874) <
      0.00001,
    "meters to inches",
  );
  equal(convertUnit(2, "s", "s").normalizedValue, 2, "seconds identity");
  assert(
    Math.abs(convertUnit(1000, "ms", "s").normalizedValue - 1) < 0.00001,
    "ms to seconds",
  );
  equal(convertUnit(45, "deg", "deg").normalizedValue, 45, "degree identity");
  equal(convertUnit(2200, "rpm", "rpm").normalizedValue, 2200, "RPM identity");
  assert(
    Math.abs(convertUnit(1, "m", "ft").normalizedValue - 3.280839895) < 0.00001,
    "meters to feet",
  );
  throwsCode(() => convertUnit(90, "in", "mph"), "unit_conflict");
  throwsCode(() => convertUnit(90, "knots", "mph"), "unsupported_unit");
  equal(
    convertUnit(0.9, "decimal", "percent").normalizedValue,
    90,
    "ratio to percent",
  );
  equal(
    convertUnit(90, "percent", "decimal").normalizedValue,
    0.9,
    "percent to ratio",
  );
});

Deno.test("dates require explicit non-ambiguous rules and reject future values", () => {
  equal(
    parseObservationDate(
      "2026-01-02",
      "ISO",
      "America/New_York",
      new Date("2026-07-15T00:00:00Z"),
    )
      .toISOString(),
    "2026-01-02T17:00:00.000Z",
    "ISO date at local noon",
  );
  equal(
    parseObservationDate(
      "01/02/2026",
      "MM/DD/YYYY",
      "America/New_York",
      new Date("2026-07-15T00:00:00Z"),
    ).getUTCMonth(),
    0,
    "US month",
  );
  throwsCode(
    () => parseObservationDate("01/02/26", "MM/DD/YYYY"),
    "ambiguous_date",
  );
  throwsCode(
    () =>
      parseObservationDate(
        "2026-07-16",
        "ISO",
        "UTC",
        new Date("2026-07-15T00:00:00Z"),
      ),
    "future_date",
  );
  throwsCode(
    () => parseObservationDate("2026-01-02T10:00:00", "ISO"),
    "ambiguous_date",
  );
  equal(
    parseObservationDate(
      "2026-03-08",
      "ISO",
      "America/New_York",
      new Date("2026-07-15T00:00:00Z"),
    ).toISOString(),
    "2026-03-08T16:00:00.000Z",
    "DST date uses deterministic local noon",
  );
  throwsCode(
    () => parseObservationDate("2026-01-02", "ISO", "Not/A_Timezone"),
    "ambiguous_date",
  );
});

Deno.test("numeric parsing is invariant and never evaluates spreadsheet formulas", () => {
  const parsed = parseDelimitedText(
    "player,date,metric,value,unit\n" +
      "Fictional Avery,2026-01-01,hitting.bat_speed,1.2e2,mph\n" +
      'Fictional Avery,2026-01-02,hitting.bat_speed,"1,234.5",mph\n' +
      'Fictional Avery,2026-01-03,hitting.bat_speed,"1,23",mph\n' +
      "Fictional Avery,2026-01-04,hitting.bat_speed,=2+2,mph",
    "csv",
  );
  const rows = buildPreview({
    parsed,
    provider: "generic_csv",
    mapping: longMapping,
    definitions,
    players,
    identities: [],
    now: new Date("2026-07-15"),
  }).rows;
  equal(rows[0].normalizedValue, 120, "scientific notation");
  equal(rows[1].normalizedValue, 1234.5, "grouped thousands");
  assert(rows[2].errors.includes("invalid_number"), "locale decimal rejected");
  assert(
    rows[3].errors.includes("invalid_number"),
    "formula rejected as number",
  );
});

Deno.test("wide mappings reject duplicate columns, metrics, and protected roles", () => {
  const parsed = parseDelimitedText(
    "player,date,a,b\nFictional Avery,2026-01-01,1,2",
    "csv",
  );
  const base: ColumnMapping = {
    shape: "wide",
    timezone: "UTC",
    columns: { player_name: "player", observation_date: "date" },
    wideMetrics: [
      { column: "a", metricKey: "hitting.bat_speed", sourceUnit: "mph" },
      { column: "b", metricKey: "hitting.bat_speed", sourceUnit: "mph" },
    ],
  };
  throwsCode(
    () =>
      buildPreview({
        parsed,
        provider: "generic_csv",
        mapping: base,
        definitions,
        players,
        identities: [],
      }),
    "duplicate_metric_mapping",
  );
});

Deno.test("exact username and unique normalized name match; fuzzy names never confirm", () => {
  const parsed = parseDelimitedText(
    "player,username,date,metric,value,unit\nFictional Avery,,2026-01-01,hitting.bat_speed,70,mph\n,avery_demo,2026-01-02,hitting.bat_speed,71,mph\nFiction Avery,,2026-01-03,hitting.bat_speed,72,mph",
    "csv",
  );
  const preview = buildPreview({
    parsed,
    provider: "generic_csv",
    mapping: {
      ...longMapping,
      columns: { ...longMapping.columns, player_username: "username" },
    },
    definitions,
    players,
    identities: [],
    now: new Date("2026-07-15T00:00:00Z"),
  });
  equal(preview.rows[0].playerMatchState, "matched", "unique name");
  equal(preview.rows[1].playerMatchState, "matched", "username");
  equal(preview.rows[2].playerMatchState, "unmatched", "no fuzzy confirmation");
});

Deno.test("external ID has priority and manual resolution is explicit", () => {
  const parsed = parseDelimitedText(
    "external,player,date,metric,value,unit\nfiction-1,Wrong Name,2026-01-01,hitting.bat_speed,70,mph",
    "csv",
  );
  const mapping: ColumnMapping = {
    ...longMapping,
    columns: { ...longMapping.columns, player_external_id: "external" },
  };
  const first = buildPreview({
    parsed,
    provider: "generic_csv",
    mapping,
    definitions,
    players,
    identities: [{
      provider: "generic_csv",
      externalPlayerId: "fiction-1",
      playerId,
    }],
    now: new Date("2026-07-15"),
  });
  equal(first.rows[0].playerId, playerId, "external match");
  const resolvedMapping = {
    ...mapping,
    playerResolutions: { "external:fiction-1": playerId },
  };
  equal(
    buildPreview({
      parsed,
      provider: "generic_csv",
      mapping: resolvedMapping,
      definitions,
      players,
      identities: [],
      now: new Date("2026-07-15"),
    }).rows[0].playerId,
    playerId,
    "manual match",
  );
});

Deno.test("external IDs are case-insensitive but preserve meaningful punctuation", () => {
  equal(normalizeExternalID("  AB-12  "), "ab-12", "case and trim");
  assert(
    normalizeExternalID("AB-12") !== normalizeExternalID("AB 12"),
    "provider punctuation must not collapse",
  );
});

Deno.test("organization usernames are case-insensitive but punctuation-exact", () => {
  equal(normalizeUsername("  Avery_Demo "), "avery_demo", "case and trim");
  assert(
    normalizeUsername("avery_demo") !== normalizeUsername("avery-demo"),
    "username punctuation must not collapse",
  );
});

Deno.test("ambiguous and inactive players cannot be confirmed", () => {
  const parsed = parseDelimitedText(
    "player,date,metric,value,unit\nFictional Avery,2026-01-01,hitting.bat_speed,70,mph",
    "csv",
  );
  const ambiguous = buildPreview({
    parsed,
    provider: "generic_csv",
    mapping: longMapping,
    definitions,
    players: [...players, {
      id: "55555555-5555-4555-8555-555555555555",
      fullName: "Fictional Avery",
      active: true,
    }],
    identities: [],
    now: new Date("2026-07-15"),
  });
  equal(ambiguous.rows[0].playerMatchState, "ambiguous", "ambiguous name");
  const inactive = buildPreview({
    parsed,
    provider: "generic_csv",
    mapping: longMapping,
    definitions,
    players: [{ ...players[0], active: false }],
    identities: [],
    now: new Date("2026-07-15"),
  });
  equal(inactive.rows[0].playerMatchState, "unmatched", "inactive excluded");
});

Deno.test("unknown, deprecated, invalid-number, missing-unit and conflicting-unit rows reject", () => {
  const parsed = parseDelimitedText(
    "player,date,metric,value,unit\nFictional Avery,2026-01-01,unknown.metric,1,mph\nFictional Avery,2026-01-01,old.metric,1,mph\nFictional Avery,2026-01-01,hitting.bat_speed,nope,mph\nFictional Avery,2026-01-01,hitting.bat_speed,70,\nFictional Avery,2026-01-01,hitting.bat_speed,70,in",
    "csv",
  );
  const rows = buildPreview({
    parsed,
    provider: "generic_csv",
    mapping: longMapping,
    definitions,
    players,
    identities: [],
    now: new Date("2026-07-15"),
  }).rows;
  assert(rows[0].errors.includes("unsupported_metric"), "unknown metric");
  assert(rows[1].errors.includes("deprecated_metric"), "deprecated metric");
  assert(rows[2].errors.includes("invalid_number"), "invalid number");
  assert(rows[3].errors.includes("missing_unit"), "missing unit");
  assert(rows[4].errors.includes("unit_conflict"), "unit conflict");
});

Deno.test("duplicate source rows reject without affecting accepted count", () => {
  const parsed = parseDelimitedText(
    "player,date,metric,value,unit\nFictional Avery,2026-01-01,hitting.bat_speed,70,mph\nFictional Avery,2026-01-01,hitting.bat_speed,70,mph",
    "csv",
  );
  const result = buildPreview({
    parsed,
    provider: "generic_csv",
    mapping: longMapping,
    definitions,
    players,
    identities: [],
    now: new Date("2026-07-15"),
  });
  equal(result.summary.duplicateRows, 1, "duplicate count");
  equal(result.rows[1].acceptanceState, "duplicate", "duplicate state");
});

Deno.test("wide source-row totals are mutually exclusive when one metric rejects", () => {
  const parsed = parseDelimitedText(
    "player,date,bat_speed,exit_velocity\nFictional Avery,2026-01-01,70,nope",
    "csv",
  );
  const result = buildPreview({
    parsed,
    provider: "generic_csv",
    mapping: {
      shape: "wide",
      timezone: "America/New_York",
      dateFormat: "ISO",
      columns: { player_name: "player", observation_date: "date" },
      wideMetrics: [
        {
          column: "bat_speed",
          metricKey: "hitting.bat_speed",
          sourceUnit: "mph",
        },
        {
          column: "exit_velocity",
          metricKey: "hitting.max_exit_velocity",
          sourceUnit: "mph",
        },
      ],
    },
    definitions,
    players,
    identities: [],
    now: new Date("2026-07-15"),
  });
  equal(result.summary.totalRows, 1, "source rows");
  equal(result.summary.acceptedRows, 0, "accepted rows");
  equal(result.summary.rejectedRows, 1, "rejected rows");
  equal(result.summary.generatedObservations, 2, "generated observations");
});

Deno.test("original and normalized values and units are both retained", () => {
  const parsed = parseDelimitedText(
    "player,date,metric,value,unit\nFictional Avery,2026-01-01,hitting.bat_speed,100,km/h",
    "csv",
  );
  const row = buildPreview({
    parsed,
    provider: "generic_csv",
    mapping: longMapping,
    definitions,
    players,
    identities: [],
    now: new Date("2026-07-15"),
  }).rows[0];
  equal(row.originalValue, "100", "raw value");
  equal(row.originalUnit, "km/h", "raw unit");
  equal(row.canonicalUnit, "mph", "canonical unit");
  assert(row.normalizedValue !== 100, "converted value");
});

Deno.test("header and mapping fingerprints are deterministic and sensitive", async () => {
  equal(
    await headerFingerprint(["Player", "Date"]),
    await headerFingerprint([" player ", "DATE"]),
    "normalized headers",
  );
  assert(
    await headerFingerprint(["Player", "Metric"]) !==
      await headerFingerprint(["Player", "Date"]),
    "header difference",
  );
  const reordered = {
    ...longMapping,
    columns: {
      value: "value",
      metric: "metric",
      observation_date: "date",
      player_name: "player",
      unit: "unit",
    },
  } as ColumnMapping;
  equal(
    await mappingFingerprint(longMapping),
    await mappingFingerprint(reordered),
    "key order stable",
  );
});

Deno.test("stable observation identity is deterministic for file and row idempotency", async () => {
  const material = "org|file-hash|mapping|2|player|metric|100|mph|2026-01-01";
  equal(
    await stableObservationUUID(material),
    await stableObservationUUID(material),
    "same source identity",
  );
  assert(
    await stableObservationUUID(material) !==
      await stableObservationUUID(`${material}|changed`),
    "changed source identity",
  );
});

Deno.test("Rapsodo and TrackMan adapters are active while HitTrax remains fixture-gated", () => {
  equal(PROVIDER_ADAPTERS.generic_csv.productionActive, true, "generic active");
  equal(PROVIDER_ADAPTERS.rapsodo.productionActive, true, "Rapsodo active");
  equal(PROVIDER_ADAPTERS.trackman.productionActive, true, "TrackMan active");
  for (
    const key of [
      "hittrax",
      "blast",
      "pocket_radar",
      "strength_testing",
    ] as const
  ) {
    equal(PROVIDER_ADAPTERS[key].productionActive, false, `${key} inactive`);
  }
});

Deno.test("uppercase request UUIDs produce a lowercase storage path accepted by the database contract", () => {
  equal(
    buildImportStoragePath(
      "800E22AE-2A9D-4109-9E11-1360EEAA8EA7",
      "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA",
      "BBBBBBBB-BBBB-4BBB-8BBB-BBBBBBBBBBBB",
      "csv",
    ),
    "800e22ae-2a9d-4109-9e11-1360eeaa8ea7/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb.csv",
    "storage UUID casing",
  );
  const vendorSQL = Deno.readTextFileSync(
    new URL(
      "../../migrations/20260715080000_player_development_vendor_adapters.sql",
      import.meta.url,
    ),
  );
  assert(
    vendorSQL.includes("[0-9a-f]{12}\\.(csv|tsv)$"),
    "literal extension dot",
  );
  assert(
    !vendorSQL.includes("[0-9a-f]{12}\\\\.(csv|tsv)$"),
    "broken double slash removed",
  );
});

Deno.test("Rapsodo hitting preamble is preserved, detected, mapped, and dash values stay missing", () => {
  const parsed = parseImportText(
    fixture("rapsodo_hitting_sanitized.csv"),
    "csv",
  );
  const detection = detectProvider(parsed);
  equal(detection.exportType, "rapsodo_hitting", "hitting export");
  equal(detection.confidence, "high", "hitting confidence");
  equal(parsed.metadata.player_id, "fictional-player-101", "external ID");
  equal(parsed.metadata.player_name, "Avery Example", "player candidate");
  equal(parsed.sourceRowNumbers[0], 6, "original source row");
  equal(parsed.headers.length, 18, "exact hitting header");
  const exitIndex = parsed.headers.indexOf("ExitVelocity");
  equal(parsed.rows[1][exitIndex], "-", "source missing token retained");
  const mapping = recommendedMapping(parsed, detection, "America/New_York");
  assert(
    mapping?.wideMetrics?.some((item) =>
      item.metricKey === "hitting.exit_velocity"
    ) === true,
  );
  assert(
    !mapping?.wideMetrics?.some((item) =>
      item.metricKey === "hitting.max_exit_velocity"
    ),
  );
  assert(detection.protectedColumns.includes("SerialNumber"));
  assert(detection.unsupportedColumns.includes("Contact Depth"));
  equal(
    parseObservationDate(
      "Sun Jan 11 2026 1:55:34 PM",
      "RAPSODO",
      "America/New_York",
    ).toISOString(),
    "2026-01-11T18:55:34.000Z",
    "Rapsodo timezone",
  );
});

Deno.test("Rapsodo pitching excludes GPS/device fields and leaves movement semantics unsupported", () => {
  const parsed = parseImportText(
    fixture("rapsodo_pitching_sanitized.csv"),
    "csv",
  );
  const detection = detectProvider(parsed);
  equal(detection.exportType, "rapsodo_pitching", "pitching export");
  equal(detection.confidence, "high", "pitching confidence");
  equal(parsed.headers.length, 45, "exact pitching header");
  assert(detection.protectedColumns.includes("Device Serial Number"));
  assert(detection.protectedColumns.includes("SO - latitude"));
  assert(detection.unsupportedColumns.includes("VB (trajectory)"));
  const mapping = recommendedMapping(parsed, detection, "America/New_York");
  assert(
    mapping?.wideMetrics?.some((item) =>
      item.metricKey === "pitching.true_spin"
    ) === true,
  );
  assert(!mapping?.wideMetrics?.some((item) => item.column.startsWith("VB (")));
  assert(!mapping?.contextColumns?.some((item) => item.startsWith("SO -")));
});

Deno.test("validation persistence represents zero, warning, and rejected source rows without duplicate keys", () => {
  const accepted = buildPreview({
    parsed: parseDelimitedText(
      "player,date,metric,value,unit\nFictional Avery,2026-01-01,hitting.bat_speed,70,mph",
      "csv",
    ),
    provider: "generic_csv",
    mapping: longMapping,
    definitions,
    players,
    identities: [],
    now: new Date("2026-07-15"),
  });
  const acceptedPersistence = buildValidationPersistencePayload(
    accepted.rows,
    accepted.summary,
  );
  equal(acceptedPersistence.status, "ready", "accepted status");
  equal(acceptedPersistence.rowErrors.length, 0, "zero persisted errors");
  equal(
    acceptedPersistence.validationSummary.persistedRowErrors,
    0,
    "zero-error summary",
  );

  const warningMapping: ColumnMapping = {
    ...longMapping,
    columns: { ...longMapping.columns, sample_size: "sample" },
  };
  const warning = buildPreview({
    parsed: parseDelimitedText(
      "player,date,metric,value,unit,sample\nFictional Avery,2026-01-01,hitting.bat_speed,70,mph,0",
      "csv",
    ),
    provider: "generic_csv",
    mapping: warningMapping,
    definitions,
    players,
    identities: [],
    now: new Date("2026-07-15"),
  });
  const warningPersistence = buildValidationPersistencePayload(
    warning.rows,
    warning.summary,
  );
  equal(warningPersistence.rowErrors.length, 1, "warning persisted");
  equal(
    warningPersistence.rowErrors[0].acceptance_state,
    "warning",
    "warning state",
  );

  const rejected = buildPreview({
    parsed: parseDelimitedText(
      "player,date,bat_speed,exit_velocity\nUnknown Player,2026-01-01,70,90",
      "csv",
    ),
    provider: "generic_csv",
    mapping: {
      shape: "wide",
      timezone: "UTC",
      dateFormat: "ISO",
      columns: { player_name: "player", observation_date: "date" },
      wideMetrics: [
        {
          column: "bat_speed",
          metricKey: "hitting.bat_speed",
          sourceUnit: "mph",
        },
        {
          column: "exit_velocity",
          metricKey: "hitting.max_exit_velocity",
          sourceUnit: "mph",
        },
      ],
    },
    definitions,
    players,
    identities: [],
    now: new Date("2026-07-15"),
  });
  equal(rejected.rows.length, 2, "wide generated observations");
  const rejectedPersistence = buildValidationPersistencePayload(
    rejected.rows,
    rejected.summary,
  );
  equal(
    rejectedPersistence.rowErrors.length,
    1,
    "one error record per source row",
  );
  assert(
    rejectedPersistence.rowErrors[0].error_codes.includes("missing_player"),
    "merged missing-player error",
  );
});

Deno.test("Rapsodo hitting validation persistence aggregates source rows and excludes protected values", () => {
  const parsed = parseImportText(
    fixture("rapsodo_hitting_sanitized.csv"),
    "csv",
  );
  const detection = detectProvider(parsed);
  const mapping = recommendedMapping(parsed, detection, "America/New_York")!;
  const preview = buildPreview({
    parsed,
    provider: "rapsodo",
    mapping,
    definitions: persistenceDefinitions,
    players: [],
    identities: [],
    now: new Date("2026-07-15"),
  });
  const persistence = buildValidationPersistencePayload(
    preview.rows,
    preview.summary,
  );
  equal(persistence.status, "player_resolution_required", "hitting status");
  equal(
    persistence.rowErrors.length,
    new Set(preview.rows.map((row) => row.sourceRowNumber)).size,
    "hitting errors aggregated by source row",
  );
  const serialized = JSON.stringify(persistence);
  assert(!serialized.includes("SerialNumber"), "serial header excluded");
  assert(!serialized.includes("REDACTED-DEVICE"), "serial value excluded");
  assert(
    persistence.rowErrors.every((row) => row.source_row_number >= 2),
    "preamble source rows remain valid",
  );
});

Deno.test("Rapsodo pitching validation persistence excludes GPS, orientation, and ambiguous movement fields", () => {
  const parsed = parseImportText(
    fixture("rapsodo_pitching_sanitized.csv"),
    "csv",
  );
  const detection = detectProvider(parsed);
  const mapping = recommendedMapping(parsed, detection, "America/New_York")!;
  const preview = buildPreview({
    parsed,
    provider: "rapsodo",
    mapping,
    definitions: persistenceDefinitions,
    players: [],
    identities: [],
    now: new Date("2026-07-15"),
  });
  const persistence = buildValidationPersistencePayload(
    preview.rows,
    preview.summary,
  );
  equal(persistence.status, "player_resolution_required", "pitching status");
  equal(
    persistence.rowErrors.length,
    new Set(preview.rows.map((row) => row.sourceRowNumber)).size,
    "pitching errors aggregated by source row",
  );
  const serialized = JSON.stringify(persistence);
  for (
    const protectedText of [
      "Device Serial Number",
      "SO - latitude",
      "SO - longitude",
      "VB (trajectory)",
    ]
  ) {
    assert(!serialized.includes(protectedText), `${protectedText} excluded`);
  }
});

Deno.test("validation migration is service-only, fingerprint-locked, bounded, and transactional", () => {
  const sql = Deno.readTextFileSync(
    new URL(
      "../../migrations/20260715090000_player_development_import_validation_fix.sql",
      import.meta.url,
    ),
  ).toLowerCase();
  const validationStart = sql.indexOf(
    "create or replace function public.sd_persist_development_import_validation",
  );
  const validationEnd = sql.indexOf(
    "create or replace function public.sd_archive_development_import_job",
  );
  const validationSQL = sql.slice(validationStart, validationEnd);
  assert(validationStart >= 0 && validationEnd > validationStart, "RPC exists");
  for (
    const contract of [
      "security definer",
      "set search_path = ''",
      "for update",
      "p_expected_file_sha256",
      "p_expected_mapping_fingerprint",
      "p_expected_player_scope_fingerprint",
      "p_row_count is distinct from v_job.row_count",
      "jsonb_array_length(p_row_errors)",
      "v_row_error_count > 1000",
      "pg_column_size(p_row_errors) > 1048576",
      "delete from public.sd_development_import_row_errors",
      "insert into public.sd_development_import_row_errors",
      "update public.sd_development_import_jobs",
      "validation_summary_constraint_failed",
      "validation_transition_failed",
      "validation_scope_failed",
    ]
  ) {
    assert(validationSQL.includes(contract), `missing ${contract}`);
  }
  assert(
    !validationSQL.includes("insert into public.sd_player_metric_observations"),
    "validation never commits observations",
  );
  assert(
    sql.includes(
      "from public, anon, authenticated, service_role;\ngrant execute on function public.sd_persist_development_import_validation",
    ),
    "RPC execute reset before service grant",
  );
  assert(
    sql.includes(
      ") to service_role;\n\nrevoke all on function public.sd_archive_development_import_job",
    ),
    "validation RPC granted only to service role",
  );
  assert(!sql.includes("notification"), "migration sends no notifications");
  assert(!sql.includes("apns"), "migration sends no APNs events");
});

Deno.test("Edge validation uses the exact RPC contract and retains safe staged errors", () => {
  const edge = Deno.readTextFileSync(
    new URL("../player-development-imports/index.ts", import.meta.url),
  );
  const start = edge.indexOf("async function persistValidation");
  const end = edge.indexOf("async function handleAction", start);
  const persistence = edge.slice(start, end);
  for (
    const parameter of [
      "p_actor_id",
      "p_org_id",
      "p_job_id",
      "p_expected_file_sha256",
      "p_expected_mapping_fingerprint",
      "p_expected_player_scope_fingerprint",
      "p_row_count",
      "p_accepted_rows",
      "p_rejected_rows",
      "p_unmatched_player_rows",
      "p_ambiguous_player_rows",
      "p_warning_count",
      "p_validation_summary",
      "p_row_errors",
    ]
  ) {
    assert(persistence.includes(`${parameter}:`), `missing Edge ${parameter}`);
  }
  assert(
    persistence.includes('"sd_persist_development_import_validation"'),
    "validation uses RPC",
  );
  assert(
    !persistence.includes('.from("sd_development_import_row_errors")'),
    "validation no longer performs independent row-error writes",
  );
  assert(
    edge.includes("validation_row_error_replace_failed") &&
      edge.includes("validation_summary_constraint_failed") &&
      edge.includes("safeCode = inputChanged") &&
      edge.includes('"validation_input_changed"') &&
      edge.includes("request_id") && edge.includes("job_id"),
    "safe stage and correlation logging",
  );
});

Deno.test("TrackMan strong signature maps official fields and keeps VertBreak and pfx fields distinct", () => {
  const parsed = parseImportText(
    fixture("trackman_radar_sanitized.csv"),
    "csv",
  );
  const detection = detectProvider(parsed);
  equal(detection.exportType, "trackman_radar", "TrackMan export");
  equal(detection.confidence, "high", "TrackMan confidence");
  assert(detection.unsupportedColumns.includes("VertBreak"));
  assert(detection.unsupportedColumns.includes("pfxx"));
  const imperial = recommendedMapping(parsed, detection, "UTC", "imperial")!;
  const metric = recommendedMapping(parsed, detection, "UTC", "metric")!;
  equal(
    imperial.wideMetrics?.find((item) => item.column === "InducedVertBreak")
      ?.sourceUnit,
    "in",
    "imperial movement",
  );
  equal(
    metric.wideMetrics?.find((item) => item.column === "InducedVertBreak")
      ?.sourceUnit,
    "cm",
    "metric movement",
  );
  assert(
    !imperial.wideMetrics?.some((item) =>
      ["VertBreak", "pfxx", "pfxz"].includes(item.column)
    ),
  );
  equal(imperial.columns.pitcher_external_id, "PitcherId", "pitcher identity");
  equal(imperial.columns.batter_external_id, "BatterId", "batter identity");
});

Deno.test("common velocity and spin headers do not falsely detect TrackMan", () => {
  const parsed = parseDelimitedText(
    "Date,Velocity,SpinRate,Player\n2026-01-01,90,2200,A\n",
  );
  equal(detectProvider(parsed).exportType, "generic_csv", "generic fallback");
});

Deno.test("Rapsodo preamble rejects duplicate, conflicting, and missing table metadata", () => {
  throwsCode(
    () =>
      parseImportText(
        `"Player ID:",one\n"Player ID:",two\n"Player Name:",Example\nHitID,ExitVelocity,LaunchAngle,Unique ID\n1,90,10,u1\n`,
        "csv",
      ),
    "conflicting_provider_metadata",
  );
  throwsCode(
    () =>
      parseImportText(
        `"Player ID:",one\n"Player Name:",Example\nnot,a,valid,header\n`,
        "csv",
      ),
    "missing_provider_header",
  );
});

Deno.test("adapter version, unit system, and timezone change mapping identity", async () => {
  const parsed = parseImportText(
    fixture("trackman_radar_sanitized.csv"),
    "csv",
  );
  const detection = detectProvider(parsed);
  const imperial = recommendedMapping(parsed, detection, "UTC", "imperial")!;
  const metric = recommendedMapping(parsed, detection, "UTC", "metric")!;
  const eastern = recommendedMapping(
    parsed,
    detection,
    "America/New_York",
    "imperial",
  )!;
  const future = { ...imperial, adapterVersion: "trackman-radar.v2" };
  const fingerprints = await Promise.all(
    [imperial, metric, eastern, future].map(mappingFingerprint),
  );
  equal(new Set(fingerprints).size, 4, "assumption fingerprints");
});

Deno.test("materially changed Rapsodo signature and ambiguous dual signature fall back safely", () => {
  const changed = fixture("rapsodo_hitting_sanitized.csv").replace(
    "Unique ID",
    "Changed ID",
  );
  equal(
    detectProvider(parseImportText(changed, "csv")).confidence,
    "low",
    "changed fallback",
  );
  const ambiguous =
    `\n"Player ID:",fictional\n"Player Name:",Example Player\n\nNo,Date,HitID,ExitVelocity,LaunchAngle,Pitch ID,Pitch Type,Velocity,Total Spin,Unique ID\n1,2026-01-01,hit-1,90,12,pitch-1,Fastball,88,2200,unique-1\n`;
  const detection = detectProvider(parseImportText(ambiguous, "csv"));
  equal(detection.exportType, "generic_csv", "ambiguous fallback");
  assert(detection.warnings.includes("ambiguous_rapsodo_signature"));
});

Deno.test("migration enforces private scope, RLS, audit provenance, and no client writes", () => {
  const sql = Deno.readTextFileSync(
    new URL(
      "../../migrations/20260715070000_player_development_data_imports.sql",
      import.meta.url,
    ),
  ).toLowerCase();
  for (
    const table of [
      "sd_development_import_mapping_profiles",
      "sd_development_external_player_identities",
      "sd_development_import_row_errors",
    ]
  ) {
    assert(
      sql.includes(`alter table public.${table} enable row level security`),
      `${table} RLS`,
    );
  }
  assert(
    sql.includes("player-development-imports', false, 10485760"),
    "private 10 MB bucket",
  );
  assert(
    sql.includes(
      "public.sd_development_can_manage_player(j.org_id, j.player_id)",
    ),
    "storage access retains coach player scope",
  );
  assert(
    sql.includes(
      "revoke all on table public.sd_development_import_mapping_profiles",
    ),
    "no authenticated writes",
  );
  assert(sql.includes("device_imported_unverified"), "verification state");
  assert(
    sql.includes("original_unit") && sql.includes("canonical_unit"),
    "unit provenance",
  );
  assert(
    sql.includes(
      "unique index idx_sd_development_import_jobs_completed_file_mapping",
    ),
    "file idempotency",
  );
});

Deno.test("Edge Function authenticates every action and has no automatic report, alert, notification, or APNs calls", () => {
  const source = Deno.readTextFileSync(
    new URL("../player-development-imports/index.ts", import.meta.url),
  );
  assert(source.includes("userClient.auth.getUser()"), "JWT verification");
  assert(source.includes('["owner", "admin", "coach"]'), "staff roles");
  assert(source.includes("organization_staff_required"), "membership required");
  assert(
    !source.includes('.from("sd_platform_admins")'),
    "platform-only admin denied",
  );
  assert(!source.includes("generateDevelopment"), "no report generation call");
  assert(!source.includes("persistAlerts"), "no alert persistence call");
  assert(
    !source.includes('.from("sd_notification_deliveries")'),
    "no notification write",
  );
  assert(!source.includes("sendAPNS"), "no APNs send call");
  assert(source.includes("file_identity_changed"), "commit rehash");
  assert(source.includes("concurrent_commit"), "concurrent claim");
  for (
    const conflictCode of [
      "idempotency_key_conflict",
      "idempotent_import_already_started",
      "invalid_job_transition",
      "duplicate_file_reused",
      "job_not_ready",
    ]
  ) assert(source.includes(conflictCode), `${conflictCode} retained`);
  assert(
    source.includes('"archive_mapping"') &&
      source.includes("mapping_profile_not_found"),
    "organization-scoped mapping archival",
  );
});
