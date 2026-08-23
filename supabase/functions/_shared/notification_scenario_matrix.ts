export type NotificationScenario = {
  id: string;
  category: string;
  route: string;
  source: "payment_request" | "payment_webhook" | "announcement" | "chat" | "event" | "system";
  recipients: Array<"owner" | "admin" | "coach" | "player" | "parent">;
  dismissAfterFirstOpen?: boolean;
};

export const notificationScenarioMatrix: NotificationScenario[] = [
  { id: "event-created", category: "event_created", route: "team_event", source: "event", recipients: ["coach", "player", "parent"] },
  { id: "event-updated", category: "event_updated", route: "team_event", source: "event", recipients: ["coach", "player", "parent"] },
  { id: "event-canceled", category: "event_canceled", route: "team_event", source: "event", recipients: ["coach", "player", "parent"], dismissAfterFirstOpen: true },
  { id: "event-postponed", category: "event_postponed", route: "team_event", source: "event", recipients: ["coach", "player", "parent"] },
  { id: "event-reminder", category: "event_reminder", route: "team_event", source: "event", recipients: ["coach", "player", "parent"] },
  { id: "booking-requested", category: "booking_created", route: "notification_detail", source: "event", recipients: ["owner", "admin", "coach"] },
  { id: "booking-approved", category: "booking_updated", route: "notification_detail", source: "event", recipients: ["player", "parent"] },
  { id: "booking-denied", category: "booking_updated", route: "notification_detail", source: "event", recipients: ["player", "parent"] },
  { id: "booking-canceled", category: "booking_updated", route: "notification_detail", source: "event", recipients: ["coach", "player", "parent"], dismissAfterFirstOpen: true },
  { id: "direct-message", category: "message_received", route: "chat_conversation", source: "chat", recipients: ["owner", "admin", "coach", "player", "parent"] },
  { id: "group-message", category: "message_received", route: "chat_conversation", source: "chat", recipients: ["owner", "admin", "coach", "player", "parent"] },
  { id: "message-attachment", category: "message_received", route: "chat_conversation", source: "chat", recipients: ["owner", "admin", "coach", "player", "parent"] },
  { id: "message-reaction", category: "message_received", route: "chat_conversation", source: "chat", recipients: ["owner", "admin", "coach", "player", "parent"] },
  { id: "program-assigned", category: "program_assigned", route: "notification_detail", source: "system", recipients: ["player", "parent"] },
  { id: "program-updated", category: "program_updated", route: "notification_detail", source: "system", recipients: ["player", "parent"] },
  { id: "testing-result", category: "testing_result_added", route: "notification_detail", source: "system", recipients: ["coach", "player", "parent"] },
  { id: "payment-requested", category: "payment_request_created", route: "payment_request", source: "payment_request", recipients: ["player", "parent"] },
  { id: "payment-received", category: "payment_received", route: "payment", source: "payment_webhook", recipients: ["owner", "admin", "coach", "player", "parent"] },
  { id: "payment-refunded", category: "payment_notice", route: "payment", source: "payment_webhook", recipients: ["owner", "admin", "player", "parent"] },
  { id: "attendance-response", category: "attendance", route: "team_event", source: "event", recipients: ["owner", "admin", "coach"] },
  { id: "organization-announcement", category: "organization_announcement", route: "notification_detail", source: "announcement", recipients: ["owner", "admin", "coach", "player", "parent"] },
  { id: "game-starting", category: "game_starting", route: "game_detail", source: "event", recipients: ["coach", "player", "parent"] },
  { id: "game-final", category: "game_final", route: "game_detail", source: "event", recipients: ["coach", "player", "parent"] },
];
