import SwiftUI

struct PaymentRequestCard: View {
  let request: SDPaymentRequest
  let organizationName: String
  let playerName: String
  let context: SDPaymentRequestPayerContext
  let checkoutState: SDPaymentCheckoutState
  let onPay: () -> Void

  var body: some View {
    DHDCard(style: .flat) {
      VStack(alignment: .leading, spacing: 9) {
        HStack(alignment: .firstTextBaseline) {
          VStack(alignment: .leading, spacing: 3) {
            Text(organizationName)
              .font(.caption)
              .foregroundStyle(DHDTheme.textSecondary)
            if context == .parent {
              Text(playerName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(DHDTheme.textSecondary)
            }
            Text(request.title).font(.headline)
          }
          Spacer()
          DHDStatusBadge(
            text: request.status.rawValue.capitalized,
            color: statusColor
          )
        }

        if let description = request.description, !description.isEmpty {
          Text(description)
            .font(.subheadline)
            .foregroundStyle(DHDTheme.textSecondary)
        }

        HStack {
          Text(request.money?.formatted() ?? "Amount unavailable")
            .font(.subheadline.weight(.semibold))
          Spacer()
          if let dueDate = request.due_date {
            Text("Due \(displayDate(dueDate))")
              .font(.caption)
              .foregroundStyle(DHDTheme.textSecondary)
          }
        }

        payerAction

        if checkoutState.isProcessing(request.id) {
          Label("Waiting for secure payment confirmation…", systemImage: "clock.arrow.circlepath")
            .font(.footnote)
            .foregroundStyle(DHDTheme.textSecondary)
        }
        if let message = checkoutState.errorMessage(for: request.id) {
          Text(message)
            .font(.footnote)
            .foregroundStyle(.red)
        }
      }
    }
  }

  @ViewBuilder
  private var payerAction: some View {
    switch SDPaymentRequestPayerAuthorization.action(for: request, context: context) {
    case .payNow:
      Button(action: onPay) {
        Label(
          checkoutState.isOpening(request.id) ? "Opening Stripe Checkout…" : "Pay Now",
          systemImage: "creditcard"
        )
      }
      .buttonStyle(.borderedProminent)
      .disabled(checkoutState.isMutationInFlight)
    case .unavailable(let reason):
      Text(reason)
        .font(.footnote)
        .foregroundStyle(DHDTheme.textSecondary)
    case .hidden:
      EmptyView()
    }
  }

  private var statusColor: Color {
    switch request.status {
    case .open: return .orange
    case .canceled: return .secondary
    case .paid: return .green
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
      Form {
        Section("Secure payment") {
          LabeledContent("Organization", value: organizationName)
          LabeledContent("Player", value: playerName)
          LabeledContent("Request", value: request.title)
          LabeledContent("Amount", value: request.money?.formatted() ?? "Unavailable")
        }
        Section {
          Text("You will continue in Stripe’s hosted Checkout. Returning to Home Plate does not mark the request paid; payment is confirmed only after the server receives Stripe’s verified webhook.")
            .font(.footnote)
            .foregroundStyle(DHDTheme.textSecondary)
        }
      }
      .navigationTitle("Open Stripe Checkout?")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Continue") {
            dismiss()
            onConfirm()
          }
        }
      }
    }
    #if os(macOS)
    .frame(minWidth: 480, minHeight: 330)
    #endif
  }
}
