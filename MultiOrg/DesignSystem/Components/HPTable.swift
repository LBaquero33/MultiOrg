import SwiftUI

/// Column descriptor for `HPTable`.
struct HPColumn: Identifiable {
  let id = UUID()
  let title: String
  var alignment: HorizontalAlignment = .leading
  var numeric: Bool = false
}

/// Row descriptor. `cells` align to `columns`; an optional trailing `badge`
/// replaces the last cell.
struct HPTableRow: Identifiable {
  let id = UUID()
  let cells: [String]
  var badge: (text: String, kind: HPStatusKind)? = nil
}

enum HPTableLayout: Equatable {
  case auto, columns, stacked

  func resolvesStacked(isAccessibilitySize: Bool, isCompactWidth: Bool) -> Bool {
    switch self {
    case .stacked: true
    case .columns: false
    case .auto: isAccessibilitySize || isCompactWidth
    }
  }
}

/// Record list. Columns on regular width / normal text; collapses to stacked
/// label:value rows at accessibility sizes (auto). Evolves from
/// `RecentPaymentsView` and the finance lists.
struct HPTable: View {
  let columns: [HPColumn]
  let rows: [HPTableRow]
  var layout: HPTableLayout = .auto

  @Environment(\.dynamicTypeSize) private var dts
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass

  private var stacked: Bool {
    layout.resolvesStacked(
      isAccessibilitySize: dts.isAccessibilitySize,
      isCompactWidth: horizontalSizeClass == .compact
    )
  }

  var body: some View {
    VStack(spacing: 0) {
      if rows.isEmpty {
        HPEmptyState(title: "No records", message: "Rows will appear here once available.", systemImage: "tablecells")
      } else {
        if !stacked {
          headerRow
          Divider().overlay(HP.Color.border)
        }
        ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
          if stacked { stackedRow(row) } else { columnRow(row) }
          if index < rows.count - 1 {
            Divider().overlay(HP.Color.border.opacity(0.5))
          }
        }
      }
    }
    .padding(HP.Space.sm)
    .background(RoundedRectangle(cornerRadius: HP.Radius.lg, style: .continuous).fill(HP.Color.surface))
    .overlay(RoundedRectangle(cornerRadius: HP.Radius.lg, style: .continuous).strokeBorder(HP.Color.border, lineWidth: 1))
  }

  private var headerRow: some View {
    HStack(spacing: HP.Space.sm) {
      ForEach(columns) { column in
        Text(column.title.uppercased())
          .font(HP.Font.eyebrow).tracking(HP.Font.eyebrowTracking)
          .foregroundStyle(HP.Color.textMuted)
          .lineLimit(1)
          .frame(maxWidth: .infinity, alignment: column.alignment == .trailing ? .trailing : .leading)
      }
    }
    .padding(.vertical, 6)
  }

  private func columnRow(_ row: HPTableRow) -> some View {
    HStack(spacing: HP.Space.sm) {
      ForEach(Array(columns.enumerated()), id: \.element.id) { index, column in
        if index == columns.count - 1, let badge = row.badge {
          HStack { Spacer(minLength: 0); HPStatusBadge(text: badge.text, kind: badge.kind) }
            .frame(maxWidth: .infinity, alignment: .trailing)
        } else {
          Text(index < row.cells.count ? row.cells[index] : "")
            .font(column.numeric ? HP.Font.number(.callout) : HP.Font.callout)
            .foregroundStyle(HP.Color.text)
            .lineLimit(1).minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity, alignment: column.alignment == .trailing ? .trailing : .leading)
        }
      }
    }
    .padding(.vertical, 8)
  }

  private func stackedRow(_ row: HPTableRow) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      ForEach(Array(columns.enumerated()), id: \.element.id) { index, column in
        if index == columns.count - 1, let badge = row.badge {
          HStack {
            Text(column.title).font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
            Spacer(minLength: HP.Space.sm)
            HPStatusBadge(text: badge.text, kind: badge.kind)
          }
        } else {
          HStack(alignment: .firstTextBaseline) {
            Text(column.title).font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
            Spacer(minLength: HP.Space.sm)
            Text(index < row.cells.count ? row.cells[index] : "")
              .font(column.numeric ? HP.Font.number(.callout) : HP.Font.callout)
              .foregroundStyle(HP.Color.text)
              .multilineTextAlignment(.trailing)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
      }
    }
    .padding(.vertical, 8)
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}
