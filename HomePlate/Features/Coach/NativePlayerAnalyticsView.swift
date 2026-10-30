import SwiftUI

struct NativePlayerAnalyticsView: View {
  @EnvironmentObject private var appState: AppState

  let playerId: UUID
  let playerName: String
  var date: String? = nil
  var athleteId: UUID? = nil

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: HP.Space.md) {
        HPWorkspaceHeader(
          "R Analysis",
          context: "Open the complete interactive report for \(playerName) on Home Plate web."
        )

        HPCard {
          VStack(alignment: .leading, spacing: HP.Space.md) {
            Image(systemName: "chart.xyaxis.line")
              .font(.system(size: 34, weight: .semibold))
              .foregroundStyle(HP.Color.accent)

            VStack(alignment: .leading, spacing: HP.Space.xs) {
              Text("Full analytics are on the web")
                .font(HP.Font.title)
                .foregroundStyle(HP.Color.text)
              Text("Home Plate web provides the complete TrackMan, Rapsodo, and HitTrax experience with full-size charts, tables, filters, and exports.")
                .font(HP.Font.body)
                .foregroundStyle(HP.Color.textMuted)
                .fixedSize(horizontal: false, vertical: true)
            }

            if let websiteURL {
              Link(destination: websiteURL) {
                Label("Open R Analysis", systemImage: "arrow.up.right.square")
                  .frame(maxWidth: .infinity, minHeight: 48)
              }
              .buttonStyle(HPButtonStyle(variant: .primary, size: .lg, fullWidth: true))
              .accessibilityHint("Opens this player's analysis in the Home Plate web app")
            } else {
              HPStatusBadge(text: "Choose an organization first", kind: .warning)
            }
          }
        }

        HPCard(style: .flat) {
          VStack(alignment: .leading, spacing: HP.Space.sm) {
            HPSectionHeader("What opens on the web")
            destinationRow("Player and organization preserved", systemImage: "person.crop.circle.badge.checkmark")
            destinationRow("Selected calendar date preserved", systemImage: "calendar")
            destinationRow("Responsive charts and export tools", systemImage: "rectangle.and.arrow.up.right.and.arrow.down.left")
          }
        }
      }
      .padding(HP.Space.md)
      .frame(maxWidth: 720, alignment: .leading)
      .frame(maxWidth: .infinity, alignment: .center)
    }
    .background(HP.Color.bg)
  }

  private var websiteURL: URL? {
    guard let organization = appState.activeOrgId else { return nil }
    var parts = URLComponents(string: "https://www.homeplateapps.com/app/analysis")!
    var query = [
      URLQueryItem(name: "org", value: organization.uuidString.lowercased()),
      URLQueryItem(
        name: athleteId == nil ? "player" : "athlete",
        value: (athleteId ?? playerId).uuidString.lowercased()
      ),
    ]
    if let date {
      query.append(URLQueryItem(name: "start", value: date))
      query.append(URLQueryItem(name: "end", value: date))
    }
    parts.queryItems = query
    return parts.url
  }

  private func destinationRow(_ title: String, systemImage: String) -> some View {
    Label(title, systemImage: systemImage)
      .font(HP.Font.callout)
      .foregroundStyle(HP.Color.text)
  }
}
