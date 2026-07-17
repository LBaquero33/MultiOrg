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
      .background(cardShape.fill(backgroundFill))
      .clipShape(cardShape)
      .overlay(
        cardShape
          .strokeBorder(borderColor, lineWidth: 1)
          .allowsHitTesting(false)
      )
      .shadow(color: shadowColor, radius: shadowRadius, x: 0, y: shadowY)
  }

  private var cardShape: RoundedRectangle {
    RoundedRectangle(cornerRadius: DHDTheme.cornerRadius, style: .continuous)
  }

  private var backgroundFill: Color {
    switch style {
    case .flat: DHDTheme.cardBackground
    case .elevated: DHDTheme.surfaceElevated
    }
  }

  private var borderColor: Color {
    style == .flat ? DHDTheme.border : DHDTheme.borderStrong
  }

  private var shadowColor: Color {
#if canImport(AppKit)
    style == .flat ? .clear : DHDTheme.macShadowColor
#else
    style == .flat ? .clear : DHDTheme.shadowColor
#endif
  }

  private var shadowRadius: CGFloat {
#if canImport(AppKit)
    style == .flat ? 0 : DHDTheme.macShadowRadius
#else
    style == .flat ? 0 : DHDTheme.shadowRadius
#endif
  }

  private var shadowY: CGFloat {
#if canImport(AppKit)
    style == .flat ? 0 : DHDTheme.macShadowY
#else
    style == .flat ? 0 : DHDTheme.shadowY
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
    let shape = RoundedRectangle(cornerRadius: DHDTheme.cornerRadius, style: .continuous)
    content
      .padding(DHDTheme.cardPadding)
      .foregroundStyle(DHDTheme.identityText)
      .background(shape.fill(branding.headerGradient))
      .clipShape(shape)
      .overlay(
        DHDDiamondPattern(color: DHDTheme.identityText.opacity(0.06))
          .clipShape(shape)
          .allowsHitTesting(false)
      )
      .overlay(
        shape
          .strokeBorder(DHDTheme.identityText.opacity(0.12), lineWidth: 1)
          .allowsHitTesting(false)
      )
      .shadow(
        color: DHDTheme.macShadowColor,
        radius: DHDTheme.macShadowRadius,
        x: 0,
        y: DHDTheme.macShadowY
      )
  }
}

struct DHDOrgMenuHeader: View {
  @Environment(\.dhdOrgBranding) private var branding
  var subtitle = "Coach workspace"

  var body: some View {
    HStack(spacing: HP.Space.sm) {
      Group {
        if let logoURL = branding.logoURL {
          AsyncImage(url: logoURL) { image in
            image.resizable().scaledToFit()
          } placeholder: {
            ProgressView().tint(DHDTheme.identityText)
          }
        } else {
          Image("BrandMark")
            .resizable()
            .scaledToFit()
        }
      }
      .frame(width: 38, height: 38)
      .padding(5)
      .background(DHDTheme.identityText.opacity(0.10))
      .clipShape(RoundedRectangle(cornerRadius: HP.Radius.sm, style: .continuous))

      VStack(alignment: .leading, spacing: 2) {
        Text(branding.shortName)
          .font(HP.Font.headline)
          .lineLimit(2)
        Text(subtitle)
          .font(HP.Font.caption)
          .foregroundStyle(DHDTheme.identityText.opacity(0.78))
          .lineLimit(2)
      }
      Spacer(minLength: 0)
    }
    .foregroundStyle(DHDTheme.identityText)
    .padding(HP.Space.sm)
    .frame(minHeight: DHDTheme.minimumTouchTarget)
    .background(branding.headerGradient)
    .clipShape(RoundedRectangle(cornerRadius: HP.Radius.sm, style: .continuous))
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
    ViewThatFits(in: .horizontal) {
      HStack(alignment: .firstTextBaseline, spacing: HP.Space.sm) {
        titleView
        Spacer(minLength: HP.Space.sm)
        right
      }
      VStack(alignment: .leading, spacing: HP.Space.sm) {
        titleView
        right
      }
    }
  }

  private var titleView: some View {
    Text(title)
      .font(HP.Font.headline)
      .foregroundStyle(DHDTheme.textPrimary)
      .fixedSize(horizontal: false, vertical: true)
      .layoutPriority(1)
      .accessibilityAddTraits(.isHeader)
  }
}

// MARK: - Status semantics

enum DHDStatusKind: CaseIterable {
  case neutral
  case role
  case informational
  case success
  case warning
  case danger
  case verified
  case provider

  var color: Color {
    switch self {
    case .neutral: DHDTheme.textSecondary
    case .role: DHDTheme.accent
    case .informational, .provider: DHDTheme.info
    case .success, .verified: DHDTheme.success
    case .warning: DHDTheme.warning
    case .danger: DHDTheme.danger
    }
  }

  var accessibilityDescription: String {
    switch self {
    case .neutral: "Status"
    case .role: "Role"
    case .informational: "Information"
    case .success: "Success"
    case .warning: "Warning"
    case .danger: "Error"
    case .verified: "Verified"
    case .provider: "Provider"
    }
  }
}

struct DHDStatusPill: View {
  let text: String
  var color: Color
  private let semanticDescription: String?

  nonisolated init(text: String, color: Color = DHDTheme.accent) {
    self.text = text
    self.color = color
    semanticDescription = nil
  }

  nonisolated init(text: String, kind: DHDStatusKind) {
    self.text = text
    color = kind.color
    semanticDescription = kind.accessibilityDescription
  }

  var body: some View {
    Text(text)
      .font(HP.Font.badge)
      .lineLimit(2)
      .fixedSize(horizontal: false, vertical: true)
      .padding(.horizontal, HP.Space.sm)
      .padding(.vertical, HP.Space.xs)
      .background(color.opacity(0.14))
      .foregroundStyle(color)
      .clipShape(Capsule())
      .overlay(
        Capsule()
          .strokeBorder(color.opacity(0.38), lineWidth: 1)
          .allowsHitTesting(false)
      )
      .accessibilityLabel(accessibilityLabel)
  }

  private var accessibilityLabel: String {
    semanticDescription.map { "\($0): \(text)" } ?? text
  }
}

struct DHDStatusBadge: View {
  let text: String
  var color: Color
  private let semanticDescription: String?

  nonisolated init(text: String, color: Color = DHDTheme.accent) {
    self.text = text
    self.color = color
    semanticDescription = nil
  }

  nonisolated init(text: String, kind: DHDStatusKind) {
    self.text = text
    color = kind.color
    semanticDescription = kind.accessibilityDescription
  }

  var body: some View {
    Text(text)
      .font(HP.Font.badge)
      .lineLimit(2)
      .fixedSize(horizontal: false, vertical: true)
      .padding(.horizontal, HP.Space.xs)
      .padding(.vertical, 6)
      .background(Capsule().fill(color.opacity(0.14)))
      .foregroundStyle(color)
      .overlay(
        Capsule()
          .strokeBorder(color.opacity(0.38), lineWidth: 1)
          .allowsHitTesting(false)
      )
      .accessibilityLabel(accessibilityLabel)
  }

  private var accessibilityLabel: String {
    semanticDescription.map { "\($0): \(text)" } ?? text
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
    ViewThatFits(in: .horizontal) {
      HStack(alignment: .firstTextBaseline, spacing: HP.Space.sm) {
        titleView
        Spacer(minLength: HP.Space.sm)
        rightView
      }
      VStack(alignment: .leading, spacing: HP.Space.xs) {
        titleView
        rightView
      }
    }
  }

  private var titleView: some View {
    Text(title)
      .font(HP.Font.body)
      .foregroundStyle(DHDTheme.textSecondary)
  }

  private var rightView: some View {
    right
      .font(HP.Font.body)
      .foregroundStyle(DHDTheme.textPrimary)
  }
}

// MARK: - Universal buttons

enum DHDButtonVariant: CaseIterable {
  case primary
  case secondary
  case destructive
  case compactAction
  case icon
}

enum DHDButtonSize {
  case regular
  case compact

  fileprivate var horizontalPadding: CGFloat {
    switch self {
    case .regular: HP.Space.md
    case .compact: HP.Space.sm
    }
  }
}

struct DHDButton: View {
  let title: String
  var systemImage: String?
  var variant: DHDButtonVariant = .primary
  var size: DHDButtonSize = .regular
  var isEnabled = true
  var isLoading = false
  var expands = false
  let action: () -> Void

  @FocusState private var isFocused: Bool
  @State private var isHovering = false

  init(
    _ title: String,
    systemImage: String? = nil,
    variant: DHDButtonVariant = .primary,
    size: DHDButtonSize = .regular,
    isEnabled: Bool = true,
    isLoading: Bool = false,
    expands: Bool = false,
    action: @escaping () -> Void
  ) {
    self.title = title
    self.systemImage = systemImage
    self.variant = variant
    self.size = size
    self.isEnabled = isEnabled
    self.isLoading = isLoading
    self.expands = expands
    self.action = action
  }

  var body: some View {
    Button {
      DHDActionGate.perform(isEnabled: isEnabled, isLoading: isLoading, action: action)
    } label: {
      HStack(spacing: HP.Space.xs) {
        if isLoading {
          ProgressView()
            .controlSize(.small)
            .tint(foregroundColor)
        } else if let systemImage {
          Image(systemName: systemImage)
            .accessibilityHidden(true)
        }
        if variant != .icon || isLoading {
          Text(title)
            .lineLimit(2)
            .multilineTextAlignment(.center)
        }
      }
      .frame(maxWidth: expands ? .infinity : nil)
    }
    .buttonStyle(
      DHDUniversalButtonStyle(
        variant: variant,
        size: size,
        isFocused: isFocused,
        isHovering: isHovering
      )
    )
    .disabled(!isEnabled || isLoading)
    .focused($isFocused)
    .onHover { isHovering = $0 }
    .accessibilityLabel(title)
    .accessibilityValue(isLoading ? "Loading" : "")
  }

  private var foregroundColor: Color {
    DHDUniversalButtonStyle.foregroundColor(for: variant)
  }
}

enum DHDActionGate {
  @discardableResult
  static func perform(
    isEnabled: Bool,
    isLoading: Bool,
    action: () -> Void
  ) -> Bool {
    guard isEnabled, !isLoading else { return false }
    action()
    return true
  }
}

private struct DHDUniversalButtonStyle: ButtonStyle {
  @Environment(\.isEnabled) private var isEnabled

  let variant: DHDButtonVariant
  let size: DHDButtonSize
  let isFocused: Bool
  let isHovering: Bool

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(HP.Font.caption.weight(.semibold))
      .foregroundStyle(Self.foregroundColor(for: variant))
      .padding(.horizontal, variant == .icon ? 0 : size.horizontalPadding)
      .frame(
        minWidth: variant == .icon ? DHDTheme.minimumTouchTarget : nil,
        minHeight: DHDTheme.minimumTouchTarget
      )
      .background(buttonShape.fill(backgroundColor))
      .overlay(
        buttonShape
          .strokeBorder(strokeColor, lineWidth: isFocused ? 2 : 1)
          .allowsHitTesting(false)
      )
      .contentShape(buttonShape)
      .opacity(isEnabled ? 1 : 0.46)
      .scaleEffect(configuration.isPressed ? 0.98 : 1)
      .brightness(isHovering && isEnabled ? 0.035 : 0)
      .animation(HP.Motion.quick, value: configuration.isPressed)
      .animation(HP.Motion.quick, value: isHovering)
  }

  static func foregroundColor(for variant: DHDButtonVariant) -> Color {
    switch variant {
    case .primary: DHDTheme.accentText
    case .secondary, .icon: DHDTheme.textPrimary
    case .destructive: DHDTheme.danger
    case .compactAction: DHDTheme.identityText
    }
  }

  private var backgroundColor: Color {
    switch variant {
    case .primary: DHDTheme.accent
    case .secondary, .icon: DHDTheme.surfaceMuted
    case .destructive: DHDTheme.danger.opacity(0.14)
    case .compactAction: DHDTheme.primary
    }
  }

  private var strokeColor: Color {
    if isFocused { return DHDTheme.focusRing }
    switch variant {
    case .primary: return DHDTheme.accent.opacity(0.8)
    case .secondary, .icon: return DHDTheme.borderStrong
    case .destructive: return DHDTheme.danger.opacity(0.75)
    case .compactAction: return DHDTheme.primaryGlow.opacity(0.75)
    }
  }

  private var buttonShape: RoundedRectangle {
    RoundedRectangle(cornerRadius: HP.Radius.md, style: .continuous)
  }
}

// MARK: - Universal inputs

enum DHDTextInputKind {
  case plain
  case secure
  case search
}

struct DHDTextInput: View {
  let label: String
  @Binding var text: String
  var prompt = ""
  var helper: String?
  var error: String?
  var kind: DHDTextInputKind = .plain
  var isEnabled = true

  @FocusState private var isFocused: Bool

  init(
    label: String,
    text: Binding<String>,
    prompt: String = "",
    helper: String? = nil,
    error: String? = nil,
    kind: DHDTextInputKind = .plain,
    isEnabled: Bool = true
  ) {
    self.label = label
    _text = text
    self.prompt = prompt
    self.helper = helper
    self.error = error
    self.kind = kind
    self.isEnabled = isEnabled
  }

  var body: some View {
    VStack(alignment: .leading, spacing: HP.Space.xs) {
      if !label.isEmpty {
        Text(label)
          .font(HP.Font.caption)
          .foregroundStyle(DHDTheme.textPrimary)
      }

      HStack(spacing: HP.Space.xs) {
        if kind == .search {
          Image(systemName: "magnifyingglass")
            .foregroundStyle(DHDTheme.textSecondary)
            .accessibilityHidden(true)
        }
        field
      }
      .font(HP.Font.body)
      .padding(.horizontal, HP.Space.sm)
      .frame(minHeight: DHDTheme.minimumTouchTarget)
      .background(inputShape.fill(DHDTheme.inputBackground))
      .overlay(
        inputShape
          .strokeBorder(strokeColor, lineWidth: isFocused || error != nil ? 2 : 1)
          .allowsHitTesting(false)
      )
      .opacity(isEnabled ? 1 : 0.5)

      if let message = error ?? helper {
        Text(message)
          .font(HP.Font.caption)
          .foregroundStyle(error == nil ? DHDTheme.textSecondary : DHDTheme.danger)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .disabled(!isEnabled)
  }

  @ViewBuilder
  private var field: some View {
    switch kind {
    case .plain, .search:
      TextField(prompt, text: $text)
        .focused($isFocused)
        .textFieldStyle(.plain)
    case .secure:
      SecureField(prompt, text: $text)
        .focused($isFocused)
        .textFieldStyle(.plain)
    }
  }

  private var strokeColor: Color {
    if error != nil { return DHDTheme.danger }
    return isFocused ? DHDTheme.focusRing : DHDTheme.borderStrong
  }

  private var inputShape: RoundedRectangle {
    RoundedRectangle(cornerRadius: HP.Radius.md, style: .continuous)
  }
}

/// Semantic shell for selectors, menus, filters, segmented controls, and
/// existing custom inputs whose bindings and validation must stay untouched.
struct DHDControlSurface<Content: View>: View {
  var isFocused = false
  var isInvalid = false
  var isEnabled = true
  let content: Content

  init(
    isFocused: Bool = false,
    isInvalid: Bool = false,
    isEnabled: Bool = true,
    @ViewBuilder content: () -> Content
  ) {
    self.isFocused = isFocused
    self.isInvalid = isInvalid
    self.isEnabled = isEnabled
    self.content = content()
  }

  var body: some View {
    content
      .font(HP.Font.body)
      .padding(.horizontal, HP.Space.sm)
      .frame(minHeight: DHDTheme.minimumTouchTarget)
      .background(shape.fill(DHDTheme.inputBackground))
      .overlay(
        shape
          .strokeBorder(strokeColor, lineWidth: isFocused || isInvalid ? 2 : 1)
          .allowsHitTesting(false)
      )
      .opacity(isEnabled ? 1 : 0.5)
      .disabled(!isEnabled)
  }

  private var strokeColor: Color {
    if isInvalid { return DHDTheme.danger }
    return isFocused ? DHDTheme.focusRing : DHDTheme.borderStrong
  }

  private var shape: RoundedRectangle {
    RoundedRectangle(cornerRadius: HP.Radius.md, style: .continuous)
  }
}

// MARK: - Universal states

enum DHDStateKind: Equatable {
  case loading
  case empty
  case error
  case success
  case restricted

  fileprivate var icon: String {
    switch self {
    case .loading: "clock"
    case .empty: "tray"
    case .error: "exclamationmark.triangle"
    case .success: "checkmark.circle"
    case .restricted: "lock"
    }
  }

  fileprivate var color: Color {
    switch self {
    case .loading, .empty: DHDTheme.textSecondary
    case .error: DHDTheme.danger
    case .success: DHDTheme.success
    case .restricted: DHDTheme.warning
    }
  }
}

struct DHDStateView: View {
  let kind: DHDStateKind
  let title: String
  var message: String?
  var actionTitle: String?
  var action: (() -> Void)?

  var body: some View {
    DHDCard(style: .flat) {
      VStack(spacing: HP.Space.sm) {
        if kind == .loading {
          ProgressView()
            .controlSize(.large)
            .tint(DHDTheme.accent)
            .accessibilityLabel(title)
        } else {
          Image(systemName: kind.icon)
            .font(.system(.title2, design: .default, weight: .semibold))
            .foregroundStyle(kind.color)
            .accessibilityHidden(true)
        }

        Text(title)
          .font(HP.Font.headline)
          .foregroundStyle(DHDTheme.textPrimary)
          .multilineTextAlignment(.center)
          .fixedSize(horizontal: false, vertical: true)

        if let message {
          Text(message)
            .font(HP.Font.body)
            .foregroundStyle(DHDTheme.textSecondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
        }

        if let actionTitle, let action {
          DHDButton(
            actionTitle,
            variant: kind == .error ? .secondary : .primary,
            size: .compact,
            action: action
          )
        }
      }
      .padding(.vertical, HP.Space.md)
      .frame(maxWidth: .infinity)
    }
  }
}

struct DHDLoadingState: View {
  var title = "Loading…"
  var message: String?

  var body: some View {
    DHDStateView(kind: .loading, title: title, message: message)
  }
}

struct DHDEmptyState: View {
  let title: String
  var message: String?
  var actionTitle: String?
  var action: (() -> Void)?

  var body: some View {
    DHDStateView(
      kind: .empty,
      title: title,
      message: message,
      actionTitle: actionTitle,
      action: action
    )
  }
}

struct DHDErrorState: View {
  let title: String
  var message: String?
  var retryTitle = "Try again"
  var retry: (() -> Void)?

  var body: some View {
    DHDStateView(
      kind: .error,
      title: title,
      message: message,
      actionTitle: retry == nil ? nil : retryTitle,
      action: retry
    )
  }
}

// MARK: - Decorative pattern

struct DHDDiamondPattern: View {
  let color: Color

  init(color: Color = DHDTheme.primary.opacity(0.10)) {
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
      .allowsHitTesting(false)
      .accessibilityHidden(true)
    }
  }
}

// MARK: - Toast

struct DHDToast: View {
  let text: String

  var body: some View {
    Text(text)
      .font(HP.Font.callout.weight(.semibold))
      .foregroundStyle(DHDTheme.textPrimary)
      .fixedSize(horizontal: false, vertical: true)
      .padding(.horizontal, HP.Space.md)
      .padding(.vertical, HP.Space.sm)
      .background(
        RoundedRectangle(cornerRadius: HP.Radius.md, style: .continuous)
          .fill(DHDTheme.surfaceElevated)
      )
      .overlay(
        RoundedRectangle(cornerRadius: HP.Radius.md, style: .continuous)
          .strokeBorder(DHDTheme.borderStrong, lineWidth: 1)
          .allowsHitTesting(false)
      )
      .shadow(color: DHDTheme.macShadowColor, radius: 12, x: 0, y: 6)
      .accessibilityAddTraits(.isStaticText)
  }
}

extension View {
  func dhdToast(_ text: Binding<String?>) -> some View {
    overlay(alignment: .top) {
      if let currentText = text.wrappedValue {
        DHDToast(text: currentText)
          .padding(.top, HP.Space.sm)
          .transition(.move(edge: .top).combined(with: .opacity))
          .allowsHitTesting(false)
          .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
              withAnimation(HP.Motion.quick) {
                text.wrappedValue = nil
              }
            }
          }
      }
    }
  }

  /// Applies the adaptive Home Plate page surface while preserving the
  /// receiver's scrolling and interaction behavior.
  @ViewBuilder
  func dhdPageBackground() -> some View {
    if #available(iOS 16.0, macOS 13.0, *) {
      self
        .background(DHDTheme.pageBackground)
        .scrollContentBackground(.hidden)
    } else {
      self.background(DHDTheme.pageBackground)
    }
  }
}

// MARK: - macOS floating modal (click-outside and Escape to dismiss)

#if os(macOS)
extension View {
  func dhdFloatingModal<Item: Identifiable, Modal: View>(
    item: Binding<Item?>,
    width: CGFloat = 860,
    height: CGFloat = 640,
    @ViewBuilder content: @escaping (Item) -> Modal
  ) -> some View {
    overlay {
      if let value = item.wrappedValue {
        ZStack {
          DHDTheme.scrim
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .onTapGesture { item.wrappedValue = nil }

          content(value)
            .frame(minWidth: width, minHeight: height)
            .background(DHDTheme.pageBackground)
            .clipShape(RoundedRectangle(cornerRadius: HP.Radius.xl, style: .continuous))
            .overlay(
              RoundedRectangle(cornerRadius: HP.Radius.xl, style: .continuous)
                .strokeBorder(DHDTheme.borderStrong, lineWidth: 1)
                .allowsHitTesting(false)
            )
            .shadow(
              color: HP.Shadow.modal.color,
              radius: HP.Shadow.modal.radius,
              x: HP.Shadow.modal.x,
              y: HP.Shadow.modal.y
            )
        }
        .onExitCommand { item.wrappedValue = nil }
        .transition(.opacity)
      }
    }
  }
}
#endif
