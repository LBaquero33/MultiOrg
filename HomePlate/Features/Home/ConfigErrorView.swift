import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

struct ConfigErrorView: View {
  @Environment(\.openURL) private var openURL
  let message: String

  var body: some View {
    HPStateScreenLayout(widthMode: .compact) { _ in
      HPCard {
        VStack(spacing: HP.Space.md) {
          HPErrorState(
            title: "Home Plate isn’t configured",
            message: safeConfigurationMessage
          )

          if let supportURL {
            HPButton(
              title: "Contact support",
              systemImage: "envelope",
              variant: .primary,
              size: .lg,
              fullWidth: true
            ) {
              openURL(supportURL)
            }
          } else {
            HPButton(
              title: "Copy configuration details",
              systemImage: "doc.on.doc",
              variant: .primary,
              size: .lg,
              fullWidth: true,
              action: copyConfigurationDetails
            )
          }

          Text("For development builds, configure the ignored local Secrets.xcconfig file, then regenerate the Xcode project.")
            .font(HP.Font.caption)
            .foregroundStyle(HP.Color.textMuted)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
    }
    .accessibilityHint("Use the action below to contact support or copy the safe configuration diagnosis.")
  }

  private var supportURL: URL? {
    guard let email = DHDAppConfig.supportEmail?
      .trimmingCharacters(in: .whitespacesAndNewlines),
      email.contains("@") else { return nil }
    return URL(string: "mailto:\(email)")
  }

  private func copyConfigurationDetails() {
    #if canImport(UIKit)
    UIPasteboard.general.string = safeConfigurationMessage
    #elseif canImport(AppKit)
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(safeConfigurationMessage, forType: .string)
    #endif
  }

  private var safeConfigurationMessage: String {
    let normalized = message.lowercased()
    if normalized.contains("missing supabase_host") {
      return "The Home Plate service host is missing from this build."
    }
    if normalized.contains("missing supabase_anon_key") {
      return "The Home Plate service key is missing from this build."
    }
    if normalized.contains("supabase_anon_key looks wrong")
      || normalized.contains("invalid supabase_anon_key") {
      return "The Home Plate service key has an invalid format."
    }
    if normalized.contains("invalid supabase_host") {
      return "The Home Plate service host has an invalid format."
    }
    return "This build is missing or has an invalid secure service configuration."
  }
}
