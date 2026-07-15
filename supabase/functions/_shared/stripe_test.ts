import { stripeSubscriptionSnapshot } from "./stripe.ts";

function assertEqual<T>(actual: T, expected: T, label: string) {
  if (actual !== expected) throw new Error(`${label}: expected ${expected}, received ${actual}`);
}

Deno.test("uses current period dates from the newer subscription item shape", () => {
  const snapshot = stripeSubscriptionSnapshot({
    current_period_start: 1,
    current_period_end: 2,
    cancel_at_period_end: false,
    items: { data: [{ current_period_start: 1_700_000_000, current_period_end: 1_700_086_400 }] },
  });
  assertEqual(snapshot.currentPeriodStart, "2023-11-14T22:13:20.000Z", "item start");
  assertEqual(snapshot.currentPeriodEnd, "2023-11-15T22:13:20.000Z", "item end");
  assertEqual(snapshot.cancelAtPeriodEnd, false, "new subscription cancellation state");
});

Deno.test("falls back to legacy top-level subscription dates", () => {
  const snapshot = stripeSubscriptionSnapshot({
    current_period_start: 1_700_000_000,
    current_period_end: 1_700_086_400,
    cancel_at_period_end: true,
  });
  assertEqual(snapshot.currentPeriodStart, "2023-11-14T22:13:20.000Z", "legacy start");
  assertEqual(snapshot.currentPeriodEnd, "2023-11-15T22:13:20.000Z", "legacy end");
  assertEqual(snapshot.cancelAtPeriodEnd, true, "scheduled cancellation state");
});

Deno.test("handles missing subscription items and dates safely", () => {
  const snapshot = stripeSubscriptionSnapshot({ items: { data: [] }, cancel_at_period_end: false });
  assertEqual(snapshot.item, null, "missing item");
  assertEqual(snapshot.currentPeriodStart, null, "missing start");
  assertEqual(snapshot.currentPeriodEnd, null, "missing end");
  assertEqual(snapshot.cancelAtPeriodEnd, false, "false cancellation state");
});
