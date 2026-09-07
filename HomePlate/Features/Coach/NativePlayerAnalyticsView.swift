import Charts
import SwiftUI

struct NativePlayerAnalyticsView: View {
  @EnvironmentObject private var appState: AppState

  let playerId: UUID
  let playerName: String

  @State private var sources: [SDPlayerAnalyticsSource] = []
  @State private var selectedSourceId: UUID?
  @State private var discipline: SDPlayerAnalyticsDiscipline = .hitting
  @State private var module = SDPlayerAnalyticsDiscipline.hitting.modules[0].key
  @State private var result: SDPlayerAnalyticsResponse?
  @State private var isLoadingSources = false
  @State private var isRunning = false
  @State private var errorText: String?
  @State private var requestToken = UUID()

  private var eligibleSources: [SDPlayerAnalyticsSource] {
    sources.filter { source in
      guard let role = source.selectedSourcePlayerRole, !role.isEmpty else { return true }
      return role == discipline.sourceRole
    }
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: HP.Space.md) {
        header
        controls
        content
      }
      .padding(HP.Space.md)
      .frame(maxWidth: 1100, alignment: .leading)
      .frame(maxWidth: .infinity, alignment: .center)
    }
    .background(HP.Color.bg)
    .task(id: playerId) { await loadSourcesAndAnalysis() }
    .onChange(of: discipline) { _, next in
      module = next.modules[0].key
      selectedSourceId = eligibleSources.first?.id
      result = nil
      Task { await runAnalysis() }
    }
  }

  private var header: some View {
    HPWorkspaceHeader(
      "Data Lab",
      context: "Native R analytics for \(playerName)"
    ) {
      if let result {
        HPStatusBadge(
          text: result.cacheStatus == "hit" ? "Cached · fast" : "Fresh analysis",
          kind: result.cacheStatus == "hit" ? .success : .neutral
        )
      }
    }
  }

  private var controls: some View {
    HPCard {
      VStack(alignment: .leading, spacing: HP.Space.md) {
        HPSectionHeader("Analysis scope")
        HPSegmentedControl(
          options: SDPlayerAnalyticsDiscipline.allCases.map { (value: $0, label: $0.title) },
          selection: $discipline
        )

        Picker("Topic", selection: $module) {
          ForEach(discipline.modules, id: \.key) { item in
            Text(item.label).tag(item.key)
          }
        }
        .pickerStyle(.menu)

        Picker("Source", selection: $selectedSourceId) {
          if eligibleSources.count > 1 {
            Text("All matching sessions (slower first load)").tag(UUID?.none)
          }
          ForEach(eligibleSources) { source in
            Text(sourceLabel(source)).tag(Optional(source.id))
          }
        }
        .pickerStyle(.menu)
        .disabled(isLoadingSources || eligibleSources.isEmpty)

        Text("The mobile view defaults to the newest imported session. Repeat requests use Home Plate's cached R result instead of re-running the full model.")
          .font(HP.Font.caption)
          .foregroundStyle(HP.Color.textMuted)

        HPButton(
          title: isRunning ? "Running R analysis…" : "Load analysis",
          systemImage: "chart.xyaxis.line",
          variant: .primary,
          size: .md,
          isLoading: isRunning,
          action: { Task { await runAnalysis() } }
        )
        .disabled(isRunning || eligibleSources.isEmpty)
      }
    }
  }

  @ViewBuilder
  private var content: some View {
    if isLoadingSources && sources.isEmpty {
      HPCard { HPLoadingState(text: "Finding imported TrackMan and Rapsodo sessions…") }
    } else if let errorText, result == nil {
      HPCard {
        HPErrorState(message: errorText, onRetry: { Task { await loadSourcesAndAnalysis() } })
      }
    } else if eligibleSources.isEmpty {
      HPCard {
        HPEmptyState(
          title: "No \(discipline.title.lowercased()) source yet",
          message: "Import a matching TrackMan, Rapsodo, or HitTrax file for this player first.",
          systemImage: "externaldrive.badge.exclamationmark"
        )
      }
    } else if isRunning && result == nil {
      HPCard { HPLoadingState(text: "Running the selected R model…") }
    } else if let result {
      resultContent(result)
    }
  }

  private func resultContent(_ result: SDPlayerAnalyticsResponse) -> some View {
    VStack(alignment: .leading, spacing: HP.Space.md) {
      if !result.summaryMetrics.isEmpty {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: HP.Space.sm) {
          ForEach(result.summaryMetrics) { metric in
            HPMetricCard(
              title: metric.label,
              value: metric.displayValue,
              unit: metric.unit,
              context: metric.guidance ?? (metric.provisional == true ? "Provisional sample" : "R model output")
            )
          }
        }
      }

      if let summary = result.guidance.summary, !summary.isEmpty {
        HPCard {
          VStack(alignment: .leading, spacing: HP.Space.xs) {
            HPSectionHeader("What this means")
            Text(summary).font(HP.Font.body).foregroundStyle(HP.Color.text)
            if let note = result.guidance.sampleNote, !note.isEmpty {
              Text(note).font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
            }
          }
        }
      }

      ForEach(result.charts) { chart in
        NativeAnalyticsChartCard(chart: chart)
      }

      ForEach(result.tables) { table in
        analyticsTable(table)
      }

      if !result.warnings.isEmpty {
        HPCard {
          VStack(alignment: .leading, spacing: HP.Space.xs) {
            HPSectionHeader("Analysis notes")
            ForEach(result.warnings, id: \.self) { warning in
              Label(warning, systemImage: "exclamationmark.triangle")
                .font(HP.Font.caption)
                .foregroundStyle(HP.Color.warning)
            }
          }
        }
      }

      Text("\(result.sampleSummary.rows ?? 0) source rows · \(result.sampleSummary.provider ?? discipline.title) · Model \(result.modelVersion)")
        .font(HP.Font.caption)
        .foregroundStyle(HP.Color.textMuted)
    }
  }

  private func analyticsTable(_ table: SDPlayerAnalyticsTable) -> some View {
    let visibleColumns = Array(table.columns.prefix(4))
    let rows = Array(table.rows.prefix(20)).enumerated().map { index, row in
      HPTableRow(
        id: "\(table.id)-\(index)",
        cells: visibleColumns.map { display(row[$0.key]) }
      )
    }
    return HPCard {
      VStack(alignment: .leading, spacing: HP.Space.sm) {
        HPSectionHeader(table.title) {
          HPStatusBadge(text: "\(table.rows.count) rows", kind: .neutral)
        }
        if let description = table.description, !description.isEmpty {
          Text(description).font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
        }
        HPTable(columns: visibleColumns.map { HPColumn(title: $0.label) }, rows: rows)
      }
    }
  }

  private func loadSourcesAndAnalysis() async {
    guard let service = appState.supabase, let organizationId = appState.activeOrgId else { return }
    let token = UUID()
    requestToken = token
    isLoadingSources = true
    errorText = nil
    defer { if requestToken == token { isLoadingSources = false } }
    do {
      let response = try await service.listPlayerAnalyticsSources(
        organizationId: organizationId,
        playerId: playerId
      )
      guard requestToken == token else { return }
      sources = response.sources
      selectedSourceId = eligibleSources.first?.id
      isLoadingSources = false
      if !eligibleSources.isEmpty { await runAnalysis() }
    } catch {
      guard requestToken == token else { return }
      errorText = SDApplicationErrorClassifier.alertMessage(for: error)
    }
  }

  private func runAnalysis() async {
    guard let service = appState.supabase, let organizationId = appState.activeOrgId else { return }
    let sourceIds = selectedSourceId.map { [$0] } ?? eligibleSources.map(\.id)
    guard !sourceIds.isEmpty else { return }
    let token = UUID()
    requestToken = token
    isRunning = true
    errorText = nil
    do {
      let response = try await service.runPlayerAnalytics(
        organizationId: organizationId,
        playerId: playerId,
        discipline: discipline,
        module: module,
        sourceIds: sourceIds
      )
      guard requestToken == token else { return }
      result = response
    } catch {
      guard requestToken == token else { return }
      errorText = SDApplicationErrorClassifier.alertMessage(for: error)
    }
    if requestToken == token { isRunning = false }
  }

  private func sourceLabel(_ source: SDPlayerAnalyticsSource) -> String {
    "\(source.provider.uppercased()) · \(source.selectedSourcePlayerName ?? source.fileName) · \(source.rowCount) rows"
  }

  private func display(_ value: SDJSONValue?) -> String {
    guard let value else { return "—" }
    switch value {
    case .double(let number): return number.rounded() == number ? String(Int(number)) : String(format: "%.2f", number)
    case .int(let number): return String(number)
    case .bool(let flag): return flag ? "Yes" : "No"
    case .string(let text): return text
    case .null: return "—"
    default: return "Available"
    }
  }
}

private struct NativeAnalyticsChartPoint: Identifiable {
  let id: Int
  let x: String
  let y: Double
}

private struct NativeAnalyticsChartCard: View {
  let chart: SDPlayerAnalyticsChart

  private var points: [NativeAnalyticsChartPoint] {
    let yKey = chart.y ?? chart.data.first?.first(where: { $0.value.doubleValue != nil })?.key
    guard let yKey else { return [] }
    let xKey = chart.x ?? chart.data.first?.keys.first(where: { $0 != yKey })
    return chart.data.prefix(60).enumerated().compactMap { index, row in
      guard let y = row[yKey]?.doubleValue else { return nil }
      return NativeAnalyticsChartPoint(
        id: index,
        x: xKey.flatMap { row[$0]?.stringValue } ?? String(index + 1),
        y: y
      )
    }
  }

  var body: some View {
    HPCard {
      VStack(alignment: .leading, spacing: HP.Space.sm) {
        HPSectionHeader(chart.title)
        if let description = chart.description, !description.isEmpty {
          Text(description).font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
        }
        if points.isEmpty {
          Text("This model returned a specialized baseball visualization. Its numeric output remains available in the detailed tables below.")
            .font(HP.Font.caption)
            .foregroundStyle(HP.Color.textMuted)
        } else {
          Chart(points) { point in
            if chart.type.localizedCaseInsensitiveContains("scatter") || chart.type.localizedCaseInsensitiveContains("location") {
              PointMark(x: .value("Group", point.x), y: .value("Value", point.y))
                .foregroundStyle(HP.Color.accent)
            } else {
              BarMark(x: .value("Group", point.x), y: .value("Value", point.y))
                .foregroundStyle(HP.Color.primaryGlow)
            }
          }
          .frame(height: 220)
          .chartXAxis(.hidden)
        }
      }
    }
  }
}
