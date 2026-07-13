import { json } from "../_shared/apple_player_subscription.ts";

// Fail closed until App Store Server Notifications V2 are routed through a
// runtime that can perform Apple's complete certificate-chain and JWS
// verification. Hosted Supabase Edge Runtime does not implement the Node X.509
// APIs required by Apple's official server library. Notification payloads must
// never be decoded and trusted without that cryptographic verification.
const DEPLOYMENT_MARKER = "apple_notifications_verifier_required_20260714_1";

Deno.serve((req) => {
  if (req.method !== "POST") return json(405, { error: "method_not_allowed" });
  console.error(JSON.stringify({
    event: "apple_notification_rejected_fail_closed",
    deployment_marker: DEPLOYMENT_MARKER,
    code: "apple_notification_verifier_unavailable",
  }));
  return json(503, { error: "apple_notification_verifier_unavailable" });
});
