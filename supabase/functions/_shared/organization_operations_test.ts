import {
  balanceStatus,
  financialLayerIncluded,
  invoiceNextStatus,
  mayTransitionSeason,
  notificationDecision,
  ratio,
  registrationIsOpen,
  registrationPlacement,
  rowsToCSV,
  sanitizeRegistration,
} from "./organization_operations.ts";

const equal = (actual: unknown, expected: unknown) => {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(
      `Expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`,
    );
  }
};

Deno.test("season lifecycle allows only explicit transitions", () => {
  equal(mayTransitionSeason("planning", "registration_open"), true);
  equal(mayTransitionSeason("planning", "active"), false);
  equal(mayTransitionSeason("archived", "planning"), false);
});

Deno.test("registration opening and capacity are deterministic", () => {
  const now = new Date("2026-07-18T12:00:00Z");
  equal(
    registrationIsOpen({
      state: "active",
      opens_at: "2026-07-01T00:00:00Z",
      closes_at: "2026-08-01T00:00:00Z",
    }, now),
    true,
  );
  equal(registrationPlacement(10, 10, 2, 1), "waitlisted");
  equal(registrationPlacement(10, 10, 2, 2), "full");
});

Deno.test("invoice states preserve issued records", () => {
  equal(invoiceNextStatus("draft", "issue"), "issued");
  equal(invoiceNextStatus("issued", "write_off"), "written_off");
  equal(invoiceNextStatus("paid", "void"), null);
  equal(balanceStatus(1000, 400, "2026-08-01"), "partially_paid");
});

Deno.test("required notices stay in app while quiet hours suppress push", () => {
  equal(
    notificationDecision(
      {
        in_app_enabled: false,
        push_enabled: true,
        quiet_hours_start: "22:00",
        quiet_hours_end: "07:00",
      },
      "23:30",
      true,
    ),
    { inApp: true, push: false, reason: "quiet_hours" },
  );
  equal(
    notificationDecision(
      { in_app_enabled: false, push_enabled: false },
      "12:00",
      false,
    ),
    { inApp: false, push: false, reason: "preference" },
  );
});

Deno.test("financial layer and registration redaction do not leak", () => {
  equal(financialLayerIncluded("organization_customer"), true);
  equal(financialLayerIncluded("home_plate_saas"), false);
  const row = sanitizeRegistration(
    {
      applicant_user_id: "a",
      sensitive_answers: { medical: "private" },
      balance_cents: 100,
    },
    "coach",
    "coach",
  );
  equal("sensitive_answers" in row, false);
  equal("balance_cents" in row, false);
});

Deno.test("analytics empty ratios and CSV export remain truthful", () => {
  equal(ratio(0, 0), null);
  equal(ratio(3, 4), 0.75);
  equal(
    rowsToCSV([{ name: "Doe, Jane", amount: 1200, secret: "x" }], [
      "name",
      "amount",
    ]),
    'name,amount\r\n"Doe, Jane",1200',
  );
});
