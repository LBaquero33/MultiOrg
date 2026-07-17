import SwiftUI

struct PaymentRequestCard: View {
  let request: SDPaymentRequest
  let organizationName: String
  let playerName: String
  let context: SDPaymentRequestPayerContext
  let checkoutState: SDPaymentCheckoutState
  let onPay: () -> Void

  var body: some View {
    HPCard(style: .flat) {
      VStack(alignment: .leading, spacing: HP.Space.sm) {
        VStack(alignment: .leading, spacing: 3) {
          Text(organizationName)
            .font(HP.Font.caption)
            .foregroundStyle(HP.Color.textMuted)
          if context == .parent {
            Text(playerName)
              .font(HP.Font.caption.weight(.semibold))
              .foregroundStyle(HP.Color.textMuted)
          }
        }
        HPSectionHeader(request.title) {
          HPStatusBadge(
            text: request.status.rawValue.capitalized,
            kind: statusKind
          )
        }

        if let description = request.description, !description.isEmpty {
          Text(description)
            .font(HP.Font.callout)
            .foregroundStyle(HP.Color.textMuted)
            .fixedSize(horizontal: false, vertical: true)
        }

        ViewThatFits(in: .horizontal) {
          HStack(alignment: .firstTextBaseline, spacing: HP.Space.sm) {
            amountLabel
            Spacer(minLength: HP.Space.sm)
            dueDateLabel
          }
          VStack(alignment: .leading, spacing: HP.Space.xs) {
            amountLabel
            dueDateLabel
          }
        }

        payerAction

        if checkoutState.isProcessing(request.id) {
          Label("Waiting for secure payment confirmation…", systemImage: "clock.arrow.circlepath")
            .font(HP.Font.caption)
            .foregroundStyle(HP.Color.textMuted)
            .fixedSize(horizontal: false, vertical: true)
        }
        if let message = checkoutState.errorMessage(for: request.id) {
          Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(HP.Font.caption)
            .foregroundStyle(HP.Color.danger)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
    }
  }

  private var amountLabel: some View {
    Text(request.money?.formatted() ?? "Amount unavailable")
      .font(HP.Font.number(.title3))
      .foregroundStyle(HP.Color.text)
  }

  @ViewBuilder
  private var dueDateLabel: some View {
    if let dueDate = request.due_date {
      Text("Due \(displayDate(dueDate))")
        .font(HP.Font.caption)
        .foregroundStyle(HP.Color.textMuted)
    }
  }

  @ViewBuilder
  private var payerAction: some View {
    switch SDPaymentRequestPayerAuthorization.action(for: request, context: context) {
    case .payNow:
      HPButton(
        title: checkoutState.isOpening(request.id) ? "Opening Stripe Checkout…" : "Pay Now",
        systemImage: "creditcard",
        variant: .secondary,
        size: .md,
        isLoading: checkoutState.isOpening(request.id),
        fullWidth: true,
        action: onPay
      )
      .disabled(checkoutState.isMutationInFlight)
    case .unavailable(let reason):
      Text(reason)
        .font(HP.Font.caption)
        .foregroundStyle(HP.Color.textMuted)
        .fixedSize(horizontal: false, vertical: true)
    case .hidden:
      EmptyView()
    }
  }

  private var statusKind: HPStatusKind {
    switch request.status {
    case .open: return .warning
    case .canceled: return .neutral
    case .paid: return .success
    }
  }

  private func displayDate(_ value: String) -> String {
    let input = DateFormatter()
    input.locale = Locale(identifier: "en_US_POSIX")
    input.dateFormat = "yyyy-MM-dd"
    guard let date = input.date(from: value) else { return value }
    return date.formatted(date: .abbreviated, time: .omitted)
  }
}
struct PaymentCheckoutConfirmationSheet: View {
  @Environment(\.dismiss) private var dismiss
  let request: SDPaymentRequest
  let organizationName: String
  let playerName: String
  let onConfirm: () -> Void

  var body: some View {
    NavigationStack {
      HPFormScreenLayout { _ in
        HPWorkspaceHeader(
          "Open Stripe Checkout?",
          orgLabel: organizationName,
          context: playerName
        )
      } sections: { _ in
        HPCard {
          VStack(alignment: .leading, spacing: HP.Space.sm) {
            HPSectionHeader("Secure payment")
            LabeledContent("Organization", value: organizationName)
            LabeledContent("Player", value: playerName)
            LabeledContent("Request", value: request.title)
            LabeledContent("Amount", value: request.money?.formatted() ?? "Unavailable")
          }
        }

        HPCard {
          Text("You will continue in Stripe’s hosted Checkout. Returning to Home Plate does not mark the request paid; payment is confirmed only after the server receives Stripe’s verified webhook.")
            .font(HP.Font.caption)
            .foregroundStyle(HP.Color.textMuted)
            .fixedSize(horizontal: false, vertical: true)
        }
      } primaryAction: { context in
        HPButton(
          title: "Continue",
          systemImage: "arrow.up.right.square",
          variant: .primary,
          size: .lg,
          fullWidth: context.isAccessibilitySize
        ) {
          dismiss()
          onConfirm()
        }
      } secondaryAction: { _ in
        EmptyView()
      }
      .navigationTitle("Open Stripe Checkout?")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
            #if os(macOS)
            .keyboardShortcut(.cancelAction)
            #endif
        }
      }
    }
    #if os(macOS)
    .frame(minWidth: 480, minHeight: 330)
    #endif
  }
}
