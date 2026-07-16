export const IMPORT_LIMITS = {
  maxFileBytes: 10 * 1024 * 1024,
  maxRows: 50_000,
  maxColumns: 250,
  maxLineCharacters: 256 * 1024,
  maxHeaderCharacters: 200,
  maxCellCharacters: 10_000,
  maxContextColumns: 20,
  maxContextValueCharacters: 500,
  maxContextMetadataCharacters: 1_000,
  maxGeneratedObservations: 50_000,
  maxPersistedRowErrors: 1_000,
  maxRequestBytes: 1024 * 1024,
  previewRows: 100,
  maxListRows: 200,
} as const;

export const IMPORT_PARSER_VERSION = "generic-csv.v1";
export const IMPORT_MAPPING_VERSION = "player-development-mapping.v1";

export const VENDOR_ADAPTER_VERSIONS = {
  rapsodo_hitting: "rapsodo-hitting.v1",
  rapsodo_pitching: "rapsodo-pitching.v1",
  trackman_radar: "trackman-radar.v1",
  generic_csv: IMPORT_PARSER_VERSION,
} as const;

export type ProviderKey =
  | "generic_csv"
  | "rapsodo"
  | "hittrax"
  | "trackman"
  | "blast"
  | "pocket_radar"
  | "strength_testing";

export type FileShape = "wide" | "long";
export type DetectedExportType = keyof typeof VENDOR_ADAPTER_VERSIONS;
export type DetectionConfidence = "high" | "medium" | "low";
export type ImportStatus =
  | "uploaded"
  | "inspecting"
  | "mapping_required"
  | "player_resolution_required"
  | "validating"
  | "ready"
  | "importing"
  | "completed"
  | "completed_with_errors"
  | "failed"
  | "archived";

export type ImportErrorCode =
  | "unsupported_file_type"
  | "file_too_large"
  | "unsupported_file_encoding"
  | "missing_header"
  | "ambiguous_delimiter"
  | "duplicate_header"
  | "column_limit_exceeded"
  | "row_limit_exceeded"
  | "row_too_large"
  | "cell_too_large"
  | "extra_columns"
  | "observation_limit_exceeded"
  | "malformed_csv"
  | "missing_player"
  | "ambiguous_player"
  | "inactive_player"
  | "missing_metric"
  | "unsupported_metric"
  | "deprecated_metric"
  | "missing_value"
  | "invalid_number"
  | "missing_unit"
  | "unsupported_unit"
  | "unit_conflict"
  | "missing_date"
  | "ambiguous_date"
  | "future_date"
  | "duplicate_source_row"
  | "duplicate_existing_observation";

export class ImportRequestError extends Error {
  constructor(
    public status: number,
    public code: string,
    public safeMessage: string,
    public internalStage?: string,
    public postgresCode?: string,
    public postgrestStatus?: number,
  ) {
    super(code);
  }
}

export type ProviderAdapter = {
  providerKey: ProviderKey;
  parserVersion: string;
  productionActive: boolean;
  recognizedFileSignatures: string[];
  headerAliases: Record<string, string[]>;
  dateAliases: string[];
  playerIdentifierAliases: Record<string, string[]>;
  metricAliases: Record<string, string>;
  defaultUnitHints: Record<string, string>;
  contextFieldAliases: Record<string, string[]>;
  fixtureRequirements: string[];
};

const inactive = (
  providerKey: Exclude<ProviderKey, "generic_csv">,
): ProviderAdapter => ({
  providerKey,
  parserVersion: `${providerKey}.disabled-until-fixtures`,
  productionActive: false,
  recognizedFileSignatures: [],
  headerAliases: {},
  dateAliases: [],
  playerIdentifierAliases: {},
  metricAliases: {},
  defaultUnitHints: {},
  contextFieldAliases: {},
  fixtureRequirements: [
    "A sanitized real export with unchanged headers and representative rows",
  ],
});

export const PROVIDER_ADAPTERS: Record<ProviderKey, ProviderAdapter> = {
  generic_csv: {
    providerKey: "generic_csv",
    parserVersion: IMPORT_PARSER_VERSION,
    productionActive: true,
    recognizedFileSignatures: ["utf8-comma-delimited", "utf8-tab-delimited"],
    headerAliases: {},
    dateAliases: [],
    playerIdentifierAliases: {},
    metricAliases: {},
    defaultUnitHints: {},
    contextFieldAliases: {},
    fixtureRequirements: [],
  },
  rapsodo: {
    providerKey: "rapsodo",
    parserVersion: "rapsodo-auto.v1",
    productionActive: true,
    recognizedFileSignatures: ["rapsodo-hitting.v1", "rapsodo-pitching.v1"],
    headerAliases: {},
    dateAliases: ["Date"],
    playerIdentifierAliases: {
      external: ["Player ID:"],
      name: ["Player Name:"],
    },
    metricAliases: {},
    defaultUnitHints: {},
    contextFieldAliases: {},
    fixtureRequirements: [],
  },
  hittrax: inactive("hittrax"),
  trackman: {
    providerKey: "trackman",
    parserVersion: VENDOR_ADAPTER_VERSIONS.trackman_radar,
    productionActive: true,
    recognizedFileSignatures: ["trackman-radar.v1"],
    headerAliases: {},
    dateAliases: ["UTCDateTime", "LocalDateTime", "Date"],
    playerIdentifierAliases: {
      pitcher: ["PitcherId", "Pitcher"],
      batter: ["BatterId", "Batter"],
    },
    metricAliases: {},
    defaultUnitHints: {},
    contextFieldAliases: {},
    fixtureRequirements: [],
  },
  blast: inactive("blast"),
  pocket_radar: inactive("pocket_radar"),
  strength_testing: inactive("strength_testing"),
};

export type ParsedDelimitedFile = {
  fileType: "csv" | "tsv";
  delimiter: "," | "\t";
  headers: string[];
  normalizedHeaders: string[];
  rows: string[][];
  totalRows: number;
  blankRows: number;
  warnings: string[];
  sourceRowNumbers: number[];
  metadata: Record<string, string>;
  missingValueTokens: string[];
};

export type ProviderDetection = {
  providerKey: "generic_csv" | "rapsodo" | "trackman";
  exportType: DetectedExportType;
  adapterVersion: string;
  confidence: DetectionConfidence;
  matchedRequiredSignatures: string[];
  matchedOptionalSignatures: string[];
  missingSignatures: string[];
  warnings: string[];
  automaticMappingSafe: boolean;
  protectedColumns: string[];
  unsupportedColumns: string[];
  providerPlayerId: string | null;
  providerPlayerName: string | null;
};

export function normalizeHeader(value: string): string {
  return value.replace(/^\uFEFF/, "").trim().toLocaleLowerCase("en-US")
    .normalize("NFKD").replace(/[\u0300-\u036f]/g, "")
    .replace(/[^a-z0-9]+/g, "_").replace(/^_+|_+$/g, "");
}

export function normalizeIdentity(value: string): string {
  return value.trim().toLocaleLowerCase("en-US").normalize("NFKD")
    .replace(/[\u0300-\u036f]/g, "").replace(/[^a-z0-9]+/g, " ")
    .trim().replace(/\s+/g, " ");
}

export function normalizeExternalID(value: string): string {
  return value.trim().toLocaleLowerCase("en-US");
}

export function normalizeUsername(value: string): string {
  return value.trim().toLocaleLowerCase("en-US");
}

export function buildImportStoragePath(
  organizationId: string,
  jobId: string,
  objectId: string,
  fileType: "csv" | "tsv",
): string {
  return `${organizationId.toLowerCase()}/${jobId.toLowerCase()}/${objectId.toLowerCase()}.${fileType}`;
}

function delimiterCounts(line: string): { comma: number; tab: number } {
  let comma = 0;
  let tab = 0;
  let quoted = false;
  for (let i = 0; i < line.length; i++) {
    if (line[i] === '"') {
      if (quoted && line[i + 1] === '"') i++;
      else quoted = !quoted;
    } else if (!quoted && line[i] === ",") comma++;
    else if (!quoted && line[i] === "\t") tab++;
  }
  return { comma, tab };
}

export function detectDelimiter(text: string): "," | "\t" {
  const firstNonBlank = text.split(/\r?\n/, 20).find((line) =>
    line.trim().length > 0
  );
  if (!firstNonBlank) {
    throw new ImportRequestError(
      400,
      "missing_header",
      "The file has no header row.",
    );
  }
  const counts = delimiterCounts(firstNonBlank);
  if (counts.comma > 0 && counts.comma === counts.tab) {
    throw new ImportRequestError(
      400,
      "ambiguous_delimiter",
      "The header contains equally plausible comma and tab delimiters.",
    );
  }
  if (counts.tab > counts.comma && counts.tab > 0) return "\t";
  if (counts.comma > 0) return ",";
  throw new ImportRequestError(
    400,
    "missing_header",
    "The header must contain comma- or tab-separated columns.",
  );
}

export function decodeImportFile(bytes: Uint8Array): string {
  if (bytes.byteLength > IMPORT_LIMITS.maxFileBytes) {
    throw new ImportRequestError(
      413,
      "file_too_large",
      "CSV and TSV files must be 10 MB or smaller.",
    );
  }
  try {
    const text = new TextDecoder("utf-8", { fatal: true }).decode(bytes);
    if (text.includes("\0")) throw new Error("nul");
    return text.replace(/^\uFEFF/, "");
  } catch {
    throw new ImportRequestError(
      400,
      "unsupported_file_encoding",
      "Export the file as UTF-8 CSV or TSV and try again.",
    );
  }
}

export function parseDelimitedText(
  text: string,
  extension?: string,
): ParsedDelimitedFile {
  const delimiter = detectDelimiter(text);
  if (extension && !["csv", "tsv"].includes(extension.toLowerCase())) {
    throw new ImportRequestError(
      400,
      "unsupported_file_type",
      "Export spreadsheet files as CSV or TSV.",
    );
  }
  const rows: string[][] = [];
  let row: string[] = [];
  let field = "";
  let quoted = false;
  let quotedFieldClosed = false;
  let lineCharacters = 0;
  let blankRows = 0;
  const finishField = () => {
    if (field.length > IMPORT_LIMITS.maxCellCharacters) {
      throw new ImportRequestError(
        400,
        "cell_too_large",
        "A cell exceeds the supported length.",
      );
    }
    row.push(field);
    field = "";
    quotedFieldClosed = false;
    if (row.length > IMPORT_LIMITS.maxColumns) {
      throw new ImportRequestError(
        400,
        "column_limit_exceeded",
        "Files may contain at most 250 columns.",
      );
    }
  };
  const finishRow = () => {
    finishField();
    if (row.every((cell) => cell.trim() === "")) blankRows++;
    else rows.push(row);
    row = [];
    lineCharacters = 0;
    if (rows.length > IMPORT_LIMITS.maxRows + 1) {
      throw new ImportRequestError(
        400,
        "row_limit_exceeded",
        "Files may contain at most 50,000 data rows.",
      );
    }
  };
  for (let i = 0; i < text.length; i++) {
    const char = text[i];
    lineCharacters++;
    if (lineCharacters > IMPORT_LIMITS.maxLineCharacters) {
      throw new ImportRequestError(
        400,
        "row_too_large",
        "A row exceeds the supported length.",
      );
    }
    if (quoted) {
      if (char === '"') {
        if (text[i + 1] === '"') {
          field += '"';
          i++;
        } else {
          quoted = false;
          quotedFieldClosed = true;
        }
      } else field += char;
    } else if (quotedFieldClosed) {
      if (char === delimiter) finishField();
      else if (char === "\n") finishRow();
      else if (char !== "\r") {
        throw new ImportRequestError(
          400,
          "malformed_csv",
          "A quoted value contains characters after its closing quote.",
        );
      }
    } else if (char === '"' && field.length === 0) quoted = true;
    else if (char === '"') {
      throw new ImportRequestError(
        400,
        "malformed_csv",
        "Quotes inside unquoted values must be escaped.",
      );
    } else if (char === delimiter) finishField();
    else if (char === "\n") finishRow();
    else if (char !== "\r") field += char;
  }
  if (quoted) {
    throw new ImportRequestError(
      400,
      "malformed_csv",
      "The file contains an unterminated quoted value.",
    );
  }
  if (field.length > 0 || row.length > 0) finishRow();
  if (rows.length < 1) {
    throw new ImportRequestError(
      400,
      "missing_header",
      "The file has no header row.",
    );
  }
  const headers = rows.shift()!.map((header) => header.trim());
  if (
    headers.length < 2 ||
    headers.some((header) =>
      !header || header.length > IMPORT_LIMITS.maxHeaderCharacters ||
      !normalizeHeader(header)
    )
  ) {
    throw new ImportRequestError(
      400,
      "missing_header",
      "Every column must have a non-empty header.",
    );
  }
  const normalizedHeaders = headers.map(normalizeHeader);
  const duplicate = normalizedHeaders.find((header, index) =>
    normalizedHeaders.indexOf(header) !== index
  );
  if (duplicate) {
    throw new ImportRequestError(
      400,
      "duplicate_header",
      `Rename the duplicate column '${duplicate}' before importing.`,
    );
  }
  for (const dataRow of rows) {
    if (dataRow.length > headers.length) {
      throw new ImportRequestError(
        400,
        "extra_columns",
        "A data row contains more columns than the header.",
      );
    }
    while (dataRow.length < headers.length) dataRow.push("");
  }
  return {
    fileType: delimiter === "\t" ? "tsv" : "csv",
    delimiter,
    headers,
    normalizedHeaders,
    rows,
    totalRows: rows.length,
    blankRows,
    warnings: blankRows ? ["blank_rows_ignored"] : [],
    sourceRowNumbers: rows.map((_, index) => index + 2),
    metadata: {},
    missingValueTokens: [],
  };
}

const RAPSODO_PREAMBLE_LINES = 20;
const RAPSODO_METADATA_KEYS: Record<string, string> = {
  "player id:": "player_id",
  "player name:": "player_name",
};

function parseBoundedCSVLine(line: string): string[] {
  const values: string[] = [];
  let value = "";
  let quoted = false;
  for (let index = 0; index < line.length; index++) {
    const character = line[index];
    if (character === '"') {
      if (quoted && line[index + 1] === '"') {
        value += '"';
        index++;
      } else quoted = !quoted;
    } else if (character === "," && !quoted) {
      values.push(value.trim());
      value = "";
    } else value += character;
  }
  if (quoted) {
    throw new ImportRequestError(
      400,
      "malformed_csv",
      "The metadata preamble contains an unterminated quoted value.",
    );
  }
  values.push(value.trim());
  return values;
}

export function parseImportText(
  text: string,
  extension?: string,
): ParsedDelimitedFile {
  const physicalLines = text.split(/\r?\n/);
  const metadata: Record<string, string> = {};
  let recognizedMetadata = 0;
  let headerLineIndex = -1;
  for (
    let index = 0;
    index < Math.min(physicalLines.length, RAPSODO_PREAMBLE_LINES);
    index++
  ) {
    const line = physicalLines[index];
    if (line.length > IMPORT_LIMITS.maxLineCharacters) {
      throw new ImportRequestError(
        400,
        "row_too_large",
        "A preamble row exceeds the supported length.",
      );
    }
    const cells = parseBoundedCSVLine(line);
    const metadataKey =
      RAPSODO_METADATA_KEYS[cells[0]?.trim().toLocaleLowerCase("en-US")];
    if (metadataKey) {
      recognizedMetadata++;
      const boundedValue = (cells[1] ?? "").trim();
      if (!boundedValue || boundedValue.length > 200 || cells.length > 2) {
        throw new ImportRequestError(
          400,
          "invalid_provider_metadata",
          "The Rapsodo metadata preamble is invalid.",
        );
      }
      if (metadata[metadataKey] !== undefined) {
        throw new ImportRequestError(
          400,
          metadata[metadataKey] === boundedValue
            ? "duplicate_provider_metadata"
            : "conflicting_provider_metadata",
          "The Rapsodo metadata preamble contains duplicate or conflicting player fields.",
        );
      }
      metadata[metadataKey] = boundedValue;
      continue;
    }
    const normalized = cells.map(normalizeHeader);
    const hittingHeader = normalized.includes("hitid") &&
      normalized.includes("exitvelocity");
    const pitchingHeader = normalized.includes("pitch_id") &&
      normalized.includes("velocity");
    if (recognizedMetadata > 0 && (hittingHeader || pitchingHeader)) {
      headerLineIndex = index;
      break;
    }
  }
  if (recognizedMetadata > 0) {
    if (
      metadata.player_id === undefined || metadata.player_name === undefined ||
      headerLineIndex < 0
    ) {
      throw new ImportRequestError(
        400,
        "missing_provider_header",
        "The Rapsodo preamble or table header is incomplete.",
      );
    }
    const parsed = parseDelimitedText(
      physicalLines.slice(headerLineIndex).join("\n"),
      extension,
    );
    parsed.sourceRowNumbers = parsed.rows.map((_, index) =>
      headerLineIndex + index + 2
    );
    parsed.metadata = metadata;
    parsed.missingValueTokens = ["-"];
    return parsed;
  }
  return parseDelimitedText(text, extension);
}

function signaturesPresent(
  headers: Set<string>,
  signatures: string[],
): string[] {
  return signatures.filter((signature) =>
    headers.has(normalizeHeader(signature))
  );
}

export function detectProvider(parsed: ParsedDelimitedFile): ProviderDetection {
  const headers = new Set(parsed.normalizedHeaders);
  const hasPreamble = Boolean(
    parsed.metadata.player_id && parsed.metadata.player_name,
  );
  const hittingRequired = ["HitID", "ExitVelocity", "LaunchAngle", "Unique ID"];
  const pitchingRequired = [
    "Pitch ID",
    "Pitch Type",
    "Velocity",
    "Total Spin",
    "Unique ID",
  ];
  const hittingMatched = signaturesPresent(headers, hittingRequired);
  const pitchingMatched = signaturesPresent(headers, pitchingRequired);
  const hittingComplete = hasPreamble &&
    hittingMatched.length === hittingRequired.length;
  const pitchingComplete = hasPreamble &&
    pitchingMatched.length === pitchingRequired.length;
  if (hittingComplete && pitchingComplete) {
    return genericDetection(["ambiguous_rapsodo_signature"]);
  }
  if (hittingComplete) {
    const optional = [
      "PitchBallVelocity",
      "Distance",
      "StrikeZoneX",
      "StrikeZoneY",
      "Contact Depth",
      "SerialNumber",
      "Session Name",
    ];
    return {
      providerKey: "rapsodo",
      exportType: "rapsodo_hitting",
      adapterVersion: VENDOR_ADAPTER_VERSIONS.rapsodo_hitting,
      confidence: "high",
      matchedRequiredSignatures: [
        "Player ID:",
        "Player Name:",
        ...hittingMatched,
      ],
      matchedOptionalSignatures: signaturesPresent(headers, optional),
      missingSignatures: [],
      warnings: ["timezone_confirmation_required"],
      automaticMappingSafe: true,
      protectedColumns: signaturesPresent(headers, [
        "SerialNumber",
        "Unique ID",
      ]),
      unsupportedColumns: signaturesPresent(headers, [
        "StrikeZoneX",
        "StrikeZoneY",
        "Contact Depth",
        "SpinDirection",
        "SpinConfidence",
      ]),
      providerPlayerId: parsed.metadata.player_id,
      providerPlayerName: parsed.metadata.player_name,
    };
  }
  if (pitchingComplete) {
    const optional = [
      "True Spin (release)",
      "Spin Efficiency (release)",
      "Release Height",
      "Release Side",
      "Horizontal Approach Angle",
      "Vertical Approach Angle",
      "Release Extension (ft)",
    ];
    const protectedColumns = parsed.headers.filter((header) => {
      const normalized = normalizeHeader(header);
      return normalized === "device_serial_number" ||
        normalized === "unique_id" || normalized.startsWith("so_");
    });
    return {
      providerKey: "rapsodo",
      exportType: "rapsodo_pitching",
      adapterVersion: VENDOR_ADAPTER_VERSIONS.rapsodo_pitching,
      confidence: "high",
      matchedRequiredSignatures: [
        "Player ID:",
        "Player Name:",
        ...pitchingMatched,
      ],
      matchedOptionalSignatures: signaturesPresent(headers, optional),
      missingSignatures: [],
      warnings: [
        "timezone_confirmation_required",
        "sensitive_device_and_location_fields_excluded",
      ],
      automaticMappingSafe: true,
      protectedColumns,
      unsupportedColumns: signaturesPresent(headers, [
        "Strike Zone Side",
        "Strike Zone Height",
        "VB (trajectory)",
        "HB (trajectory)",
        "SSW VB",
        "SSW HB",
        "VB (spin)",
        "HB (spin)",
      ]),
      providerPlayerId: parsed.metadata.player_id,
      providerPlayerName: parsed.metadata.player_name,
    };
  }

  const trackmanRequiredGroups = [
    ["PitchNo"],
    ["PitchUID"],
    ["Pitcher", "PitcherId"],
    ["TaggedPitchType", "AutoPitchType"],
  ];
  const groupMatches = trackmanRequiredGroups.map((group) =>
    signaturesPresent(headers, group)
  );
  const trackmanMetrics = signaturesPresent(headers, [
    "RelSpeed",
    "SpinRate",
    "RelHeight",
    "Extension",
  ]);
  const trackmanComplete =
    groupMatches.every((matches) => matches.length > 0) &&
    trackmanMetrics.length >= 3;
  const trackmanEvidence =
    groupMatches.filter((matches) => matches.length > 0).length +
    trackmanMetrics.length;
  if (trackmanComplete) {
    const supported = [
      "RelSpeed",
      "SpinRate",
      "RelHeight",
      "RelSide",
      "Extension",
      "InducedVertBreak",
      "HorzBreak",
      "PlateLocHeight",
      "PlateLocSide",
      "ZoneSpeed",
      "VertApprAngle",
      "HorzApprAngle",
      "ExitSpeed",
      "Angle",
      "Direction",
      "HitSpinRate",
      "Distance",
    ];
    return {
      providerKey: "trackman",
      exportType: "trackman_radar",
      adapterVersion: VENDOR_ADAPTER_VERSIONS.trackman_radar,
      confidence: "high",
      matchedRequiredSignatures: [...groupMatches.flat(), ...trackmanMetrics],
      matchedOptionalSignatures: signaturesPresent(headers, [
        "Batter",
        "BatterId",
        ...supported,
      ]),
      missingSignatures: [],
      warnings: ["unit_system_confirmation_required"],
      automaticMappingSafe: true,
      protectedColumns: signaturesPresent(headers, [
        "PitchUID",
        "GameUID",
        "PlayID",
      ]),
      unsupportedColumns: signaturesPresent(headers, [
        "VertBreak",
        "pfxx",
        "pfxz",
      ]),
      providerPlayerId: null,
      providerPlayerName: null,
    };
  }
  if (trackmanEvidence >= 5 && headers.has("pitchuid")) {
    const missing = trackmanRequiredGroups.filter((_, index) =>
      groupMatches[index].length === 0
    ).flat();
    if (trackmanMetrics.length < 3) {
      missing.push("three_of_RelSpeed_SpinRate_RelHeight_Extension");
    }
    return {
      ...genericDetection(["trackman_schema_confirmation_required"]),
      providerKey: "trackman",
      exportType: "trackman_radar",
      adapterVersion: VENDOR_ADAPTER_VERSIONS.trackman_radar,
      confidence: "medium",
      matchedRequiredSignatures: [...groupMatches.flat(), ...trackmanMetrics],
      missingSignatures: missing,
    };
  }
  return genericDetection(
    hasPreamble ? ["materially_changed_rapsodo_schema"] : [],
  );
}

function genericDetection(warnings: string[]): ProviderDetection {
  return {
    providerKey: "generic_csv",
    exportType: "generic_csv",
    adapterVersion: VENDOR_ADAPTER_VERSIONS.generic_csv,
    confidence: "low",
    matchedRequiredSignatures: [],
    matchedOptionalSignatures: [],
    missingSignatures: [],
    warnings,
    automaticMappingSafe: false,
    protectedColumns: [],
    unsupportedColumns: [],
    providerPlayerId: null,
    providerPlayerName: null,
  };
}

export async function sha256Hex(value: Uint8Array | string): Promise<string> {
  const bytes = typeof value === "string"
    ? new TextEncoder().encode(value)
    : value;
  const digest = await crypto.subtle.digest(
    "SHA-256",
    Uint8Array.from(bytes).buffer,
  );
  return [...new Uint8Array(digest)].map((byte) =>
    byte.toString(16).padStart(2, "0")
  ).join("");
}

export async function headerFingerprint(headers: string[]): Promise<string> {
  return await sha256Hex(headers.map(normalizeHeader).join("\u001f"));
}

export type MetricDefinition = {
  id: string;
  canonical_key: string;
  display_name: string;
  category: string;
  canonical_unit: string | null;
  preferred_direction: string;
  minimum_sample_size: number;
  status: "active" | "deprecated";
};

export type PlayerCandidate = {
  id: string;
  fullName: string;
  username?: string | null;
  active: boolean;
};

export type ExternalIdentity = {
  provider: string;
  externalPlayerId: string;
  playerId: string;
};

export type ColumnMapping = {
  shape: FileShape;
  timezone: string;
  dateFormat?: "ISO" | "MM/DD/YYYY" | "RAPSODO";
  adapterVersion?: string;
  detectedExportType?: DetectedExportType;
  unitSystem?: "imperial" | "metric";
  columns: Partial<
    Record<
      | "player_external_id"
      | "player_name"
      | "player_username"
      | "player_email"
      | "pitcher_external_id"
      | "pitcher_name"
      | "batter_external_id"
      | "batter_name"
      | "birth_year"
      | "observation_date"
      | "observation_timestamp"
      | "metric"
      | "value"
      | "unit"
      | "sample_size"
      | "session_identifier"
      | "source_event_id"
      | "pitch_type"
      | "swing_type"
      | "team",
      string
    >
  >;
  wideMetrics?: Array<
    { column: string; metricKey: string; sourceUnit?: string }
  >;
  longMetricKeys?: Record<string, string>;
  longSourceUnits?: Record<string, string>;
  contextColumns?: string[];
  playerResolutions?: Record<string, string>;
};

const AUTO_METRICS: Record<
  DetectedExportType,
  Array<[string, string, string, string?]>
> = {
  generic_csv: [],
  rapsodo_hitting: [
    ["ExitVelocity", "hitting.exit_velocity", "mph"],
    ["PitchBallVelocity", "hitting.pitch_velocity_seen", "mph"],
    ["LaunchAngle", "hitting.launch_angle", "deg"],
    ["ExitDirection", "hitting.exit_direction", "deg"],
    ["Spin", "hitting.batted_ball_spin_rate", "rpm"],
    ["Distance", "hitting.distance", "ft"],
  ],
  rapsodo_pitching: [
    ["Velocity", "pitching.velocity", "mph"],
    ["Total Spin", "pitching.spin_rate", "rpm"],
    ["True Spin (release)", "pitching.true_spin", "rpm"],
    ["Spin Efficiency (release)", "pitching.spin_efficiency", "percent"],
    ["Release Height", "pitching.release_height", "ft"],
    ["Release Side", "pitching.release_side", "ft"],
    ["Horizontal Approach Angle", "pitching.horizontal_approach_angle", "deg"],
    ["Vertical Approach Angle", "pitching.vertical_approach_angle", "deg"],
    ["Release Extension (ft)", "pitching.extension", "ft"],
  ],
  trackman_radar: [
    ["RelSpeed", "pitching.velocity", "velocity"],
    ["SpinRate", "pitching.spin_rate", "rpm"],
    ["RelHeight", "pitching.release_height", "distance"],
    ["RelSide", "pitching.release_side", "distance"],
    ["Extension", "pitching.extension", "distance"],
    ["InducedVertBreak", "pitching.induced_vertical_break", "movement"],
    ["HorzBreak", "pitching.horizontal_break", "movement"],
    ["PlateLocHeight", "pitching.plate_location_height", "distance"],
    ["PlateLocSide", "pitching.plate_location_side", "distance"],
    ["ZoneSpeed", "pitching.zone_velocity", "velocity"],
    ["VertApprAngle", "pitching.vertical_approach_angle", "deg"],
    ["HorzApprAngle", "pitching.horizontal_approach_angle", "deg"],
    ["ExitSpeed", "hitting.exit_velocity", "velocity"],
    ["Angle", "hitting.launch_angle", "deg"],
    ["Direction", "hitting.exit_direction", "deg"],
    ["HitSpinRate", "hitting.batted_ball_spin_rate", "rpm"],
    ["Distance", "hitting.distance", "distance"],
  ],
};

export function recommendedMapping(
  parsed: ParsedDelimitedFile,
  detection: ProviderDetection,
  timezone: string,
  unitSystem?: "imperial" | "metric",
): ColumnMapping | null {
  if (!detection.automaticMappingSafe) return null;
  const has = (header: string) =>
    parsed.normalizedHeaders.includes(normalizeHeader(header));
  const trackmanUnit = (kind: string): string => {
    if (kind === "velocity") return unitSystem === "metric" ? "km/h" : "mph";
    if (kind === "distance") return unitSystem === "metric" ? "m" : "ft";
    if (kind === "movement") return unitSystem === "metric" ? "cm" : "in";
    return kind;
  };
  const metrics = AUTO_METRICS[detection.exportType]
    .filter(([header]) => has(header))
    .map(([column, metricKey, sourceUnit]) => ({
      column,
      metricKey,
      sourceUnit: detection.exportType === "trackman_radar"
        ? trackmanUnit(sourceUnit)
        : sourceUnit,
    }));
  const columns: ColumnMapping["columns"] = {};
  if (detection.providerKey === "rapsodo") {
    columns.player_external_id = "__provider_player_id";
    columns.player_name = "__provider_player_name";
    columns.observation_timestamp = "Date";
    columns.source_event_id = detection.exportType === "rapsodo_hitting"
      ? "HitID"
      : "Pitch ID";
  } else {
    columns.pitcher_external_id = has("PitcherId") ? "PitcherId" : undefined;
    columns.pitcher_name = has("Pitcher") ? "Pitcher" : undefined;
    columns.batter_external_id = has("BatterId") ? "BatterId" : undefined;
    columns.batter_name = has("Batter") ? "Batter" : undefined;
    columns.observation_timestamp = has("UTCDateTime")
      ? "UTCDateTime"
      : has("LocalDateTime")
      ? "LocalDateTime"
      : "Date";
    columns.source_event_id = "PitchUID";
  }
  const contextColumns = detection.exportType === "rapsodo_hitting"
    ? ["Session Name", "BatName"].filter(has)
    : detection.exportType === "rapsodo_pitching"
    ? ["Pitch Type", "Intent Type", "Session Name"].filter(has)
    : ["TaggedPitchType", "AutoPitchType"].filter(has);
  return {
    shape: "wide",
    timezone,
    dateFormat: detection.providerKey === "rapsodo" ? "RAPSODO" : "ISO",
    adapterVersion: detection.adapterVersion,
    detectedExportType: detection.exportType,
    unitSystem,
    columns,
    wideMetrics: metrics,
    contextColumns,
  };
}

type UnitDef = { dimension: string; scale: number; aliases: string[] };
const UNIT_DEFS: Record<string, UnitDef> = {
  mph: {
    dimension: "velocity",
    scale: 1,
    aliases: ["mph", "mi/h", "miles per hour"],
  },
  "km/h": {
    dimension: "velocity",
    scale: 0.6213711922,
    aliases: ["km/h", "kph", "kmh"],
  },
  lb: {
    dimension: "mass",
    scale: 1,
    aliases: ["lb", "lbs", "pound", "pounds"],
  },
  kg: {
    dimension: "mass",
    scale: 2.2046226218,
    aliases: ["kg", "kilogram", "kilograms"],
  },
  in: { dimension: "distance", scale: 1, aliases: ["in", "inch", "inches"] },
  cm: {
    dimension: "distance",
    scale: 0.3937007874,
    aliases: ["cm", "centimeter", "centimeters"],
  },
  ft: { dimension: "distance", scale: 12, aliases: ["ft", "foot", "feet"] },
  m: {
    dimension: "distance",
    scale: 39.37007874,
    aliases: ["m", "meter", "meters"],
  },
  s: {
    dimension: "time",
    scale: 1,
    aliases: ["s", "sec", "second", "seconds"],
  },
  ms: {
    dimension: "time",
    scale: 0.001,
    aliases: ["ms", "millisecond", "milliseconds"],
  },
  deg: {
    dimension: "angle",
    scale: 1,
    aliases: ["deg", "degree", "degrees", "°"],
  },
  rpm: { dimension: "rotation", scale: 1, aliases: ["rpm", "rev/min"] },
  percent: {
    dimension: "ratio",
    scale: 0.01,
    aliases: ["%", "percent", "percentage", "pct"],
  },
  decimal: { dimension: "ratio", scale: 1, aliases: ["decimal", "ratio"] },
};

function canonicalUnit(value: string): string | null {
  const normalized = value.trim().toLocaleLowerCase("en-US");
  for (const [unit, definition] of Object.entries(UNIT_DEFS)) {
    if (definition.aliases.includes(normalized)) return unit;
  }
  return null;
}

export type ConversionResult = {
  normalizedValue: number;
  canonicalUnit: string | null;
  rule: string;
  version: "unit-registry.v1";
};

export function convertUnit(
  value: number,
  sourceUnit: string,
  targetUnit: string | null,
): ConversionResult {
  if (targetUnit === null) {
    if (sourceUnit.trim() !== "") {
      throw new ImportRequestError(
        400,
        "unit_conflict",
        "A unit cannot be applied to this unitless metric.",
      );
    }
    return {
      normalizedValue: value,
      canonicalUnit: null,
      rule: "identity-unitless",
      version: "unit-registry.v1",
    };
  }
  const source = canonicalUnit(sourceUnit);
  const target = canonicalUnit(targetUnit);
  if (!source) {
    throw new ImportRequestError(
      400,
      "unsupported_unit",
      `The source unit '${sourceUnit}' is not supported.`,
    );
  }
  if (!target) {
    throw new ImportRequestError(
      400,
      "unsupported_unit",
      "The canonical metric unit is not supported by this parser version.",
    );
  }
  const from = UNIT_DEFS[source];
  const to = UNIT_DEFS[target];
  if (from.dimension !== to.dimension) {
    throw new ImportRequestError(
      400,
      "unit_conflict",
      `The source unit '${sourceUnit}' cannot be converted to '${targetUnit}'.`,
    );
  }
  return {
    normalizedValue: value * from.scale / to.scale,
    canonicalUnit: target,
    rule: source === target ? `identity:${source}` : `${source}->${target}`,
    version: "unit-registry.v1",
  };
}

export function parseObservationDate(
  source: string,
  format: ColumnMapping["dateFormat"],
  timezone = "UTC",
  now = new Date(),
): Date {
  const value = source.trim();
  if (!value) {
    throw new ImportRequestError(
      400,
      "missing_date",
      "An observation date is required.",
    );
  }
  let date: Date | null = null;
  const localDateTime = (
    year: number,
    month: number,
    day: number,
    hour: number,
    minute: number,
    second: number,
  ): Date | null => {
    try {
      const formatter = new Intl.DateTimeFormat("en-US", {
        timeZone: timezone,
        year: "numeric",
        month: "2-digit",
        day: "2-digit",
        hour: "2-digit",
        minute: "2-digit",
        second: "2-digit",
        hourCycle: "h23",
      });
      const requestedWallClock = Date.UTC(
        year,
        month - 1,
        day,
        hour,
        minute,
        second,
      );
      let timestamp = requestedWallClock;
      for (let attempt = 0; attempt < 3; attempt++) {
        const parts = Object.fromEntries(
          formatter.formatToParts(new Date(timestamp)).map((part) => [
            part.type,
            part.value,
          ]),
        );
        const displayed = Date.UTC(
          Number(parts.year),
          Number(parts.month) - 1,
          Number(parts.day),
          Number(parts.hour),
          Number(parts.minute),
          Number(parts.second),
        );
        timestamp += requestedWallClock - displayed;
      }
      const result = new Date(timestamp);
      const check = Object.fromEntries(
        formatter.formatToParts(result).map((part) => [part.type, part.value]),
      );
      return Number(check.year) === year && Number(check.month) === month &&
          Number(check.day) === day && Number(check.hour) === hour &&
          Number(check.minute) === minute && Number(check.second) === second
        ? result
        : null;
    } catch {
      return null;
    }
  };
  const localNoon = (year: number, month: number, day: number): Date | null =>
    localDateTime(year, month, day, 12, 0, 0);
  if (/^\d{4}-\d{2}-\d{2}$/.test(value)) {
    const [year, month, day] = value.split("-").map(Number);
    date = localNoon(year, month, day);
  } else if (/^\d{4}-\d{2}-\d{2}T/.test(value)) {
    if (!/(Z|[+-]\d{2}:?\d{2})$/.test(value)) {
      throw new ImportRequestError(
        400,
        "ambiguous_date",
        "Timestamps require a time zone or offset.",
      );
    }
    const timestampParts = value.match(
      /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d+)?/,
    );
    if (!timestampParts) {
      throw new ImportRequestError(
        400,
        "ambiguous_date",
        "Use a complete ISO timestamp with seconds and a time zone.",
      );
    }
    const [, year, month, day, hour, minute, second] = timestampParts.map(
      Number,
    );
    const calendarCheck = new Date(Date.UTC(year, month - 1, day));
    if (
      calendarCheck.getUTCFullYear() !== year ||
      calendarCheck.getUTCMonth() !== month - 1 ||
      calendarCheck.getUTCDate() !== day || hour > 23 || minute > 59 ||
      second > 59
    ) {
      throw new ImportRequestError(
        400,
        "ambiguous_date",
        "The timestamp contains an invalid calendar date or time.",
      );
    }
    date = new Date(value);
  } else if (
    format === "MM/DD/YYYY" && /^\d{1,2}\/\d{1,2}\/\d{4}$/.test(value)
  ) {
    const [month, day, year] = value.split("/").map(Number);
    date = localNoon(year, month, day);
  } else if (format === "RAPSODO") {
    const match = value.match(
      /^(?:Sun|Mon|Tue|Wed|Thu|Fri|Sat) (?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec) (\d{1,2}) (\d{4}) (\d{1,2}):(\d{2}):(\d{2}) (AM|PM)$/,
    );
    if (match) {
      const monthName = value.slice(4, 7);
      const month = [
        "Jan",
        "Feb",
        "Mar",
        "Apr",
        "May",
        "Jun",
        "Jul",
        "Aug",
        "Sep",
        "Oct",
        "Nov",
        "Dec",
      ].indexOf(monthName) + 1;
      let hour = Number(match[3]) % 12;
      if (match[6] === "PM") hour += 12;
      date = localDateTime(
        Number(match[2]),
        month,
        Number(match[1]),
        hour,
        Number(match[4]),
        Number(match[5]),
      );
    }
  } else if (/^\d{1,2}\/\d{1,2}\/\d{2}$/.test(value)) {
    throw new ImportRequestError(
      400,
      "ambiguous_date",
      "Two-digit years require an explicit correction.",
    );
  }
  if (!date || Number.isNaN(date.valueOf())) {
    throw new ImportRequestError(
      400,
      "ambiguous_date",
      "Choose the file's date format before importing.",
    );
  }
  if (date.valueOf() > now.valueOf() + 5 * 60_000) {
    throw new ImportRequestError(
      400,
      "future_date",
      "Future observation timestamps cannot be imported.",
    );
  }
  return date;
}

export type PreviewRow = {
  sourceRowNumber: number;
  playerSourceKey: string;
  playerMatchState:
    | "matched"
    | "suggested"
    | "ambiguous"
    | "unmatched"
    | "ignored";
  playerId: string | null;
  playerLabel: string;
  metricKey: string | null;
  metricDisplayName: string | null;
  originalValue: string;
  originalUnit: string;
  normalizedValue: number | null;
  canonicalUnit: string | null;
  conversionRule: string | null;
  conversionVersion: string | null;
  observedAt: string | null;
  sourceDateString: string;
  sourceEventId: string;
  sampleSize: number | null;
  acceptanceState: "accepted" | "warning" | "rejected" | "duplicate";
  warnings: string[];
  errors: ImportErrorCode[];
  context: Record<string, string>;
};

export type ValidationSummary = {
  totalRows: number;
  generatedObservations: number;
  acceptedRows: number;
  rejectedRows: number;
  unmatchedPlayerRows: number;
  ambiguousPlayerRows: number;
  warningCount: number;
  duplicateRows: number;
};

export type ValidationPersistenceRowError = {
  source_row_number: number;
  player_match_state: PreviewRow["playerMatchState"];
  metric_mapping_state:
    | "mapped"
    | "unmapped"
    | "unsupported"
    | "deprecated"
    | "ignored";
  acceptance_state: "warning" | "rejected" | "duplicate";
  error_codes: string[];
  warning_codes: string[];
  safe_summary: string;
  safe_row_identity: {
    source_row_number: number;
    metric_keys: string[];
    metric_keys_truncated: boolean;
  };
};

export type ValidationPersistencePayload = {
  status: "ready" | "player_resolution_required";
  rowErrors: ValidationPersistenceRowError[];
  validationSummary: ValidationSummary & {
    persistedRowErrors: number;
    rowErrorsTruncated: boolean;
  };
};

/**
 * Produces the bounded, database-facing validation payload. Wide files create
 * several metric observations for one source row, so persistence deliberately
 * aggregates by source row instead of attempting to store colliding copies of
 * the same row-level error.
 */
export function buildValidationPersistencePayload(
  rows: PreviewRow[],
  summary: ValidationSummary,
): ValidationPersistencePayload {
  const grouped = new Map<number, PreviewRow[]>();
  for (const row of rows) {
    if (row.acceptanceState === "accepted") continue;
    grouped.set(row.sourceRowNumber, [
      ...(grouped.get(row.sourceRowNumber) ?? []),
      row,
    ]);
  }

  const playerStateRank: Record<PreviewRow["playerMatchState"], number> = {
    matched: 0,
    suggested: 1,
    ignored: 2,
    unmatched: 3,
    ambiguous: 4,
  };
  const metricState = (
    row: PreviewRow,
  ): ValidationPersistenceRowError["metric_mapping_state"] =>
    row.errors.includes("deprecated_metric")
      ? "deprecated"
      : row.errors.includes("unsupported_metric")
      ? "unsupported"
      : row.metricKey
      ? "mapped"
      : "unmapped";
  const metricStateRank: Record<
    ValidationPersistenceRowError["metric_mapping_state"],
    number
  > = {
    mapped: 0,
    ignored: 1,
    unmapped: 2,
    unsupported: 3,
    deprecated: 4,
  };

  const allRowErrors = [...grouped.entries()]
    .sort(([left], [right]) => left - right)
    .map(([sourceRowNumber, sourceRows]) => {
      const errorCodes = [...new Set(sourceRows.flatMap((row) => row.errors))]
        .sort();
      const warningCodes = [
        ...new Set(sourceRows.flatMap((row) => row.warnings)),
      ].sort();
      const metricKeys = [
        ...new Set(
          sourceRows.flatMap((row) => row.metricKey ? [row.metricKey] : []),
        ),
      ].sort();
      const boundedMetricKeys = metricKeys.slice(0, 50);
      const playerMatchState = sourceRows.reduce(
        (strongest, row) =>
          playerStateRank[row.playerMatchState] > playerStateRank[strongest]
            ? row.playerMatchState
            : strongest,
        sourceRows[0].playerMatchState,
      );
      const metricMappingState = sourceRows.reduce((strongest, row) => {
        const state = metricState(row);
        return metricStateRank[state] > metricStateRank[strongest]
          ? state
          : strongest;
      }, metricState(sourceRows[0]));
      const acceptanceState = sourceRows.some((row) =>
          row.acceptanceState === "rejected"
        )
        ? "rejected"
        : sourceRows.some((row) => row.acceptanceState === "duplicate")
        ? "duplicate"
        : "warning";
      return {
        source_row_number: sourceRowNumber,
        player_match_state: playerMatchState,
        metric_mapping_state: metricMappingState,
        acceptance_state: acceptanceState,
        error_codes: errorCodes,
        warning_codes: warningCodes,
        safe_summary:
          [...errorCodes, ...warningCodes].join(", ").slice(0, 500) ||
          "Review required",
        safe_row_identity: {
          source_row_number: sourceRowNumber,
          metric_keys: boundedMetricKeys,
          metric_keys_truncated: metricKeys.length > boundedMetricKeys.length,
        },
      } satisfies ValidationPersistenceRowError;
    });
  const rowErrors = allRowErrors.slice(
    0,
    IMPORT_LIMITS.maxPersistedRowErrors,
  );
  return {
    status: summary.ambiguousPlayerRows || summary.unmatchedPlayerRows
      ? "player_resolution_required"
      : "ready",
    rowErrors,
    validationSummary: {
      ...summary,
      persistedRowErrors: rowErrors.length,
      rowErrorsTruncated: allRowErrors.length > rowErrors.length,
    },
  };
}

function cell(
  parsed: ParsedDelimitedFile,
  row: string[],
  header?: string,
): string {
  if (!header) return "";
  const virtualHeader = normalizeHeader(header);
  if (virtualHeader === "provider_player_id") {
    return parsed.metadata.player_id ?? "";
  }
  if (virtualHeader === "provider_player_name") {
    return parsed.metadata.player_name ?? "";
  }
  const index = parsed.normalizedHeaders.indexOf(normalizeHeader(header));
  const value = index < 0 ? "" : (row[index] ?? "").trim();
  return parsed.missingValueTokens.includes(value) ? "" : value;
}

function identityColumnsForMetric(mapping: ColumnMapping, metricKey: string) {
  if (metricKey.startsWith("hitting.")) {
    return {
      external: mapping.columns.batter_external_id ??
        mapping.columns.player_external_id,
      username: mapping.columns.player_username,
      name: mapping.columns.batter_name ?? mapping.columns.player_name,
    };
  }
  if (metricKey.startsWith("pitching.")) {
    return {
      external: mapping.columns.pitcher_external_id ??
        mapping.columns.player_external_id,
      username: mapping.columns.player_username,
      name: mapping.columns.pitcher_name ?? mapping.columns.player_name,
    };
  }
  return {
    external: mapping.columns.player_external_id,
    username: mapping.columns.player_username,
    name: mapping.columns.player_name,
  };
}

function playerKey(
  mapping: ColumnMapping,
  parsed: ParsedDelimitedFile,
  row: string[],
  metricKey = "",
): string {
  const identity = identityColumnsForMetric(mapping, metricKey);
  const external = cell(parsed, row, identity.external);
  const username = cell(parsed, row, identity.username);
  const name = cell(parsed, row, identity.name);
  return external
    ? `external:${normalizeExternalID(external)}`
    : username
    ? `username:${normalizeUsername(username)}`
    : `name:${normalizeIdentity(name)}`;
}

function matchPlayer(args: {
  provider: string;
  mapping: ColumnMapping;
  parsed: ParsedDelimitedFile;
  row: string[];
  players: PlayerCandidate[];
  identities: ExternalIdentity[];
  metricKey: string;
}): {
  state: PreviewRow["playerMatchState"];
  playerId: string | null;
  label: string;
} {
  const identity = identityColumnsForMetric(args.mapping, args.metricKey);
  const key = playerKey(args.mapping, args.parsed, args.row, args.metricKey);
  const resolved = args.mapping.playerResolutions?.[key];
  if (resolved && args.players.some((p) => p.id === resolved && p.active)) {
    return { state: "matched", playerId: resolved, label: "Staff resolved" };
  }
  const external = cell(
    args.parsed,
    args.row,
    identity.external,
  );
  if (external) {
    const match = args.identities.find((identity) =>
      identity.provider === args.provider &&
      normalizeExternalID(identity.externalPlayerId) ===
        normalizeExternalID(external)
    );
    const player = match &&
      args.players.find((candidate) =>
        candidate.id === match.playerId && candidate.active
      );
    if (player) {
      return { state: "matched", playerId: player.id, label: player.fullName };
    }
  }
  const username = cell(
    args.parsed,
    args.row,
    identity.username,
  );
  if (username) {
    const matches = args.players.filter((candidate) =>
      candidate.active &&
      normalizeUsername(candidate.username ?? "") ===
        normalizeUsername(username)
    );
    if (matches.length === 1) {
      return {
        state: "matched",
        playerId: matches[0].id,
        label: matches[0].fullName,
      };
    }
    if (matches.length > 1) {
      return { state: "ambiguous", playerId: null, label: username };
    }
  }
  const name = cell(args.parsed, args.row, identity.name);
  if (name) {
    const matches = args.players.filter((candidate) =>
      candidate.active &&
      normalizeIdentity(candidate.fullName) === normalizeIdentity(name)
    );
    if (matches.length === 1) {
      return {
        state: "matched",
        playerId: matches[0].id,
        label: matches[0].fullName,
      };
    }
    if (matches.length > 1) {
      return { state: "ambiguous", playerId: null, label: name };
    }
  }
  return {
    state: "unmatched",
    playerId: null,
    label: name || username || external || "Unknown player",
  };
}

export function validateMapping(
  mapping: ColumnMapping,
  parsed: ParsedDelimitedFile,
): void {
  const plainObject = (value: unknown): value is Record<string, unknown> =>
    value !== null && typeof value === "object" && !Array.isArray(value);
  if (
    !plainObject(mapping) || !["wide", "long"].includes(mapping.shape) ||
    !plainObject(mapping.columns) ||
    typeof mapping.timezone !== "string" || mapping.timezone.length > 100 ||
    (mapping.dateFormat !== undefined &&
      !["ISO", "MM/DD/YYYY", "RAPSODO"].includes(mapping.dateFormat)) ||
    (mapping.adapterVersion !== undefined &&
      (typeof mapping.adapterVersion !== "string" ||
        mapping.adapterVersion.length > 100)) ||
    (mapping.detectedExportType !== undefined &&
      !Object.keys(VENDOR_ADAPTER_VERSIONS).includes(
        mapping.detectedExportType,
      )) ||
    (mapping.unitSystem !== undefined &&
      !["imperial", "metric"].includes(mapping.unitSystem)) ||
    (mapping.wideMetrics !== undefined &&
      (!Array.isArray(mapping.wideMetrics) ||
        mapping.wideMetrics.length > 250)) ||
    (mapping.contextColumns !== undefined &&
      (!Array.isArray(mapping.contextColumns) ||
        mapping.contextColumns.some((value) => typeof value !== "string"))) ||
    (mapping.longMetricKeys !== undefined &&
      !plainObject(mapping.longMetricKeys)) ||
    (mapping.longSourceUnits !== undefined &&
      !plainObject(mapping.longSourceUnits)) ||
    (mapping.playerResolutions !== undefined &&
      !plainObject(mapping.playerResolutions))
  ) {
    throw new ImportRequestError(
      400,
      "invalid_mapping",
      "Choose wide or long file shape.",
    );
  }
  const allStringsBounded = (
    value: Record<string, unknown>,
    maxEntries: number,
  ) =>
    Object.keys(value).length <= maxEntries && Object.entries(value).every(
      ([key, item]) =>
        key.length <= 300 && typeof item === "string" && item.length <= 300,
    );
  if (
    !allStringsBounded(mapping.columns, 20) ||
    !allStringsBounded(mapping.longMetricKeys ?? {}, 500) ||
    !allStringsBounded(mapping.longSourceUnits ?? {}, 500) ||
    !allStringsBounded(mapping.playerResolutions ?? {}, 1_000) ||
    (mapping.wideMetrics ?? []).some((item) =>
      !plainObject(item) || typeof item.column !== "string" ||
      item.column.length > 200 || typeof item.metricKey !== "string" ||
      item.metricKey.length > 200 ||
      (item.sourceUnit !== undefined &&
        (typeof item.sourceUnit !== "string" || item.sourceUnit.length > 50))
    )
  ) {
    throw new ImportRequestError(
      400,
      "invalid_mapping",
      "The mapping contains invalid or oversized values.",
    );
  }
  try {
    new Intl.DateTimeFormat("en-US", { timeZone: mapping.timezone }).format();
  } catch {
    throw new ImportRequestError(
      400,
      "invalid_timezone",
      "Choose a valid IANA time zone for this import.",
    );
  }
  if ((mapping.contextColumns?.length ?? 0) > IMPORT_LIMITS.maxContextColumns) {
    throw new ImportRequestError(
      400,
      "mapping_too_large",
      "Map at most 20 context columns.",
    );
  }
  const available = new Set([
    ...parsed.normalizedHeaders,
    ...(parsed.metadata.player_id ? ["provider_player_id"] : []),
    ...(parsed.metadata.player_name ? ["provider_player_name"] : []),
  ]);
  const mappedHeaders = [
    ...Object.values(mapping.columns),
    ...(mapping.wideMetrics ?? []).map((item) => item.column),
    ...(mapping.contextColumns ?? []),
  ].filter((value): value is string => typeof value === "string");
  if (mappedHeaders.some((header) => !available.has(normalizeHeader(header)))) {
    throw new ImportRequestError(
      400,
      "mapping_header_mismatch",
      "The mapping references columns that are not present in this file.",
    );
  }
  if (
    !mapping.columns.player_external_id && !mapping.columns.player_username &&
    !mapping.columns.player_name && !mapping.columns.pitcher_external_id &&
    !mapping.columns.pitcher_name && !mapping.columns.batter_external_id &&
    !mapping.columns.batter_name
  ) {
    throw new ImportRequestError(
      400,
      "missing_player_mapping",
      "Map an external ID, username, or player name column.",
    );
  }
  if (
    !mapping.columns.observation_date && !mapping.columns.observation_timestamp
  ) {
    throw new ImportRequestError(
      400,
      "missing_date_mapping",
      "Map an observation date or timestamp column.",
    );
  }
  if (mapping.shape === "wide" && !(mapping.wideMetrics?.length)) {
    throw new ImportRequestError(
      400,
      "missing_metric_mapping",
      "Map at least one metric column.",
    );
  }
  const roleHeaders = Object.values(mapping.columns).filter(
    (value): value is string => typeof value === "string",
  ).map(normalizeHeader);
  const contextHeaders = (mapping.contextColumns ?? []).map(normalizeHeader);
  const duplicateRoles = roleHeaders.find((header, index) =>
    roleHeaders.indexOf(header) !== index
  );
  if (duplicateRoles) {
    throw new ImportRequestError(
      400,
      "incompatible_column_roles",
      "One source column cannot be assigned to multiple protected roles.",
    );
  }
  if (contextHeaders.some((header) => roleHeaders.includes(header))) {
    throw new ImportRequestError(
      400,
      "incompatible_column_roles",
      "Protected identity, metric, value, unit, and date columns cannot also be context.",
    );
  }
  if (mapping.shape === "wide") {
    const sourceColumns = (mapping.wideMetrics ?? []).map((item) =>
      normalizeHeader(item.column)
    );
    const metricKeys = (mapping.wideMetrics ?? []).map((item) =>
      item.metricKey
    );
    if (
      sourceColumns.some((value, index) =>
        sourceColumns.indexOf(value) !== index
      ) ||
      metricKeys.some((value, index) => metricKeys.indexOf(value) !== index) ||
      sourceColumns.some((value) => roleHeaders.includes(value))
    ) {
      throw new ImportRequestError(
        400,
        "duplicate_metric_mapping",
        "Each wide metric must use a distinct source column and canonical metric.",
      );
    }
  }
  if (
    mapping.shape === "long" &&
    (!mapping.columns.metric || !mapping.columns.value)
  ) {
    throw new ImportRequestError(
      400,
      "missing_metric_mapping",
      "Long files require metric and value columns.",
    );
  }
}

export function buildPreview(args: {
  parsed: ParsedDelimitedFile;
  provider: ProviderKey;
  mapping: ColumnMapping;
  definitions: MetricDefinition[];
  players: PlayerCandidate[];
  identities: ExternalIdentity[];
  existingSourceIds?: Set<string>;
  now?: Date;
}): { rows: PreviewRow[]; summary: ValidationSummary } {
  validateMapping(args.mapping, args.parsed);
  const definitions = new Map(
    args.definitions.map((
      definition,
    ) => [definition.canonical_key, definition]),
  );
  const configuredMetricKeys = args.mapping.shape === "wide"
    ? (args.mapping.wideMetrics ?? []).map((item) => item.metricKey)
    : Object.values(args.mapping.longMetricKeys ?? {});
  for (const metricKey of configuredMetricKeys) {
    const definition = definitions.get(metricKey);
    if (!definition || definition.status !== "active") {
      throw new ImportRequestError(
        400,
        definition ? "deprecated_metric" : "unsupported_metric",
        "Mappings may reference only active canonical metrics.",
      );
    }
  }
  if (
    Object.values(args.mapping.playerResolutions ?? {}).some((playerId) =>
      !args.players.some((player) => player.active && player.id === playerId)
    )
  ) {
    throw new ImportRequestError(
      403,
      "player_scope_denied",
      "A saved player resolution is outside the authorized player scope.",
    );
  }
  const output: PreviewRow[] = [];
  const sourceIdentities = new Set<string>();
  const acceptedSourceRows = new Set<number>();
  const rejectedSourceRows = new Set<number>();
  const unmatchedSourceRows = new Set<number>();
  const ambiguousSourceRows = new Set<number>();
  let warningCount = 0;
  let duplicateRows = 0;
  const addMetric = (
    row: string[],
    rowIndex: number,
    metricKey: string,
    rawValue: string,
    rawUnit: string,
  ) => {
    if (output.length >= IMPORT_LIMITS.maxGeneratedObservations) {
      throw new ImportRequestError(
        400,
        "observation_limit_exceeded",
        "The mapping would generate more than 50,000 observations.",
      );
    }
    const sourceRowNumber = args.parsed.sourceRowNumbers[rowIndex] ??
      rowIndex + 2;
    const errors: ImportErrorCode[] = [];
    const warnings: string[] = [];
    const sourcePlayerKey = playerKey(
      args.mapping,
      args.parsed,
      row,
      metricKey,
    );
    const match = matchPlayer({ ...args, row, metricKey });
    if (match.state === "unmatched") {
      errors.push("missing_player");
      unmatchedSourceRows.add(sourceRowNumber);
    }
    if (match.state === "ambiguous") {
      errors.push("ambiguous_player");
      ambiguousSourceRows.add(sourceRowNumber);
    }
    const definition = definitions.get(metricKey);
    if (!metricKey) errors.push("missing_metric");
    else if (!definition) errors.push("unsupported_metric");
    else if (definition.status !== "active") errors.push("deprecated_metric");
    let numeric: number | null = null;
    let converted: ConversionResult | null = null;
    if (!rawValue) errors.push("missing_value");
    else {
      const normalizedNumber = rawValue.trim();
      const invariantNumber =
        /^[+-]?(?:\d+|\d{1,3}(?:,\d{3})+)(?:\.\d+)?(?:[eE][+-]?\d+)?$/;
      numeric = invariantNumber.test(normalizedNumber)
        ? Number(normalizedNumber.replaceAll(",", ""))
        : Number.NaN;
      if (!Number.isFinite(numeric)) errors.push("invalid_number");
    }
    if (definition && numeric !== null && Number.isFinite(numeric)) {
      if (definition.canonical_unit && !rawUnit) errors.push("missing_unit");
      else {
        try {
          converted = convertUnit(numeric, rawUnit, definition.canonical_unit);
        } catch (error) {
          const code = error instanceof ImportRequestError
            ? error.code
            : "unsupported_unit";
          errors.push(
            code === "unit_conflict" ? "unit_conflict" : "unsupported_unit",
          );
        }
      }
    }
    const sourceDate = cell(
      args.parsed,
      row,
      args.mapping.columns.observation_timestamp ||
        args.mapping.columns.observation_date,
    );
    let observedAt: string | null = null;
    try {
      observedAt = parseObservationDate(
        sourceDate,
        args.mapping.dateFormat,
        args.mapping.timezone,
        args.now,
      ).toISOString();
    } catch (error) {
      const code = error instanceof ImportRequestError
        ? error.code
        : "ambiguous_date";
      errors.push(code as ImportErrorCode);
    }
    const sampleRaw = cell(args.parsed, row, args.mapping.columns.sample_size);
    const sampleSize = sampleRaw && /^\d+$/.test(sampleRaw)
      ? Number(sampleRaw)
      : null;
    if (
      sampleRaw &&
      (!Number.isSafeInteger(sampleSize) || (sampleSize ?? 0) < 1)
    ) {
      warnings.push("invalid_sample_size_ignored");
    }
    const stableIdentity = [
      match.playerId,
      metricKey,
      rawValue,
      rawUnit,
      observedAt,
      cell(args.parsed, row, args.mapping.columns.source_event_id),
    ].join("|");
    if (
      sourceIdentities.has(stableIdentity) ||
      args.existingSourceIds?.has(stableIdentity)
    ) {
      errors.push(
        sourceIdentities.has(stableIdentity)
          ? "duplicate_source_row"
          : "duplicate_existing_observation",
      );
      duplicateRows++;
    }
    sourceIdentities.add(stableIdentity);
    const context: Record<string, string> = {};
    let contextCharacters = 0;
    for (const header of args.mapping.contextColumns ?? []) {
      const value = cell(args.parsed, row, header);
      if (value) {
        const remaining = IMPORT_LIMITS.maxContextMetadataCharacters -
          contextCharacters;
        if (remaining <= 0) break;
        const bounded = value.slice(
          0,
          Math.min(IMPORT_LIMITS.maxContextValueCharacters, remaining),
        );
        context[normalizeHeader(header)] = bounded;
        contextCharacters += bounded.length;
      }
    }
    const acceptanceState = errors.length
      ? (errors.some((code) => code.startsWith("duplicate_"))
        ? "duplicate"
        : "rejected")
      : warnings.length
      ? "warning"
      : "accepted";
    if (errors.length) rejectedSourceRows.add(sourceRowNumber);
    else acceptedSourceRows.add(sourceRowNumber);
    warningCount += warnings.length;
    output.push({
      sourceRowNumber,
      playerSourceKey: sourcePlayerKey,
      playerMatchState: match.state,
      playerId: match.playerId,
      playerLabel: match.label,
      metricKey: definition?.canonical_key ?? (metricKey || null),
      metricDisplayName: definition?.display_name ?? null,
      originalValue: rawValue,
      originalUnit: rawUnit,
      normalizedValue: converted?.normalizedValue ?? null,
      canonicalUnit: converted?.canonicalUnit ?? definition?.canonical_unit ??
        null,
      conversionRule: converted?.rule ?? null,
      conversionVersion: converted?.version ?? null,
      observedAt,
      sourceDateString: sourceDate,
      sourceEventId: cell(
        args.parsed,
        row,
        args.mapping.columns.source_event_id,
      ),
      sampleSize: sampleSize && sampleSize > 0 ? sampleSize : null,
      acceptanceState,
      warnings,
      errors,
      context,
    });
  };
  args.parsed.rows.forEach((row, rowIndex) => {
    if (args.mapping.shape === "wide") {
      for (const metric of args.mapping.wideMetrics ?? []) {
        const raw = cell(args.parsed, row, metric.column);
        if (!raw) continue;
        addMetric(
          row,
          rowIndex,
          metric.metricKey,
          raw,
          metric.sourceUnit ?? "",
        );
      }
    } else {
      const sourceMetric = cell(args.parsed, row, args.mapping.columns.metric);
      const metricKey =
        args.mapping.longMetricKeys?.[normalizeIdentity(sourceMetric)] ??
          sourceMetric;
      const sourceUnit = cell(args.parsed, row, args.mapping.columns.unit) ||
        args.mapping.longSourceUnits?.[normalizeIdentity(sourceMetric)] || "";
      addMetric(
        row,
        rowIndex,
        metricKey,
        cell(args.parsed, row, args.mapping.columns.value),
        sourceUnit,
      );
    }
  });
  return {
    rows: output,
    summary: {
      totalRows: args.parsed.totalRows,
      generatedObservations: output.length,
      // A source row may generate several observations in wide form. If any
      // generated observation is rejected, the source row is rejected once;
      // accepted and rejected totals therefore remain mutually exclusive.
      acceptedRows:
        [...acceptedSourceRows].filter((row) => !rejectedSourceRows.has(row))
          .length,
      rejectedRows: rejectedSourceRows.size,
      unmatchedPlayerRows: unmatchedSourceRows.size,
      ambiguousPlayerRows: ambiguousSourceRows.size,
      warningCount,
      duplicateRows,
    },
  };
}

export async function mappingFingerprint(
  mapping: ColumnMapping,
): Promise<string> {
  const sort = (value: unknown): unknown => {
    if (Array.isArray(value)) return value.map(sort);
    if (value && typeof value === "object") {
      return Object.fromEntries(
        Object.entries(value as Record<string, unknown>).sort(([a], [b]) =>
          a.localeCompare(b)
        ).map(([key, item]) => [key, sort(item)]),
      );
    }
    return value;
  };
  return await sha256Hex(JSON.stringify(sort(mapping)));
}

export async function stableObservationUUID(material: string): Promise<string> {
  const hex = await sha256Hex(material);
  // RFC 4122 variant with a deterministic v5-shaped UUID sourced from SHA-256.
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-5${hex.slice(13, 16)}-a${
    hex.slice(17, 20)
  }-${hex.slice(20, 32)}`;
}
