import {
  normalizeHeader,
  type ParsedDelimitedFile,
  type ProviderDetection,
} from "./player_development_imports.ts";

export const MARIST_PROVIDER_ANALYTICS_VERSION = "marist-provider-summary.v1";

export type NumericSummary = {
  sample_count: number;
  average: number | null;
  maximum: number | null;
  minimum: number | null;
};

export type PitchTypeSummary = {
  pitch_type: string;
  pitch_count: number;
  velocity: NumericSummary;
  spin_rate: NumericSummary;
  induced_vertical_break: NumericSummary;
  horizontal_break: NumericSummary;
};

export type ProviderSessionAnalytics = {
  schema_version: typeof MARIST_PROVIDER_ANALYTICS_VERSION;
  provider: ProviderDetection["providerKey"];
  export_type: ProviderDetection["exportType"];
  event_count: number;
  hitting: {
    exit_velocity: NumericSummary;
    launch_angle: NumericSummary;
    distance: NumericSummary;
    barrel_count: number;
    barrel_rate: number | null;
  } | null;
  pitching: {
    velocity: NumericSummary;
    spin_rate: NumericSummary;
    induced_vertical_break: NumericSummary;
    horizontal_break: NumericSummary;
    by_pitch_type: PitchTypeSummary[];
  } | null;
};

function rounded(value: number): number {
  return Number(value.toFixed(3));
}

function summarize(values: number[]): NumericSummary {
  const finite = values.filter(Number.isFinite);
  if (!finite.length) {
    return { sample_count: 0, average: null, maximum: null, minimum: null };
  }
  return {
    sample_count: finite.length,
    average: rounded(finite.reduce((sum, value) => sum + value, 0) / finite.length),
    maximum: rounded(Math.max(...finite)),
    minimum: rounded(Math.min(...finite)),
  };
}

function columnIndex(parsed: ParsedDelimitedFile, aliases: string[]): number {
  const normalized = new Set(aliases.map(normalizeHeader));
  return parsed.normalizedHeaders.findIndex((header) => normalized.has(header));
}

function numberColumn(parsed: ParsedDelimitedFile, aliases: string[]): number[] {
  const index = columnIndex(parsed, aliases);
  if (index < 0) return [];
  return parsed.rows.map((row) => Number(row[index])).filter(Number.isFinite);
}

function optionalNumber(row: string[], index: number): number | null {
  if (index < 0) return null;
  const value = Number(row[index]);
  return Number.isFinite(value) ? value : null;
}

function pitchTypeGroups(
  parsed: ParsedDelimitedFile,
  velocityAliases: string[],
  spinAliases: string[],
  ivbAliases: string[],
  horizontalBreakAliases: string[],
): PitchTypeSummary[] {
  const typeIndex = columnIndex(parsed, ["TaggedPitchType", "AutoPitchType", "Pitch Type"]);
  if (typeIndex < 0) return [];
  const velocityIndex = columnIndex(parsed, velocityAliases);
  const spinIndex = columnIndex(parsed, spinAliases);
  const ivbIndex = columnIndex(parsed, ivbAliases);
  const horizontalBreakIndex = columnIndex(parsed, horizontalBreakAliases);
  const groups = new Map<string, {
    velocity: number[];
    spin: number[];
    ivb: number[];
    horizontalBreak: number[];
    count: number;
  }>();
  for (const row of parsed.rows) {
    const pitchType = row[typeIndex]?.trim() || "Unspecified";
    const group = groups.get(pitchType) ?? {
      velocity: [], spin: [], ivb: [], horizontalBreak: [], count: 0,
    };
    group.count += 1;
    const velocity = optionalNumber(row, velocityIndex);
    const spin = optionalNumber(row, spinIndex);
    const ivb = optionalNumber(row, ivbIndex);
    const horizontalBreak = optionalNumber(row, horizontalBreakIndex);
    if (velocity !== null) group.velocity.push(velocity);
    if (spin !== null) group.spin.push(spin);
    if (ivb !== null) group.ivb.push(ivb);
    if (horizontalBreak !== null) group.horizontalBreak.push(horizontalBreak);
    groups.set(pitchType, group);
  }
  return [...groups.entries()].map(([pitchType, group]) => ({
    pitch_type: pitchType,
    pitch_count: group.count,
    velocity: summarize(group.velocity),
    spin_rate: summarize(group.spin),
    induced_vertical_break: summarize(group.ivb),
    horizontal_break: summarize(group.horizontalBreak),
  })).sort((left, right) =>
    right.pitch_count - left.pitch_count || left.pitch_type.localeCompare(right.pitch_type)
  );
}

export function summarizeProviderSession(
  parsed: ParsedDelimitedFile,
  detection: ProviderDetection,
): ProviderSessionAnalytics {
  const hittingAliases = detection.exportType === "rapsodo_hitting"
    ? {
      velocity: ["ExitVelocity"], angle: ["LaunchAngle"], distance: ["Distance"],
    }
    : detection.exportType === "hittrax_hitting"
    ? {
      velocity: ["Exit Velocity"], angle: ["Launch Angle"], distance: ["Distance"],
    }
    : {
      velocity: ["ExitSpeed"], angle: ["Angle"], distance: ["Distance"],
    };
  const exitVelocityIndex = columnIndex(parsed, hittingAliases.velocity);
  const launchAngleIndex = columnIndex(parsed, hittingAliases.angle);
  const hittingRows = parsed.rows.filter((row) =>
    optionalNumber(row, exitVelocityIndex) !== null || optionalNumber(row, launchAngleIndex) !== null
  );
  const exitVelocity = numberColumn(parsed, hittingAliases.velocity);
  const launchAngle = numberColumn(parsed, hittingAliases.angle);
  const distance = numberColumn(parsed, hittingAliases.distance);
  let barrelCount = 0;
  let barrelEligibleCount = 0;
  for (const row of hittingRows) {
    const velocity = optionalNumber(row, exitVelocityIndex);
    const angle = optionalNumber(row, launchAngleIndex);
    if (velocity === null || angle === null) continue;
    barrelEligibleCount += 1;
    // This is the exact barrel rule used by the existing Marist application.
    if (velocity >= 98 && angle >= 26 && angle <= 30) barrelCount += 1;
  }

  const velocityAliases = detection.exportType === "rapsodo_pitching"
    ? ["Velocity"]
    : ["RelSpeed"];
  const spinAliases = detection.exportType === "rapsodo_pitching"
    ? ["Total Spin"]
    : ["SpinRate"];
  const ivbAliases = detection.exportType === "rapsodo_pitching"
    ? ["Induced Vertical Break", "VB (trajectory)"]
    : ["InducedVertBreak"];
  const horizontalBreakAliases = detection.exportType === "rapsodo_pitching"
    ? ["Horizontal Break", "HB (trajectory)"]
    : ["HorzBreak"];
  const pitchingVelocity = numberColumn(parsed, velocityAliases);
  const pitchingSpin = numberColumn(parsed, spinAliases);
  const pitchingIVB = numberColumn(parsed, ivbAliases);
  const pitchingHorizontalBreak = numberColumn(parsed, horizontalBreakAliases);
  const hasPitching = pitchingVelocity.length > 0 || pitchingSpin.length > 0;

  return {
    schema_version: MARIST_PROVIDER_ANALYTICS_VERSION,
    provider: detection.providerKey,
    export_type: detection.exportType,
    event_count: parsed.totalRows,
    hitting: hittingRows.length
      ? {
        exit_velocity: summarize(exitVelocity),
        launch_angle: summarize(launchAngle),
        distance: summarize(distance),
        barrel_count: barrelCount,
        barrel_rate: barrelEligibleCount
          ? rounded(barrelCount / barrelEligibleCount)
          : null,
      }
      : null,
    pitching: hasPitching
      ? {
        velocity: summarize(pitchingVelocity),
        spin_rate: summarize(pitchingSpin),
        induced_vertical_break: summarize(pitchingIVB),
        horizontal_break: summarize(pitchingHorizontalBreak),
        by_pitch_type: pitchTypeGroups(
          parsed,
          velocityAliases,
          spinAliases,
          ivbAliases,
          horizontalBreakAliases,
        ),
      }
      : null,
  };
}
