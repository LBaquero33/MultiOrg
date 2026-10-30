export type AccountDeletionError = {
  code?: unknown;
  message?: unknown;
  details?: unknown;
  hint?: unknown;
};

export const ACCOUNT_DELETION_SUPPORT_URL = "https://www.homeplateapps.com/support";

export function isAccountDeletionEnabled(value: string | undefined): boolean {
  return value === "true";
}

export function accountDeletionUnavailableResponse(): {
  status: 503;
  body: { error: "account_deletion_temporarily_unavailable"; support_url: string };
} {
  return {
    status: 503,
    body: {
      error: "account_deletion_temporarily_unavailable",
      support_url: ACCOUNT_DELETION_SUPPORT_URL,
    },
  };
}

function errorText(error: unknown): string {
  if (typeof error === "string") return error;
  if (!error || typeof error !== "object") return "";
  const value = error as AccountDeletionError;
  return [value.code, value.message, value.details, value.hint]
    .filter((part): part is string => typeof part === "string")
    .join(" ")
    .toLowerCase();
}

export function isSoleActiveOwnerConflict(error: unknown): boolean {
  const text = errorText(error);
  return text.includes("account_deletion_sole_active_owner") ||
    text.includes("sole active owner");
}

export function accountDeletionConflictResponse(): {
  status: 409;
  body: { error: string; message: string };
} {
  return {
    status: 409,
    body: {
      error: "sole_active_owner",
      message: "Assign another active owner in each organization before deleting this account.",
    },
  };
}
