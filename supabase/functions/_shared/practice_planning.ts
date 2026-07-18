export type Row = Record<string, unknown>;

export const PLAN_STATUSES = [
  "draft",
  "ready",
  "published",
  "active",
  "completed",
  "archived",
] as const;

export const BLOCK_TYPES = [
  "arrival",
  "meeting",
  "warmup",
  "movement_prep",
  "throwing",
  "arm_care",
  "defense",
  "infield",
  "outfield",
  "catching",
  "pitching",
  "hitting",
  "baserunning",
  "strength",
  "conditioning",
  "competition",
  "recovery",
  "cooldown",
  "custom",
] as const;

export const EXECUTION_STATUSES = [
  "pending",
  "active",
  "completed",
  "skipped",
  "adjusted",
] as const;

export function plannedDuration(blocks: Row[]): number {
  return blocks
    .filter((block) => !block.parent_block_id && !block.archived_at)
    .reduce((total, block) => total + Number(block.duration_minutes ?? 0), 0);
}

export function hasAccidentalOverlap(blocks: Row[]): boolean {
  const sequential = blocks
    .filter((block) => !block.parent_block_id && !block.archived_at)
    .map((block) => ({
      start: Number(block.start_offset_minutes ?? 0),
      end: Number(block.start_offset_minutes ?? 0) +
        Number(block.duration_minutes ?? 0),
    }))
    .sort((a, b) => a.start - b.start || a.end - b.end);
  return sequential.some((block, index) =>
    index > 0 && block.start < sequential[index - 1].end
  );
}

export function currentAndNextExecution(executions: Row[]) {
  const ordered = executions
    .filter((row) => !row.parent_block_id)
    .sort((a, b) =>
      Number(a.sequence_index ?? 0) - Number(b.sequence_index ?? 0)
    );
  const current = ordered.find((row) => row.status === "active") ?? null;
  const next = ordered.find((row) => row.status === "pending") ?? null;
  return { current, next };
}

export function sanitizePracticePayload(payload: Row, playerId?: string): Row {
  const blocks = Array.isArray(payload.blocks) ? payload.blocks as Row[] : [];
  const groups = Array.isArray(payload.groups) ? payload.groups as Row[] : [];
  const assignments = Array.isArray(payload.assignments)
    ? payload.assignments as Row[]
    : [];
  const equipment = Array.isArray(payload.equipment)
    ? payload.equipment as Row[]
    : [];
  const ownAssignmentGroupIds = new Set(
    assignments.filter((row) => row.user_id === playerId).map((row) =>
      String(row.group_id ?? "")
    ).filter(Boolean),
  );
  return {
    ...payload,
    plan: payload.plan && typeof payload.plan === "object"
      ? strip(payload.plan as Row, ["coach_notes"])
      : payload.plan,
    blocks: blocks.filter((row) => row.visibility !== "staff_only").map((row) =>
      strip(row, ["coaching_points"])
    ),
    groups: groups.filter((row) => ownAssignmentGroupIds.has(String(row.id))),
    assignments: assignments.filter((row) => row.user_id === playerId),
    equipment: equipment.filter((row) => row.visibility !== "staff_only").map(
      (row) => strip(row, ["notes", "prepared_by"]),
    ),
    audit: undefined,
  };
}

function strip(row: Row, keys: string[]): Row {
  const output = { ...row };
  for (const key of keys) delete output[key];
  return output;
}
