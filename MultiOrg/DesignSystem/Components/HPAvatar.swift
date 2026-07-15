import SwiftUI

/// Identity avatar. Initials or SF Symbol on a tinted disc. The tint may be an
/// organization's brand color (identity chrome). No network image loading in
/// Stage 3B (previews must not contact the network).
enum HPAvatarSize {
  case xs, sm, md, lg
  var dim: CGFloat { switch self { case .xs: 24; case .sm: 32; case .md: 44; case .lg: 64 } }
  var font: Font { switch self { case .xs: HP.Font.caption; case .sm: HP.Font.callout; case .md: HP.Font.headline; case .lg: HP.Font.title } }
}

struct HPAvatar: View {
  var name: String
  var systemImage: String? = nil
  var size: HPAvatarSize = .md
  /// Identity tint — org brand color is allowed here (chrome only).
  var tint: Color = HP.Color.primary
  var showsStatus: Bool = false
  var statusColor: Color = HP.Color.success

  var body: some View {
    ZStack {
      Circle().fill(tint.opacity(0.22))
      Circle().strokeBorder(tint.opacity(0.5), lineWidth: 1)
      if let systemImage {
        Image(systemName: systemImage).font(size.font).foregroundStyle(tint)
      } else {
        Text(initials).font(size.font.weight(.semibold)).foregroundStyle(tint)
      }
    }
    .frame(width: size.dim, height: size.dim)
    .overlay(alignment: .bottomTrailing) {
      if showsStatus {
        Circle().fill(statusColor)
          .frame(width: size.dim * 0.28, height: size.dim * 0.28)
          .overlay(Circle().strokeBorder(HP.Color.bg, lineWidth: 2))
      }
    }
    .accessibilityElement()
    .accessibilityLabel(name)
  }

  private var initials: String {
    let parts = name.split(separator: " ").prefix(2)
    let letters = parts.compactMap { $0.first }.map(String.init)
    return letters.joined().uppercased()
  }
}
