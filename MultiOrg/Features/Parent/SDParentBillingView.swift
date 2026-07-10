import SwiftUI

/// Parent billing: manual "pay on behalf" request (no Stripe yet).
struct SDParentBillingView: View {
  @EnvironmentObject private var appState: AppState
  let child: Profile

  @State private var requests: [SDPaymentRequest] = []
  @State private var isLoading = false
  @State private var errorText: String?
  @State private var toastText: String?

  @State private var planName = "Membership"
  @State private var amountDollars = ""
  @State private var notes = ""

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 14) {
        DHDHeaderCard {
          HStack {
            VStack(alignment: .leading, spacing: 4) {
              Text("Billing")
                .font(.title3.weight(.semibold))
              Text("Request payment for \(child.displayName)")
                .font(.caption)
                .foregroundStyle(Color.white.opacity(0.85))
            }
            Spacer()
            if isLoading { ProgressView().tint(.white) }
          }
          .foregroundStyle(.white)
        }

        DHDCard {
          VStack(alignment: .leading, spacing: 12) {
            DHDSectionHeader("Request payment") { EmptyView() }
            TextField("Plan name", text: $planName)
              .textFieldStyle(.roundedBorder)
            TextField("Amount (USD)", text: $amountDollars)
              .textFieldStyle(.roundedBorder)
            TextField("Notes (optional)", text: $notes, axis: .vertical)
              .lineLimit(3...6)
              .textFieldStyle(.roundedBorder)
            Button {
              Task { await createRequest() }
            } label: {
              Label("Submit request", systemImage: "paperplane")
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
          }
        }

        DHDCard(style: .flat) {
          VStack(alignment: .leading, spacing: 10) {
            DHDSectionHeader("Requests") { EmptyView() }
            if requests.isEmpty, !isLoading {
              Text("No requests yet.")
                .foregroundStyle(DHDTheme.textSecondary)
            } else {
              ForEach(requests) { r in
                HStack {
                  VStack(alignment: .leading, spacing: 4) {
                    Text(r.plan_name ?? "Payment")
                      .font(.headline)
                    Text(statusLabel(r))
                      .font(.caption)
                      .foregroundStyle(DHDTheme.textSecondary)
                  }
                  Spacer()
                  if let cents = r.amount_cents {
                    Text("$" + String(format: "%.2f", Double(cents) / 100.0))
                      .foregroundStyle(DHDTheme.textSecondary)
                  }
                }
                .padding(.vertical, 6)
                Divider().overlay(DHDTheme.separator.opacity(0.25))
              }
            }
          }
        }
      }
      .padding(DHDTheme.pagePadding)
      .frame(maxWidth: .infinity, alignment: .leading)
      .frame(maxHeight: .infinity, alignment: .topLeading)
    }
    .background(DHDTheme.pageBackground)
    .dhdToast($toastText)
    .alert("Error", isPresented: Binding(get: { errorText != nil }, set: { _ in errorText = nil })) {
      Button("OK", role: .cancel) {}
    } message: { Text(errorText ?? "") }
    .task { await reload() }
  }

  private func reload() async {
    guard let supabase = appState.supabase else { return }
    isLoading = true
    defer { isLoading = false }
    do {
      requests = try await supabase.listMyPaymentRequests(childId: child.id)
    } catch {
      errorText = error.localizedDescription
    }
  }

  private func createRequest() async {
    guard let supabase = appState.supabase else { return }
    isLoading = true
    defer { isLoading = false }
    do {
      let cleanPlan = planName.trimmingCharacters(in: .whitespacesAndNewlines)
      let plan = cleanPlan.isEmpty ? nil : cleanPlan

      let dollars = amountDollars.trimmingCharacters(in: .whitespacesAndNewlines)
      let cents: Int?
      if dollars.isEmpty {
        cents = nil
      } else if let d = Double(dollars) {
        cents = Int((d * 100).rounded())
      } else {
        throw NSError(domain: "Billing", code: 1, userInfo: [NSLocalizedDescriptionKey: "Amount must be a number (e.g., 99.00)."])
      }

      _ = try await supabase.createPaymentRequest(
        childId: child.id,
        planName: plan,
        amountCents: cents,
        currency: "usd",
        notes: notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : notes
      )
      toastText = "Requested"
      amountDollars = ""
      notes = ""
      await reload()
    } catch {
      errorText = error.localizedDescription
    }
  }

  private func statusLabel(_ r: SDPaymentRequest) -> String {
    let status = r.status.capitalized
    if let d = r.created_at {
      let df = DateFormatter()
      df.dateStyle = .medium
      df.timeStyle = .short
      return "\(status) • \(df.string(from: d))"
    }
    return status
  }
}
