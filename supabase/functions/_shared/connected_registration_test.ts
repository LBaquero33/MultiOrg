import {
  assertEquals,
  assertThrows,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  averageEvaluationValues,
  mayUseRegistrationOffering,
  publicCheckInParticipant,
  registrationPhoneLastFourMatches,
  validateDecisionRelease,
  validateEvaluationValue,
} from "./connected_registration.ts";

Deno.test("decision release blocks unresolved players when releasing all", () => {
  assertThrows(
    () =>
      validateDecisionRelease([
        {
          id: "one",
          decision_state: "offer_roster_spot",
          contact_email: "family@example.com",
        },
        {
          id: "two",
          decision_state: "undecided",
          contact_email: "other@example.com",
        },
      ], true),
    Error,
    "decision_release_unresolved_participants",
  );
});

Deno.test("selected release includes finalized recipients only", () => {
  assertEquals(
    validateDecisionRelease([
      {
        id: "one",
        decision_state: "offer_roster_spot",
        contact_email: "family@example.com",
      },
      {
        id: "two",
        decision_state: "watchlist",
        contact_email: "other@example.com",
      },
    ], false),
    { participantIds: ["one"] },
  );
});

Deno.test("QR phone confirmation compares exactly the last four digits", () => {
  assertEquals(
    registrationPhoneLastFourMatches("(917) 555-2985", "2985"),
    true,
  );
  assertEquals(
    registrationPhoneLastFourMatches("(917) 555-2985", "5552985"),
    false,
  );
  assertEquals(registrationPhoneLastFourMatches(null, "2985"), false);
});

Deno.test("evaluation inputs enforce their configured scales", () => {
  assertEquals(validateEvaluationValue("letter_grade", "b+"), {
    valueText: "B+",
    valueNumber: null,
  });
  assertEquals(validateEvaluationValue("twenty_eighty", 55), {
    valueText: null,
    valueNumber: 55,
  });
  assertThrows(
    () => validateEvaluationValue("twenty_eighty", 53),
    Error,
    "evaluation_twenty_eighty_invalid",
  );
  assertThrows(
    () => validateEvaluationValue("one_hundred", 101),
    Error,
    "evaluation_one_hundred_invalid",
  );
  assertEquals(averageEvaluationValues([50, 60, "70"]), 60);
});

Deno.test("explicit offering assignments never turn every coach into a manager", () => {
  assertEquals(mayUseRegistrationOffering("coach", [], "manage"), false);
  assertEquals(
    mayUseRegistrationOffering("coach", ["evaluator"], "manage"),
    false,
  );
  assertEquals(
    mayUseRegistrationOffering("coach", ["manager"], "manage"),
    true,
  );
  assertEquals(mayUseRegistrationOffering("admin", [], "manage"), true);
});

Deno.test("public QR roster projection omits contact and private evaluation fields", () => {
  assertEquals(
    publicCheckInParticipant({
      id: "participant",
      display_name: "Alex Player",
      participant_number: 24,
      age_group: "14U",
      checked_in: true,
      contact_email: "private@example.com",
      contact_phone: "9175552985",
      staff_comments: "private",
    }),
    {
      id: "participant",
      display_name: "Alex Player",
      participant_number: 24,
      age_group: "14U",
      checked_in: true,
    },
  );
});
