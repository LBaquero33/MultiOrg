import { appleStatus, appleVerifier, env, json, syncAppleSubscription } from "../_shared/apple_player_subscription.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

Deno.serve(async (req) => {
  if (req.method !== "POST") return json(405, { error: "method_not_allowed" });
  let admin: ReturnType<typeof createClient> | undefined;
  let ledgerId: string | undefined;
  try {
    const body = await req.json(); const signedPayload = String(body.signedPayload ?? ""); if (!signedPayload) return json(400, { error: "missing_signed_payload" });
    const verifier: any = await appleVerifier();
    const verified: any = await verifier.verifyAndDecodeNotification(signedPayload);
    const notificationId = String(verified.notificationUUID ?? ""); if (!notificationId) return json(400, { error: "missing_notification_uuid" });
    admin = createClient(env("SUPABASE_URL"), env("SUPABASE_SERVICE_ROLE_KEY"), { auth: { persistSession: false, autoRefreshToken: false } });
    const { data: prior } = await admin.from("sd_webhook_events").select("id,processing_status,attempt_count").eq("provider", "apple").eq("provider_event_id", notificationId).maybeSingle();
    if (prior?.processing_status === "processed" || prior?.processing_status === "processing") return json(200, { received: true, duplicate: true });
    const ledger = prior?.id ? await admin.from("sd_webhook_events").update({ processing_status: "processing", attempt_count: Number(prior.attempt_count ?? 0) + 1, error_message: null }).eq("id", prior.id).select("id").single() : await admin.from("sd_webhook_events").insert({ provider: "apple", provider_event_id: notificationId, event_type: String(verified.notificationType ?? ""), processing_status: "processing", attempt_count: 1, payload: { notification_uuid: notificationId } }).select("id").single();
    if (ledger.error || !ledger.data?.id) throw new Error("webhook_ledger_failed");
    ledgerId = String((ledger.data as any).id);
    const signedTransaction = verified.data?.signedTransactionInfo; if (!signedTransaction) throw new Error("notification_transaction_missing");
    const transaction: any = await verifier.verifyAndDecodeTransaction(signedTransaction);
    const signedRenewal = verified.data?.signedRenewalInfo;
    const renewal: any = signedRenewal ? await verifier.verifyAndDecodeRenewalInfo(signedRenewal) : {};
    const { data: rawSubscription } = await admin.from("sd_player_subscriptions").select("org_id,player_id,billing_user_id").eq("provider", "apple").eq("original_transaction_id", String(transaction.originalTransactionId ?? "")).maybeSingle();
    const subscription = rawSubscription as any;
    if (!subscription?.org_id || !subscription.player_id || !subscription.billing_user_id) throw new Error("notification_subscription_context_missing");
    await syncAppleSubscription({ admin, transaction, orgId: subscription.org_id, playerId: subscription.player_id, billingUserId: subscription.billing_user_id, status: appleStatus({ ...transaction, autoRenewStatus: renewal.autoRenewStatus }, String(verified.notificationType ?? "")), notificationType: String(verified.notificationType ?? "") });
    await admin.from("sd_webhook_events").update({ processing_status: "processed", processed_at: new Date().toISOString(), error_message: null }).eq("id", ledgerId);
    return json(200, { received: true });
  } catch (error) {
    const message = error instanceof Error ? error.message : "apple_notification_verification_failed";
    if (admin && ledgerId) {
      await admin.from("sd_webhook_events").update({ processing_status: "failed", error_message: message.split(":", 1)[0] }).eq("id", ledgerId);
    }
    return json(400, { error: message });
  }
});
