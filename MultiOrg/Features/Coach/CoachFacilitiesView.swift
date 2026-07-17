import SwiftUI

/// Coach-facing facilities scheduling (3 cages): month grid + day timeline.
struct CoachFacilitiesView: View {
  @EnvironmentObject private var appState: AppState

  @State private var facilities: [SDFacility] = []
  @State private var profileNameById: [UUID: String] = [:]
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

  @State private var editingBooking: SDFacilityBooking?
  @State private var movingBooking: SDFacilityBooking?
  @State private var bookingActionsInFlight = Set<UUID>()
  @State private var coachOptions: [Profile] = []
  @State private var playerOptions: [Profile] = []
  @State private var dayModal: DayModal?
  @State private var createSeed: NewFacilityBookingSheet.Seed?

  private struct DayModal: Identifiable {
    let id = UUID()
    let date: Date
  }

  var body: some View {
    HPCalendarScreenLayout(
      compactPane: dayModal == nil ? .calendar : .agenda,
      showsPaneContent: showsScheduleContent
    ) { context in
      HPWorkspaceHeader(
        "Facilities",
        orgLabel: activeOrganizationName,
        context: "Schedule cages, approve requests, and drag bookings between cages."
      ) {
        if isLoading {
          HPProgressIndicator(style: .spinner)
            .accessibilityLabel("Loading facilities")
        }
      }
    } scopeControl: { context in
      schedulingScopeControl(context)
    } calendar: { _ in
      calendarPane
    } agenda: { context in
      agendaPane(context)
    } stateContent: { _ in
      scheduleStateContent
    }
    .dhdToast($toastText)
    .toolbar {
      ToolbarItem(placement: .automatic) {
        Button {
          Task { await reloadAll() }
        } label: {
          Image(systemName: "arrow.clockwise")
        }
        .accessibilityLabel("Refresh facilities")
      }
    }
    #if os(macOS)
    .dhdFloatingModal(item: $dayModal, width: 980, height: 760) { modal in
      FacilityDaySheet(
        title: "Facilities",
        date: modal.date,
        facilities: facilities,
        bookings: dayBookings,
        userNameById: profileNameById,
        isLoading: isLoading,
        bookingActionsInFlight: bookingActionsInFlight,
        onClose: { dayModal = nil },
        createSeed: $createSeed,
        movingBooking: $movingBooking,
        playerOptions: playerOptions,
        onCreated: {
          toastText = "Created"
          Task { await reloadAll() }
        },
        onEdit: { b in editingBooking = b },
        onApprove: { b in Task { await setStatus(b, status: "approved") } },
        onDeny: { b in Task { await setStatus(b, status: "denied") } },
        onMove: { b, fid, s, e in Task { await moveBooking(b, facilityId: fid, startAt: s, endAt: e) } },
        onResizeSpan: { b, newSpan in Task { await resizeBookingSpan(b, spanFacilityId: newSpan) } }
      )
      .environmentObject(appState)
    }
    #else
    .sheet(item: $dayModal) { modal in
      FacilityDaySheet(
        title: "Facilities",
        date: modal.date,
        facilities: facilities,
        bookings: dayBookings,
        userNameById: profileNameById,
        isLoading: isLoading,
        bookingActionsInFlight: bookingActionsInFlight,
        onClose: { dayModal = nil },
        createSeed: $createSeed,
        movingBooking: $movingBooking,
        playerOptions: playerOptions,
        onCreated: {
          toastText = "Created"
          Task { await reloadAll() }
        },
        onEdit: { b in editingBooking = b },
        onApprove: { b in Task { await setStatus(b, status: "approved") } },
        onDeny: { b in Task { await setStatus(b, status: "denied") } },
        onMove: { b, fid, s, e in Task { await moveBooking(b, facilityId: fid, startAt: s, endAt: e) } },
        onResizeSpan: { b, newSpan in Task { await resizeBookingSpan(b, spanFacilityId: newSpan) } }
      )
      .environmentObject(appState)
      #if !os(macOS)
      .presentationDetents([.large])
      #endif
    }
    #endif
    .sheet(item: $editingBooking) { booking in
      EditFacilityBookingSheet(
        facilities: facilities,
        coachOptions: coachOptions,
        booking: booking,
        onBeginMove: {
          movingBooking = booking
          editingBooking = nil
          toastText = "Tap a time slot to move the booking"
        },
        onSaved: {
          toastText = "Saved"
          Task { await reloadAll() }
        }
      )
      .environmentObject(appState)
      #if os(macOS)
      .frame(minWidth: 640, minHeight: 620)
      #endif
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

  private var showsScheduleContent: Bool {
    !facilities.isEmpty || !rangeBookings.isEmpty || !dayBookings.isEmpty
  }

  @ViewBuilder
  private var scheduleStateContent: some View {
    HPCard {
      if isLoading {
        HPLoadingState(text: "Loading facilities…")
      } else if errorText != nil {
        HPErrorState(
          message: "Facilities could not be loaded. Try again.",
          onRetry: { Task { await reloadAll() } }
        )
      } else {
        HPEmptyState(
          title: "No facilities available",
          message: "Facilities will appear here after they are configured for this organization.",
          systemImage: "building.2"
        )
      }
    }
  }

  @ViewBuilder
  private func schedulingScopeControl(_ context: HPScreenLayoutContext) -> some View {
    if showsScheduleContent {
      if context.isAccessibilitySize {
        monthNavigationCard
      } else if !context.isRegularWidth {
        HPCard {
          HPSegmentedControl(
            options: [(value: "month", label: "Month"), (value: "day", label: "Day")],
            selection: compactScopeSelection
          )
        }
      }
    }
  }

  private var compactScopeSelection: Binding<String> {
    Binding(
      get: { dayModal == nil ? "month" : "day" },
      set: { selection in
        if selection == "month" {
          dayModal = nil
        } else if dayModal == nil {
          dayModal = DayModal(date: selectedDate)
          Task { await loadDay() }
        }
      }
    )
  }

  private var monthNavigationCard: some View {
    HPCard {
      VStack(alignment: .leading, spacing: HP.Space.sm) {
        HPSectionHeader(DateUtils.monthTitle(visibleMonth)) {
          HPStatusBadge(text: "Month agenda", kind: .info)
        }
        ViewThatFits(in: .horizontal) {
          HStack(spacing: HP.Space.sm) {
            monthNavigationButton(title: "Previous month", systemImage: "chevron.left", value: -1, fullWidth: false)
            monthNavigationButton(title: "Next month", systemImage: "chevron.right", value: 1, fullWidth: false)
          }
          VStack(alignment: .leading, spacing: HP.Space.sm) {
            monthNavigationButton(title: "Previous month", systemImage: "chevron.left", value: -1, fullWidth: true)
            monthNavigationButton(title: "Next month", systemImage: "chevron.right", value: 1, fullWidth: true)
          }
        }
      }
    }
  }

  private func monthNavigationButton(
    title: String,
    systemImage: String,
    value: Int,
    fullWidth: Bool
  ) -> some View {
    HPButton(
      title: title,
      systemImage: systemImage,
      variant: .secondary,
      size: .md,
      fullWidth: fullWidth,
      action: { changeVisibleMonth(by: value) }
    )
  }

  private var calendarPane: some View {
    VStack(alignment: .leading, spacing: HP.Space.sm) {
      DHDMonthGridView(
        visibleMonth: $visibleMonth,
        selectedDate: $selectedDate,
        scheduledLiftISOs: approvedISOs,
        practiceISOs: pendingISOs,
        gameISOs: deniedISOs,
        isLoading: isLoading,
        onPrev: { changeVisibleMonth(by: -1) },
        onNext: { changeVisibleMonth(by: 1) },
        onSelect: { date in openDay(date) }
      )

      Text("Green = approved. Blue = pending. Red = denied/cancelled.")
        .font(HP.Font.caption)
        .foregroundStyle(HP.Color.textMuted)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  private func agendaPane(_ context: HPScreenLayoutContext) -> some View {
    VStack(alignment: .leading, spacing: HP.Space.md) {
      if context.isAccessibilitySize {
        monthAgendaCard
      } else {
        selectedDayAgendaCard
      }
      pendingRequestsCard
    }
  }

  private var selectedDayAgendaCard: some View {
    HPCard {
      VStack(alignment: .leading, spacing: HP.Space.sm) {
        HPSectionHeader(selectedDate.formatted(date: .complete, time: .omitted)) {
          HPStatusBadge(text: "\(dayBookings.count) bookings", kind: .neutral)
        }

        if isLoading {
          HPLoadingState(text: "Loading day schedule…")
        }

        if dayBookings.isEmpty, !isLoading {
          HPEmptyState(
            title: "Nothing scheduled",
            message: "Open the day schedule to add a booking or facility block.",
            systemImage: "calendar"
          )
        } else {
          ForEach(dayBookings.sorted { $0.start_at < $1.start_at }) { booking in
            selectedDayBookingRow(booking)
          }
        }

        HPButton(
          title: "Open day schedule",
          systemImage: "calendar.day.timeline.left",
          variant: .secondary,
          size: .md,
          fullWidth: true,
          action: { openDay(selectedDate) }
        )
      }
    }
  }

  private func selectedDayBookingRow(_ booking: SDFacilityBooking) -> some View {
    Button {
      openDay(selectedDate)
    } label: {
      ViewThatFits(in: .horizontal) {
        HStack(alignment: .center, spacing: HP.Space.sm) {
          selectedDayBookingDetails(booking)
          Spacer(minLength: HP.Space.sm)
          HPStatusBadge(text: booking.status.capitalized, kind: bookingStatusKind(booking.status))
        }
        VStack(alignment: .leading, spacing: HP.Space.xs) {
          selectedDayBookingDetails(booking)
          HPStatusBadge(text: booking.status.capitalized, kind: bookingStatusKind(booking.status))
        }
      }
      .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(
      "\(dayBookingTitle(booking)), \(booking.start_at.formatted(date: .omitted, time: .shortened)), \(booking.status)"
    )
  }

  private func selectedDayBookingDetails(_ booking: SDFacilityBooking) -> some View {
    VStack(alignment: .leading, spacing: HP.Space.xs) {
      Text(dayBookingTitle(booking))
        .font(HP.Font.callout.weight(.semibold))
        .foregroundStyle(HP.Color.text)
        .fixedSize(horizontal: false, vertical: true)
      Text(
        "\(booking.start_at.formatted(date: .omitted, time: .shortened)) · \(facilities.first(where: { $0.id == booking.facility_id })?.name ?? "Facility")"
      )
      .font(HP.Font.caption)
      .foregroundStyle(HP.Color.textMuted)
      .fixedSize(horizontal: false, vertical: true)
    }
  }

  private func dayBookingTitle(_ booking: SDFacilityBooking) -> String {
    if let title = booking.title, !title.isEmpty { return title }
    if booking.is_block { return "Facility block" }
    if booking.player_id != nil { return playerName(for: booking) }
    return booking.activity_type.replacingOccurrences(of: "_", with: " ").capitalized
  }

  private func bookingStatusKind(_ status: String) -> HPStatusKind {
    switch status.lowercased() {
    case "approved": .success
    case "pending": .warning
    default: .danger
    }
  }

  private var monthAgendaCard: some View {
    HPCard {
      VStack(alignment: .leading, spacing: HP.Space.sm) {
        HPSectionHeader("Month agenda") {
          HPStatusBadge(text: DateUtils.monthTitle(visibleMonth), kind: .neutral)
        }
        ForEach(monthDates, id: \.self) { date in
          monthAgendaRow(date)
        }
      }
    }
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
      openDay(date)
    } label: {
      HStack(alignment: .center, spacing: HP.Space.sm) {
        VStack(alignment: .leading, spacing: HP.Space.xs) {
          Text(date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
            .font(HP.Font.callout.weight(.semibold))
            .foregroundStyle(HP.Color.text)
            .fixedSize(horizontal: false, vertical: true)
          Text(labels.isEmpty ? "No facility activity" : labels.joined(separator: " · "))
            .font(HP.Font.caption)
            .foregroundStyle(HP.Color.textMuted)
            .fixedSize(horizontal: false, vertical: true)
        }
        Spacer(minLength: HP.Space.sm)
        Image(systemName: "chevron.right")
          .font(HP.Font.caption.weight(.semibold))
          .foregroundStyle(HP.Color.textMuted)
          .accessibilityHidden(true)
      }
      .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(
      labels.isEmpty
        ? "\(date.formatted(date: .long, time: .omitted)), no facility activity"
        : "\(date.formatted(date: .long, time: .omitted)), \(labels.joined(separator: ", "))"
    )
  }

  private func bookingStatusLabels(for iso: String) -> [String] {
    var labels: [String] = []
    if approvedISOs.contains(iso) { labels.append("Approved booking") }
    if pendingISOs.contains(iso) { labels.append("Pending request") }
    if deniedISOs.contains(iso) { labels.append("Denied or cancelled") }
    return labels
  }

  private func changeVisibleMonth(by value: Int) {
    visibleMonth = DateUtils.startOfMonthET(DateUtils.addMonthsET(visibleMonth, value: value))
    Task { await reloadMonth() }
  }

  private func openDay(_ date: Date) {
    selectedDate = DateUtils.startOfDayET(date)
    dayModal = DayModal(date: selectedDate)
    Task { await loadDay() }
  }

  private var pendingRequestsCard: some View {
    let pending = rangeBookings
      .filter { $0.status.lowercased() == "pending" && !$0.is_block }
      .sorted { $0.start_at < $1.start_at }

    return HPCard {
      VStack(alignment: .leading, spacing: HP.Space.sm) {
        HPSectionHeader("Pending requests") {
          HPStatusBadge(
            text: "\(pending.count)",
            kind: pending.isEmpty ? .success : .warning
          )
        }

        if pending.isEmpty {
          Label("All booking requests are handled.", systemImage: "checkmark.circle.fill")
            .font(HP.Font.callout)
            .foregroundStyle(HP.Color.textMuted)
            .fixedSize(horizontal: false, vertical: true)
        } else {
          ForEach(Array(pending.prefix(8).enumerated()), id: \.element.id) { index, booking in
            ViewThatFits(in: .horizontal) {
              HStack(alignment: .center, spacing: HP.Space.sm) {
                pendingRequestDetails(booking)
                Spacer(minLength: HP.Space.sm)
                pendingRequestActions(booking, stacked: false)
              }
              VStack(alignment: .leading, spacing: HP.Space.sm) {
                pendingRequestDetails(booking)
                pendingRequestActions(booking, stacked: true)
              }
            }
            if index < min(pending.count, 8) - 1 {
              Divider().overlay(HP.Color.border.opacity(0.5))
            }
          }
        }
      }
    }
  }

  private func pendingRequestDetails(_ booking: SDFacilityBooking) -> some View {
    VStack(alignment: .leading, spacing: HP.Space.xs) {
      Text(playerName(for: booking))
        .font(HP.Font.callout.weight(.semibold))
        .foregroundStyle(HP.Color.text)
        .fixedSize(horizontal: false, vertical: true)
      Text(booking.start_at.formatted(date: .abbreviated, time: .shortened))
        .font(HP.Font.caption)
        .foregroundStyle(HP.Color.textMuted)
        .fixedSize(horizontal: false, vertical: true)
      Text(facilities.first(where: { $0.id == booking.facility_id })?.name ?? "Facility")
        .font(HP.Font.caption)
        .foregroundStyle(HP.Color.textMuted)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  @ViewBuilder
  private func pendingRequestActions(_ booking: SDFacilityBooking, stacked: Bool) -> some View {
    if bookingActionsInFlight.contains(booking.id) {
      HPProgressIndicator(style: .spinner)
        .accessibilityLabel("Updating booking request")
    } else if stacked {
      VStack(alignment: .leading, spacing: HP.Space.sm) {
        pendingDenyButton(booking, fullWidth: true)
        pendingApproveButton(booking, fullWidth: true)
      }
    } else {
      HStack(spacing: HP.Space.sm) {
        pendingDenyButton(booking, fullWidth: false)
        pendingApproveButton(booking, fullWidth: false)
      }
    }
  }

  private func pendingDenyButton(_ booking: SDFacilityBooking, fullWidth: Bool) -> some View {
    HPButton(
      title: "Deny",
      variant: .destructive,
      size: .md,
      fullWidth: fullWidth,
      action: { Task { await setStatus(booking, status: "denied") } }
    )
  }

  private func pendingApproveButton(_ booking: SDFacilityBooking, fullWidth: Bool) -> some View {
    HPButton(
      title: "Approve",
      systemImage: "checkmark",
      variant: .secondary,
      size: .md,
      fullWidth: fullWidth,
      action: { Task { await setStatus(booking, status: "approved") } }
    )
  }

  private func playerName(for booking: SDFacilityBooking) -> String {
    guard let playerId = booking.player_id else { return "Player request" }
    return profileNameById[playerId] ?? "Player request"
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
      // Load names so coach blocks can show who booked.
      let profiles = try await supabase.listPlayerProfiles()
      var map: [UUID: String] = [:]
      var coaches: [Profile] = []
      var players: [Profile] = []
      for p in profiles {
        map[p.id] = p.displayName
        if p.isCoach { coaches.append(p) }
        if p.isPlayer { players.append(p) }
      }
      profileNameById = map
      coachOptions = coaches.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
      playerOptions = players.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }

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
    for b in rangeBookings {
      let iso = DateUtils.toISODate(b.start_at)
      switch b.status {
      case "approved": approved.insert(iso)
      case "pending": pending.insert(iso)
      default: denied.insert(iso)
      }
    }
    approvedISOs = approved
    pendingISOs = pending
    deniedISOs = denied
  }

  private func setStatus(_ booking: SDFacilityBooking, status: String) async {
    guard let supabase = appState.supabase else { return }
    guard !bookingActionsInFlight.contains(booking.id) else { return }
    bookingActionsInFlight.insert(booking.id)
    // Approval/denial is a status-only action. Explicitly clear any stale
    // create/edit presentation so it can never jump into a creation form.
    createSeed = nil
    editingBooking = nil
    isLoading = true
    defer {
      isLoading = false
      bookingActionsInFlight.remove(booking.id)
    }
    do {
      _ = try await supabase.updateFacilityBooking(
        id: booking.id,
        facilityId: booking.facility_id,
        status: status,
        activityType: booking.activity_type,
        startAt: booking.start_at,
        endAt: booking.end_at,
        coachId: booking.coach_id,
        approved: status == "approved",
        title: booking.title,
        notes: booking.notes,
        orgId: appState.activeOrgId
      )
      toastText = status.capitalized
      await reloadAll()
    } catch {
      errorText = error.localizedDescription
    }
  }

  private func moveBooking(_ booking: SDFacilityBooking, facilityId: UUID, startAt: Date, endAt: Date) async {
    guard let supabase = appState.supabase else { return }
    isLoading = true
    defer { isLoading = false }
    do {
      // If the booking is a full Cage 3 (spanning 3.2) and it’s moved to a different cage,
      // drop the span so it doesn’t occupy an unrelated column.
      let keepSpan = (facilityId == booking.facility_id)
      let newSpan = keepSpan ? booking.span_facility_id : nil
      _ = try await supabase.updateFacilityBooking(
        id: booking.id,
        facilityId: facilityId,
        status: booking.status,
        activityType: booking.activity_type,
        startAt: startAt,
        endAt: endAt,
        coachId: booking.coach_id,
        approved: booking.status == "approved",
        title: booking.title,
        notes: booking.notes,
        spanFacilityId: newSpan,
        orgId: appState.activeOrgId
      )
      toastText = "Moved"
      await reloadAll()
    } catch {
      errorText = error.localizedDescription
    }
  }

  private func resizeBookingSpan(_ booking: SDFacilityBooking, spanFacilityId: UUID?) async {
    guard let supabase = appState.supabase else { return }
    isLoading = true
    defer { isLoading = false }
    do {
      _ = try await supabase.updateFacilityBooking(
        id: booking.id,
        facilityId: booking.facility_id,
        status: booking.status,
        activityType: booking.activity_type,
        startAt: booking.start_at,
        endAt: booking.end_at,
        coachId: booking.coach_id,
        approved: booking.status == "approved",
        title: booking.title,
        notes: booking.notes,
        spanFacilityId: spanFacilityId,
        orgId: appState.activeOrgId
      )
      toastText = (spanFacilityId == nil) ? "Half cage" : "Full cage"
      await reloadAll()
    } catch {
      errorText = error.localizedDescription
    }
  }
}
