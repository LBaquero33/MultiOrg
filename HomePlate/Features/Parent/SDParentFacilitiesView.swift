import SwiftUI

/// Parent-facing facilities scheduling for a specific child.
/// Parents can request times and cancel their own pending requests.
struct SDParentFacilitiesView: View {
  @EnvironmentObject private var appState: AppState
  let child: Profile

  @State private var facilities: [SDFacility] = []
  @State private var isLoading = false
  @State private var errorText: String?
  @State private var toastText: String?

  @State private var visibleMonth: Date = DateUtils.startOfMonthET(Date())
  @State private var selectedDate: Date = DateUtils.startOfDayET(Date())

  @State private var approvedISOs: Set<String> = []
  @State private var pendingISOs: Set<String> = []
  @State private var deniedISOs: Set<String> = []

  @State private var dayBookings: [SDFacilityBooking] = []
  @State private var rangeBookings: [SDFacilityBooking] = []
  @State private var compactScope = "month"

  @State private var showRequest = false
  @State private var requestSeed: RequestSeed?

  private struct RequestSeed: Identifiable {
    let id = UUID()
    let facilityId: UUID
    let startAt: Date
    let durationMin: Int
  }

  var body: some View {
    HPCalendarScreenLayout(
      compactPane: compactScope == "month" ? .calendar : .agenda
    ) { context in
      HPWorkspaceHeader(
        "Facilities",
        orgLabel: activeOrganizationName,
        context: "Booking for \(child.displayName)"
      ) {
        HPButton(
          title: "Request time",
          systemImage: "plus",
          variant: .primary,
          size: .sm,
          fullWidth: context.isAccessibilitySize,
          action: { showRequest = true }
        )
      }
    } scopeControl: { context in
      if context.isAccessibilitySize {
        HPCard {
          VStack(alignment: .leading, spacing: HP.Space.sm) {
            HPSectionHeader("Selected day")
            DatePicker(
              "Date",
              selection: accessibleDateSelection,
              displayedComponents: .date
            )
            HPButton(
              title: "Previous day",
              systemImage: "chevron.left",
              variant: .secondary,
              size: .md,
              fullWidth: true,
              action: { moveAccessibleDay(by: -1) }
            )
            HPButton(
              title: "Today",
              systemImage: "calendar",
              variant: .secondary,
              size: .md,
              fullWidth: true,
              action: { selectAccessibleDate(Date()) }
            )
            HPButton(
              title: "Next day",
              systemImage: "chevron.right",
              variant: .secondary,
              size: .md,
              fullWidth: true,
              action: { moveAccessibleDay(by: 1) }
            )
          }
        }
      } else {
        HPCard {
          HPSegmentedControl(
            options: [(value: "month", label: "Month"), (value: "day", label: "Day")],
            selection: $compactScope
          )
        }
      }
    } calendar: { context in
      calendarPane(context)
    } agenda: { context in
      facilitiesAgendaPane(context)
    } stateContent: { _ in
      EmptyView()
    }
    .dhdToast($toastText)
    .toolbar {
      ToolbarItem(placement: .automatic) {
        Button {
          Task { await reloadAll() }
        } label: {
          Image(systemName: "arrow.clockwise")
        }
      }
    }
    .sheet(isPresented: $showRequest) {
      ParentRequestBookingSheet(
        child: child,
        facilities: facilities,
        defaultDate: selectedDate,
        seed: nil,
        onCreated: {
          toastText = "Request sent"
          Task { await reloadAll() }
        }
      )
      .environmentObject(appState)
    }
    .sheet(item: $requestSeed) { seed in
      ParentRequestBookingSheet(
        child: child,
        facilities: facilities,
        defaultDate: seed.startAt,
        seed: .init(facilityId: seed.facilityId, startAt: seed.startAt, durationMin: seed.durationMin),
        onCreated: {
          toastText = "Request sent"
          Task { await reloadAll() }
        }
      )
      .environmentObject(appState)
    }
    .alert("Error", isPresented: Binding(get: { errorText != nil }, set: { _ in errorText = nil })) {
      Button("OK", role: .cancel) {}
    } message: { Text(errorText ?? "") }
    .task {
      await reloadAll()
    }
  }

  private var activeOrganizationName: String {
    appState.availableOrganizations.first(where: { $0.id == appState.activeOrgId })?.name
      ?? appState.activeOrgSettings?.display_name
      ?? appState.activeOrgSettings?.short_name
      ?? "Home Plate"
  }

  private func calendarPane(_ context: HPScreenLayoutContext) -> some View {
    VStack(alignment: .leading, spacing: HP.Space.sm) {
      DHDMonthGridView(
        visibleMonth: $visibleMonth,
        selectedDate: $selectedDate,
        scheduledLiftISOs: approvedISOs,
        practiceISOs: pendingISOs,
        gameISOs: deniedISOs,
        isLoading: isLoading,
        onPrev: {
          visibleMonth = DateUtils.startOfMonthET(DateUtils.addMonthsET(visibleMonth, value: -1))
          Task { await reloadMonth() }
        },
        onNext: {
          visibleMonth = DateUtils.startOfMonthET(DateUtils.addMonthsET(visibleMonth, value: 1))
          Task { await reloadMonth() }
        },
        onSelect: { date in
          selectedDate = DateUtils.startOfDayET(date)
          if !context.isRegularWidth {
            compactScope = "day"
          }
          Task { await loadDay() }
        }
      )

      Text("Green = approved booking. Blue = your pending request.")
        .font(HP.Font.caption)
        .foregroundStyle(HP.Color.textMuted)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  private var dayPane: some View {
    HPCard {
      VStack(alignment: .leading, spacing: HP.Space.sm) {
        HPSectionHeader(selectedDate.formatted(date: .complete, time: .omitted))
        if isLoading {
          HPLoadingState(text: "Loading facilities…")
        }
        FacilitiesDayTimelineView(
          mode: .player(myUserId: appState.myProfile?.id ?? UUID()),
          date: selectedDate,
          facilities: facilities,
          bookings: dayBookings,
          userNameById: [:],
          onApprove: { _ in },
          onDeny: { _ in },
          onMove: { _, _, _, _ in },
          onResizeSpan: nil,
          onCancelOwnPending: { booking in
            Task { await cancelPending(booking) }
          },
          onEdit: nil,
          onCreateAt: { facilityId, startAt in
            requestSeed = RequestSeed(facilityId: facilityId, startAt: startAt, durationMin: 60)
          }
        )
      }
    }
  }

  @ViewBuilder
  private func facilitiesAgendaPane(_ context: HPScreenLayoutContext) -> some View {
    if context.isAccessibilitySize {
      HPCard {
        VStack(alignment: .leading, spacing: HP.Space.sm) {
          HPSectionHeader("Month agenda")
          ForEach(monthDates, id: \.self) { date in
            monthAgendaRow(date)
          }
        }
      }
    }
    dayPane
  }

  private var monthDates: [Date] {
    let first = DateUtils.startOfMonthET(visibleMonth)
    return (0..<DateUtils.daysInMonthET(first)).compactMap {
      DateUtils.calendarET.date(byAdding: .day, value: $0, to: first)
    }
  }

  private func monthAgendaRow(_ date: Date) -> some View {
    let labels = bookingStatusLabels(for: DateUtils.toISODate(date))
    return Button {
      selectAccessibleDate(date)
    } label: {
      HStack(alignment: .center, spacing: HP.Space.sm) {
        VStack(alignment: .leading, spacing: 2) {
          Text(date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
            .font(HP.Font.callout.weight(.semibold))
            .foregroundStyle(HP.Color.text)
            .fixedSize(horizontal: false, vertical: true)
          Text(labels.isEmpty ? "No facility requests" : labels.joined(separator: " · "))
            .font(HP.Font.caption)
            .foregroundStyle(HP.Color.textMuted)
            .fixedSize(horizontal: false, vertical: true)
        }
        Spacer(minLength: HP.Space.sm)
        Image(systemName: "chevron.right")
          .font(.caption.weight(.semibold))
          .foregroundStyle(HP.Color.textMuted)
          .accessibilityHidden(true)
      }
      .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(
      labels.isEmpty
        ? "\(date.formatted(date: .long, time: .omitted)), no facility requests"
        : "\(date.formatted(date: .long, time: .omitted)), \(labels.joined(separator: ", "))"
    )
  }

  private func bookingStatusLabels(for iso: String) -> [String] {
    var labels: [String] = []
    if approvedISOs.contains(iso) { labels.append("Approved booking") }
    if pendingISOs.contains(iso) { labels.append("Your pending request") }
    if deniedISOs.contains(iso) { labels.append("Unavailable or denied") }
    return labels
  }

  private var accessibleDateSelection: Binding<Date> {
    Binding(
      get: { selectedDate },
      set: { selectAccessibleDate($0) }
    )
  }

  private func moveAccessibleDay(by value: Int) {
    let date = DateUtils.calendarET.date(byAdding: .day, value: value, to: selectedDate) ?? selectedDate
    selectAccessibleDate(date)
  }

  private func selectAccessibleDate(_ date: Date) {
    let day = DateUtils.startOfDayET(date)
    let month = DateUtils.startOfMonthET(day)
    let monthChanged = month != DateUtils.startOfMonthET(visibleMonth)
    selectedDate = day
    visibleMonth = month
    Task {
      if monthChanged { await reloadMonth() }
      await loadDay()
    }
  }

  private func reloadAll() async {
    await reloadMonth()
    await loadDay()
  }

  private func reloadMonth() async {
    guard let supabase = appState.supabase else { return }
    isLoading = true
    defer { isLoading = false }
    do {
      facilities = try await supabase.listFacilities(orgId: appState.activeOrgId)

      let first = DateUtils.startOfMonthET(visibleMonth)
      let end = DateUtils.addMonthsET(first, value: 1)
      rangeBookings = try await supabase.listFacilityBookings(rangeStart: first, rangeEnd: end, orgId: appState.activeOrgId)
      rebuildDots()
    } catch {
      errorText = error.localizedDescription
    }
  }

  private func loadDay() async {
    guard let supabase = appState.supabase else { return }
    isLoading = true
    defer { isLoading = false }
    do {
      let start = DateUtils.startOfDayET(selectedDate)
      let end = DateUtils.calendarET.date(byAdding: .day, value: 1, to: start) ?? start
      dayBookings = try await supabase.listFacilityBookings(dayStart: start, dayEnd: end, orgId: appState.activeOrgId)
    } catch {
      errorText = error.localizedDescription
    }
  }

  private func rebuildDots() {
    var approved: Set<String> = []
    var pending: Set<String> = []
    var denied: Set<String> = []
    let myId = appState.myProfile?.id
    for b in rangeBookings {
      let iso = DateUtils.toISODate(b.start_at)
      switch b.status {
      case "approved": approved.insert(iso)
      case "pending":
        if let myId, b.created_by == myId { pending.insert(iso) }
      default: denied.insert(iso)
      }
    }
    approvedISOs = approved
    pendingISOs = pending
    deniedISOs = denied
  }

  private func cancelPending(_ booking: SDFacilityBooking) async {
    guard let supabase = appState.supabase else { return }
    isLoading = true
    defer { isLoading = false }
    do {
      _ = try await supabase.updateFacilityBooking(
        id: booking.id,
        facilityId: booking.facility_id,
        status: "cancelled",
        activityType: booking.activity_type,
        startAt: booking.start_at,
        endAt: booking.end_at,
        coachId: booking.coach_id,
        approved: false,
        title: booking.title,
        notes: booking.notes,
        spanFacilityId: booking.span_facility_id,
        orgId: appState.activeOrgId
      )
      toastText = "Cancelled"
      await reloadAll()
    } catch {
      errorText = error.localizedDescription
    }
  }
}

private struct ParentRequestBookingSheet: View {
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject private var appState: AppState

  let child: Profile
  let facilities: [SDFacility]
  let defaultDate: Date
  let seed: Seed?
  let onCreated: () -> Void

  struct Seed {
    let facilityId: UUID
    let startAt: Date
    let durationMin: Int
  }

  @State private var facilityId: UUID?
  @State private var activityType: String = "bp"
  @State private var start: Date = Date()
  @State private var durationMin: Int = 60
  @State private var notes: String = ""
  @State private var isFullCage3: Bool = false
  @State private var isSaving = false
  @State private var errorText: String?

  var body: some View {
    NavigationStack {
      HPFormScreenLayout { _ in
        HPWorkspaceHeader(
          "Request time",
          orgLabel: activeOrganizationName,
          context: "Booking for \(child.displayName) · Pending until approved"
        )
      } sections: { _ in
        whoSection
        whenSection
        detailsSection
        notesSection
        if let errorText, !errorText.isEmpty {
          HPCard {
            Label(errorText, systemImage: "exclamationmark.triangle.fill")
              .font(HP.Font.callout)
              .foregroundStyle(HP.Color.danger)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
      } primaryAction: { context in
        HPButton(
          title: "Request",
          systemImage: "paperplane.fill",
          variant: .primary,
          size: .lg,
          isLoading: isSaving,
          fullWidth: context.isAccessibilitySize,
          action: { Task { await save() } }
        )
        .disabled(isSaving || facilityId == nil)
      } secondaryAction: { context in
        HPButton(
          title: "Cancel",
          variant: .secondary,
          size: .lg,
          fullWidth: context.isAccessibilitySize,
          action: { dismiss() }
        )
      }
      .navigationTitle("Request time")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
            #if os(macOS)
            .keyboardShortcut(.cancelAction)
            #endif
        }
      }
      .task {
        facilityId = seed?.facilityId ?? facilities.first?.id
        start = seed?.startAt ?? defaultDate
        durationMin = seed?.durationMin ?? 60
      }
      .onChange(of: facilityId) { _, newValue in
        if newValue != cage3_1Id {
          isFullCage3 = false
        }
      }
    }
  }

  private var activeOrganizationName: String {
    appState.availableOrganizations.first(where: { $0.id == appState.activeOrgId })?.name
      ?? appState.activeOrgSettings?.display_name
      ?? appState.activeOrgSettings?.short_name
      ?? "Home Plate"
  }

  private var whoSection: some View {
    HPCard {
      VStack(alignment: .leading, spacing: HP.Space.sm) {
        HPSectionHeader("Who")
        HStack(spacing: HP.Space.sm) {
          HPAvatar(name: child.displayName, systemImage: "person.crop.circle", size: .md)
          Text(child.displayName)
            .font(HP.Font.headline)
            .foregroundStyle(HP.Color.text)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
    }
  }

  private var whenSection: some View {
    HPCard {
      VStack(alignment: .leading, spacing: HP.Space.md) {
        HPSectionHeader("When")
        DatePicker("Start", selection: $start)
        Divider().overlay(HP.Color.border)
        Picker("Duration", selection: $durationMin) {
          ForEach([30, 45, 60, 75, 90, 120], id: \.self) { minutes in
            Text("\(minutes) min").tag(minutes)
          }
        }
      }
      .font(HP.Font.callout)
      .foregroundStyle(HP.Color.text)
      .tint(HP.Color.accent)
    }
  }

  private var detailsSection: some View {
    HPCard {
      VStack(alignment: .leading, spacing: HP.Space.md) {
        HPSectionHeader("Details")
        Picker("Cage", selection: $facilityId) {
          Text("Select…").tag(UUID?.none)
          ForEach(selectableFacilities) { facility in
            Text(facility.name).tag(UUID?.some(facility.id))
          }
        }
        if facilityId == cage3_1Id {
          Toggle("Full Cage 3 (3.1 + 3.2)", isOn: $isFullCage3)
        }
        Picker("Activity", selection: $activityType) {
          Text("BP").tag("bp")
          Text("Bullpen").tag("bullpen")
          Text("Extra work").tag("extra_work")
          Text("Lesson").tag("lesson")
        }
      }
      .font(HP.Font.callout)
      .foregroundStyle(HP.Color.text)
      .tint(HP.Color.accent)
    }
  }

  private var notesSection: some View {
    HPCard {
      HPFormField(
        label: "Notes (optional)",
        text: $notes,
        kind: .multiline,
        placeholder: "Anything the facility team should know"
      )
    }
  }

  private var cage3_1Id: UUID? { facilities.first(where: { $0.name == "Cage 3.1" })?.id }
  private var cage3_2Id: UUID? { facilities.first(where: { $0.name == "Cage 3.2" })?.id }
  private var selectableFacilities: [SDFacility] {
    facilities.filter { $0.name != "Cage 3.2" }
  }

  private func save() async {
    guard let supabase = appState.supabase else { return }
    guard let facilityId else { return }
    isSaving = true
    defer { isSaving = false }
    do {
      let end = start.addingTimeInterval(TimeInterval(durationMin * 60))
      let spanId: UUID? = (facilityId == cage3_1Id && isFullCage3) ? cage3_2Id : nil
      _ = try await supabase.createFacilityBooking(
        facilityId: facilityId,
        playerId: child.id,
        isBlock: false,
        status: "pending",
        activityType: activityType,
        startAt: start,
        endAt: end,
        coachId: nil,
        title: nil,
        notes: notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : notes,
        spanFacilityId: spanId,
        orgId: appState.activeOrgId
      )
      dismiss()
      onCreated()
    } catch {
      errorText = error.localizedDescription
    }
  }
}
