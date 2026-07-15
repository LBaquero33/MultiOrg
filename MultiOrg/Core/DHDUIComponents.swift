import SwiftUI

enum DHDCardStyle {
  case flat
  case elevated
}

struct DHDCard<Content: View>: View {
  let content: Content
  var style: DHDCardStyle = .elevated

  init(@ViewBuilder content: () -> Content) {
    self.content = content()
  }

  init(style: DHDCardStyle, @ViewBuilder content: () -> Content) {
    self.style = style
    self.content = content()
  }

  var body: some View {
    content
      .padding(DHDTheme.cardPadding)
      .background(
        RoundedRectangle(cornerRadius: DHDTheme.cornerRadius)
          .fill(backgroundFill)
      )
      .overlay(
        RoundedRectangle(cornerRadius: DHDTheme.cornerRadius)
          .strokeBorder(DHDTheme.separator.opacity(0.35), lineWidth: 1)
      )
      .shadow(color: shadowColor, radius: shadowRadius, x: 0, y: shadowY)
  }

  private var backgroundFill: Color {
#if canImport(AppKit)
    switch style {
    case .flat: return DHDTheme.cardBackground
    case .elevated: return DHDTheme.surfaceElevated
    }
#else
    return DHDTheme.cardBackground
#endif
  }

  private var shadowColor: Color {
#if canImport(AppKit)
    return style == .flat ? .clear : DHDTheme.macShadowColor
#else
    return DHDTheme.shadowColor
#endif
  }

  private var shadowRadius: CGFloat {
#if canImport(AppKit)
    return style == .flat ? 0 : DHDTheme.macShadowRadius
#else
    return DHDTheme.shadowRadius
#endif
  }

  private var shadowY: CGFloat {
#if canImport(AppKit)
    return style == .flat ? 0 : DHDTheme.macShadowY
#else
    return DHDTheme.shadowY
#endif
  }
}

struct DHDHeaderCard<Content: View>: View {
  @Environment(\.dhdOrgBranding) private var branding
  let content: Content

  init(@ViewBuilder content: () -> Content) {
    self.content = content()
  }

  var body: some View {
    content
      .padding(DHDTheme.cardPadding)
      .background(
        RoundedRectangle(cornerRadius: DHDTheme.cornerRadius)
          .fill(branding.headerGradient)
      )
      .overlay(
        DHDDiamondPattern(color: Color.white.opacity(0.06))
          .clipShape(RoundedRectangle(cornerRadius: DHDTheme.cornerRadius))
      )
      .shadow(color: DHDTheme.macShadowColor, radius: DHDTheme.macShadowRadius, x: 0, y: DHDTheme.macShadowY)
  }
}

struct DHDOrgMenuHeader: View {
  @Environment(\.dhdOrgBranding) private var branding
  var subtitle = "Coach workspace"

  var body: some View {
    HStack(spacing: 11) {
      Group {
        if let logoURL = branding.logoURL {
          AsyncImage(url: logoURL) { image in
            image.resizable().scaledToFit()
          } placeholder: {
            ProgressView().tint(.white)
          }
        } else {
          Image("BrandMark")
            .resizable()
            .scaledToFit()
        }
      }
      .frame(width: 38, height: 38)
      .padding(5)
      .background(Color.white.opacity(0.10))
      .clipShape(RoundedRectangle(cornerRadius: 8))

      VStack(alignment: .leading, spacing: 2) {
        Text(branding.shortName)
          .font(.headline)
          .lineLimit(1)
        Text(subtitle)
          .font(.caption2)
          .foregroundStyle(.white.opacity(0.76))
          .lineLimit(1)
      }
      Spacer(minLength: 0)
    }
    .foregroundStyle(.white)
    .padding(10)
    .background(branding.headerGradient)
    .clipShape(RoundedRectangle(cornerRadius: 8))
    .accessibilityElement(children: .combine)
    .accessibilityLabel("\(branding.name), \(subtitle)")
  }
}

struct DHDSectionHeader<Right: View>: View {
  let title: String
  let right: Right

  init(_ title: String, @ViewBuilder right: () -> Right) {
    self.title = title
    self.right = right()
  }

  init(_ title: String) where Right == EmptyView {
    self.title = title
    self.right = EmptyView()
  }

  var body: some View {
    HStack(alignment: .firstTextBaseline) {
      Text(title)
        .font(.headline)
      Spacer()
      right
    }
  }
}

struct DHDStatusPill: View {
  let text: String
  var color: Color = .accentColor

  var body: some View {
    Text(text)
      .font(.caption.weight(.semibold))
      .padding(.horizontal, 10)
      .padding(.vertical, 6)
      .background(color.opacity(0.15))
      .foregroundStyle(color)
      .clipShape(Capsule())
  }
}

struct DHDStatusBadge: View {
  let text: String
  var color: Color = DHDTheme.accent

  var body: some View {
    Text(text)
      .font(.caption2.weight(.semibold))
      .padding(.horizontal, 8)
      .padding(.vertical, 5)
      .background(
        Capsule()
          .fill(color.opacity(0.18))
          .overlay(Capsule().strokeBorder(color.opacity(0.25), lineWidth: 1))
      )
      .foregroundStyle(color)
  }
}

struct DHDFormRow<Right: View>: View {
  let title: String
  let right: Right

  init(_ title: String, @ViewBuilder right: () -> Right) {
    self.title = title
    self.right = right()
  }

  var body: some View {
    HStack(alignment: .firstTextBaseline) {
      Text(title)
        .foregroundStyle(DHDTheme.textSecondary)
      Spacer()
      right
        .foregroundStyle(DHDTheme.textPrimary)
    }
  }
}

struct DHDDiamondPattern: View {
  let color: Color

  init(color: Color = DHDTheme.navy.opacity(0.10)) {
    self.color = color
  }

  var body: some View {
    GeometryReader { geo in
      Canvas { ctx, size in
        let step: CGFloat = 26
        let diamond: CGFloat = 10
        let stroke = StrokeStyle(lineWidth: 1)

        for y in stride(from: -step, through: size.height + step, by: step) {
          for x in stride(from: -step, through: size.width + step, by: step) {
            var path = Path()
            let center = CGPoint(x: x, y: y)
            path.move(to: CGPoint(x: center.x, y: center.y - diamond))
            path.addLine(to: CGPoint(x: center.x + diamond, y: center.y))
            path.addLine(to: CGPoint(x: center.x, y: center.y + diamond))
            path.addLine(to: CGPoint(x: center.x - diamond, y: center.y))
            path.closeSubpath()

            ctx.stroke(path, with: .color(color), style: stroke)
          }
        }
      }
      .opacity(0.9)
      .drawingGroup()
      .frame(width: geo.size.width, height: geo.size.height)
    }
  }
}

// MARK: - Toast

struct DHDToast: View {
  let text: String

  var body: some View {
    Text(text)
      .font(.callout.weight(.semibold))
      .foregroundStyle(DHDTheme.textPrimary)
      .padding(.horizontal, 14)
      .padding(.vertical, 10)
      .background(
        RoundedRectangle(cornerRadius: 12)
          .fill(DHDTheme.surfaceElevated.opacity(0.98))
          .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(DHDTheme.separator.opacity(0.4), lineWidth: 1))
      )
      .shadow(color: DHDTheme.macShadowColor, radius: 12, x: 0, y: 6)
  }
}

extension View {
  func dhdToast(_ text: Binding<String?>) -> some View {
    overlay(alignment: .top) {
      if let t = text.wrappedValue {
        DHDToast(text: t)
          .padding(.top, 14)
          .transition(.move(edge: .top).combined(with: .opacity))
          .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
              withAnimation(.easeOut(duration: 0.2)) {
                text.wrappedValue = nil
              }
            }
          }
      }
    }
  }
}

extension View {
  /// Standard page background for the app's dark macOS look (safe on iOS too).
  @ViewBuilder
  func dhdPageBackground() -> some View {
    if #available(iOS 16.0, macOS 13.0, *) {
      self
        .background(DHDTheme.pageBackground)
        .scrollContentBackground(.hidden)
    } else {
      self
        .background(DHDTheme.pageBackground)
    }
  }
}

// MARK: - macOS floating modal (click-outside to dismiss)

#if os(macOS)
extension View {
  /// Presents an overlay modal that dismisses when clicking outside the card.
  /// Used for "pill" popups where the user expects click-out-to-close behavior.
  func dhdFloatingModal<Item: Identifiable, Modal: View>(
    item: Binding<Item?>,
    width: CGFloat = 860,
    height: CGFloat = 640,
    @ViewBuilder content: @escaping (Item) -> Modal
  ) -> some View {
    overlay {
      if let value = item.wrappedValue {
        ZStack {
          Color.black.opacity(0.55)
            .ignoresSafeArea()
            .onTapGesture { item.wrappedValue = nil }

          content(value)
            .frame(minWidth: width, minHeight: height)
            .background(DHDTheme.pageBackground)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
              RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(DHDTheme.separator.opacity(0.35), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.45), radius: 24, x: 0, y: 14)
        }
        .transition(.opacity)
      }
    }
  }
}
#endif
