import SwiftUI

/// Coach-facing player profile with Shiny-style top tabs.
struct CoachPlayerProfileView: View {
  @EnvironmentObject private var appState: AppState
  let player: Profile

  enum Tab: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case calendar = "Calendar"
    case testing = "Testing"
    case program = "Program"
    case analysis = "Analysis"
    var id: String { rawValue }
  }

  @State private var tab: Tab = .overview

  var body: some View {
    content
      .background(DHDTheme.pageBackground)
      .toolbar {
#if os(macOS)
        ToolbarItem(placement: .automatic) {
          Picker("", selection: $tab) {
            ForEach(Tab.allCases) { t in
              Text(t.rawValue).tag(t)
            }
          }
          .pickerStyle(.segmented)
          .frame(maxWidth: 520)
        }
#else
        ToolbarItem(placement: .principal) {
          Picker("", selection: $tab) {
            ForEach(Tab.allCases) { t in
              Text(t.rawValue).tag(t)
            }
          }
          .pickerStyle(.segmented)
        }
#endif
      }
      .navigationTitle(player.displayName)
      #if !os(macOS)
      .navigationBarTitleDisplayMode(.inline)
      #endif
  }

  @ViewBuilder
  private var content: some View {
    switch tab {
    case .overview:
      CoachPlayerOverviewView(player: player)
    case .calendar:
      CoachPlayerCalendarView(player: player)
    case .testing:
      CoachPlayerTestingCRUDView(player: player)
    case .program:
      CoachPlayerProgramAssignerView(player: player)
    case .analysis:
      CoachPlayerAnalysisView(player: player)
    }
  }
}

private struct CoachPlayerProgramAssignerView: View {
  @EnvironmentObject private var appState: AppState
  let player: Profile

  @State private var activeAssignment: SDProgramAssignment?
  @State private var activeTemplate: SDProgramTemplate?
  @State private var coachTemplates: [SDProgramTemplate] = []
  @State private var selectedTemplateId: UUID?
  @State private var startDate = Date()
  @State private var notes = ""
  @State private var isWorking = false
  @State private var errorText: String?
  @State private var toastText: String?
  @State private var parentEmail = ""
  @State private var parentRelationship = ""
  @State private var parentInvites: [SDParentInvite] = []
  @State private var parentLinks: [SDParentChildLink] = []
  @State private var paymentRequests: [SDPaymentRequest] = []

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 14) {
        DHDHeaderCard {
          HStack {
            VStack(alignment: .leading, spacing: 4) {
              Text("Program assignment")
                .font(.title3.weight(.semibold))
              Text(player.displayName)
                .font(.caption)
                .foregroundStyle(Color.white.opacity(0.85))
            }
            Spacer()
            if isWorking { ProgressView().tint(.white) }
          }
          .foregroundStyle(.white)
        }

        DHDCard {
          VStack(alignment: .leading, spacing: 12) {
            DHDSectionHeader("Current program") {
              if activeAssignment != nil {
                DHDStatusBadge(text: "Active", color: .green)
              }
            }

            if let a = activeAssignment, let t = activeTemplate {
              DHDFormRow("Template") { Text(t.name) }
              DHDFormRow("Start") { Text(a.start_date) }
              DHDFormRow("Days/week") { Text("\(t.lift_weekdays.count)") }
              DHDFormRow("Weekdays") { Text(weekdayLabel(t.lift_weekdays)) }

              Divider().overlay(DHDTheme.separator.opacity(0.35))

              Button(role: .destructive) {
                Task { await endProgram() }
              } label: {
                Label("End current program", systemImage: "xmark.circle")
                  .frame(maxWidth: .infinity, alignment: .leading)
              }
              .disabled(isWorking)
            } else {
              Text("No active program assigned.")
                .foregroundStyle(DHDTheme.textSecondary)
            }
          }
        }

        DHDCard {
          VStack(alignment: .leading, spacing: 12) {
            DHDSectionHeader("Assign new program") {
              EmptyView()
            }

            if coachTemplates.isEmpty {
              Text("No templates yet. Create one in Program Templates.")
                .foregroundStyle(DHDTheme.textSecondary)
            } else {
              Picker("Template", selection: $selectedTemplateId) {
                Text("Select…").tag(UUID?.none)
                ForEach(coachTemplates) { t in
                  Text(t.name).tag(UUID?.some(t.id))
                }
              }

              DatePicker("Start date", selection: $startDate, displayedComponents: .date)

              TextField("Notes (optional)", text: $notes)
                .textFieldStyle(.roundedBorder)

              Button {
                Task { await assignProgram() }
              } label: {
                Label("Assign", systemImage: "checkmark.circle")
                  .frame(maxWidth: .infinity)
              }
              .buttonStyle(.borderedProminent)
              .disabled(isWorking || selectedTemplateId == nil)
            }
          }
        }

        DHDCard {
          VStack(alignment: .leading, spacing: 12) {
            DHDSectionHeader("Parents") { EmptyView() }

            Text("Invite a parent/guardian to view this player (view-only) and request bookings/payments.")
              .font(.caption)
              .foregroundStyle(DHDTheme.textSecondary)

            HStack(spacing: 10) {
              TextField("Parent email", text: $parentEmail)
                .textFieldStyle(.roundedBorder)
              TextField("Relationship (optional)", text: $parentRelationship)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 220)
              Button {
                Task { await sendParentInvite() }
              } label: {
                Label("Invite", systemImage: "paperplane")
              }
              .buttonStyle(.borderedProminent)
              .disabled(isWorking || parentEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if !parentLinks.isEmpty {
              Divider().overlay(DHDTheme.separator.opacity(0.35))
              Text("Linked parents")
                .font(.headline)
              ForEach(parentLinks, id: \.id) { link in
                Text("Parent \(link.parent_id.uuidString.prefix(6).uppercased()) • \(link.relationship ?? "—")")
                  .font(.caption)
                  .foregroundStyle(DHDTheme.textSecondary)
              }
            }

            if !parentInvites.isEmpty {
              Divider().overlay(DHDTheme.separator.opacity(0.35))
              Text("Invites")
                .font(.headline)
              ForEach(parentInvites) { inv in
                HStack {
                  VStack(alignment: .leading, spacing: 2) {
                    Text(inv.email_norm).font(.subheadline)
                    Text(inv.accepted_at == nil ? "Pending" : "Accepted")
                      .font(.caption)
                      .foregroundStyle(DHDTheme.textSecondary)
                  }
                  Spacer()
                }
              }
            }
          }
        }

        DHDCard {
          VStack(alignment: .leading, spacing: 12) {
            DHDSectionHeader("Payment requests") { EmptyView() }
            if paymentRequests.isEmpty {
              Text("No payment requests for this player.")
                .foregroundStyle(DHDTheme.textSecondary)
            } else {
              ForEach(paymentRequests) { r in
                HStack {
                  VStack(alignment: .leading, spacing: 2) {
                    Text(r.plan_name ?? "Payment").font(.headline)
                    Text(r.status.capitalized).font(.caption).foregroundStyle(DHDTheme.textSecondary)
                  }
                  Spacer()
                  Menu("Update") {
                    Button("Mark paid") { Task { await setPaymentStatus(r.id, "paid") } }
                    Button("Approve") { Task { await setPaymentStatus(r.id, "approved") } }
                    Button("Cancel", role: .destructive) { Task { await setPaymentStatus(r.id, "cancelled") } }
                  }
                }
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
    .alert("Error", isPresented: Binding(get: { errorText != nil }, set: { _ in errorText = nil })) {
      Button("OK", role: .cancel) {}
    } message: { Text(errorText ?? "") }
    .dhdToast($toastText)
    .task { await reload() }
  }

  private func reload() async {
    guard let supabase = appState.supabase else { return }
    isWorking = true
    defer { isWorking = false }
    do {
      coachTemplates = try await supabase.listMyCoachTemplates()
      activeAssignment = try await supabase.fetchActiveAssignment(playerId: player.id)
      if let activeAssignment {
        activeTemplate = try await supabase.fetchTemplate(id: activeAssignment.template_id)
      } else {
        activeTemplate = nil
      }
      parentInvites = try await supabase.coachListParentInvites(childId: player.id)
      parentLinks = try await supabase.coachListParentLinks(childId: player.id)
      paymentRequests = try await supabase.listMyPaymentRequests(childId: player.id)
    } catch {
      errorText = error.localizedDescription
    }
  }

  private func assignProgram() async {
    guard let supabase = appState.supabase else { return }
    guard let templateId = selectedTemplateId else { return }
    isWorking = true
    defer { isWorking = false }
    do {
      let dateISO = DateUtils.toISODate(startDate)
      _ = try await supabase.assignProgram(
        templateId: templateId,
        playerId: player.id,
        startDateISO: dateISO,
        notes: notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : notes,
        orgId: appState.activeOrgId
      )
      toastText = "Assigned"
      await reload()
    } catch {
      errorText = error.localizedDescription
    }
  }

  private func endProgram() async {
    guard let supabase = appState.supabase else { return }
    guard let a = activeAssignment else { return }
    isWorking = true
    defer { isWorking = false }
    do {
      try await supabase.endAssignment(assignmentId: a.id)
      toastText = "Ended"
      await reload()
    } catch {
      errorText = error.localizedDescription
    }
  }

  private func sendParentInvite() async {
    guard let supabase = appState.supabase else { return }
    isWorking = true
    defer { isWorking = false }
    do {
      let rel = parentRelationship.trimmingCharacters(in: .whitespacesAndNewlines)
      _ = try await supabase.coachCreateParentInvite(
        childId: player.id,
        parentEmail: parentEmail,
        relationship: rel.isEmpty ? nil : rel
      )
      toastText = "Invited"
      parentEmail = ""
      parentRelationship = ""
      await reload()
    } catch {
      errorText = error.localizedDescription
    }
  }

  private func setPaymentStatus(_ requestId: UUID, _ status: String) async {
    guard let supabase = appState.supabase else { return }
    isWorking = true
    defer { isWorking = false }
    do {
      try await supabase.coachUpdatePaymentRequestStatus(requestId: requestId, status: status)
      toastText = "Updated"
      await reload()
    } catch {
      errorText = error.localizedDescription
    }
  }

  private func weekdayLabel(_ days: [Int]) -> String {
    let map: [Int: String] = [1: "Mon", 2: "Tue", 3: "Wed", 4: "Thu", 5: "Fri", 6: "Sat", 7: "Sun"]
    return days.compactMap { map[$0] }.joined(separator: ", ")
  }
}
