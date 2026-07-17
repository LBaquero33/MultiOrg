import SwiftUI

/// Deterministic width behavior for reusable Home Plate screen layouts.
///
/// Production callers normally use ``automatic``. Gallery and render tests can
/// force a bucket so the same anatomy is exercised at every supported width.
enum HPScreenWidthMode: Equatable, Sendable {
  case automatic
  case compact
  case regular
  case wide
}

enum HPScreenWidthClass: Equatable, Sendable {
  case compact
  case regular
  case wide
}

/// Presentation-only layout facts resolved from width and Dynamic Type.
/// Business state, authorization, navigation, and persistence remain owned by
/// the production screen embedding a structural layout.
struct HPScreenLayoutContext: Equatable, Sendable {
  let widthClass: HPScreenWidthClass
  let isAccessibilitySize: Bool

  init(widthClass: HPScreenWidthClass, isAccessibilitySize: Bool) {
    self.widthClass = widthClass
    self.isAccessibilitySize = isAccessibilitySize
  }

  /// Compatibility initializer for layout tests and compact/regular callers.
  init(isRegularWidth: Bool, isAccessibilitySize: Bool) {
    self.init(
      widthClass: isRegularWidth ? .regular : .compact,
      isAccessibilitySize: isAccessibilitySize
    )
  }

  var isRegularWidth: Bool { widthClass != .compact }
  var isWide: Bool { widthClass == .wide }
  var isExpanded: Bool { isRegularWidth && !isAccessibilitySize }
  var tableLayout: HPTableLayout { isExpanded ? .columns : .stacked }

  func gridColumnCount(compact: Int, regular: Int, wide: Int? = nil) -> Int {
    guard !isAccessibilitySize else { return 1 }
    return switch widthClass {
    case .compact: compact
    case .regular: regular
    case .wide: wide ?? regular
    }
  }

  func gridColumns(compact: Int, regular: Int, wide: Int? = nil) -> [GridItem] {
    Array(
      repeating: GridItem(.flexible(), spacing: HP.Space.sm),
      count: max(1, gridColumnCount(compact: compact, regular: regular, wide: wide))
    )
  }

  static func resolve(
    widthMode: HPScreenWidthMode,
    horizontalSizeClass: UserInterfaceSizeClass?,
    dynamicTypeSize: DynamicTypeSize,
    containerWidth: CGFloat? = nil
  ) -> Self {
    let widthClass: HPScreenWidthClass = switch widthMode {
    case .automatic:
      if let containerWidth, containerWidth > 0 {
        if containerWidth < 700 { .compact }
        else if containerWidth < 1_100 { .regular }
        else { .wide }
      } else if horizontalSizeClass == .compact {
        .compact
      } else if horizontalSizeClass == nil {
        .wide
      } else {
        .regular
      }
    case .compact: .compact
    case .regular: .regular
    case .wide: .wide
    }
    return Self(
      widthClass: widthClass,
      isAccessibilitySize: dynamicTypeSize.isAccessibilitySize
    )
  }
}

/// Shared scroll, canvas, padding, and optional content-width cap for Home
/// Plate screen structures. The content closure receives deterministic layout
/// facts and owns all feature-specific views and behavior.
struct HPScreenScaffold<Content: View>: View {
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @State private var containerWidth: CGFloat = 0

  private let widthMode: HPScreenWidthMode
  private let maxContentWidth: CGFloat?
  private let content: (HPScreenLayoutContext) -> Content

  init(
    widthMode: HPScreenWidthMode = .automatic,
    maxContentWidth: CGFloat? = nil,
    @ViewBuilder content: @escaping (HPScreenLayoutContext) -> Content
  ) {
    self.widthMode = widthMode
    self.maxContentWidth = maxContentWidth
    self.content = content
  }

  private var context: HPScreenLayoutContext {
    .resolve(
      widthMode: widthMode,
      horizontalSizeClass: horizontalSizeClass,
      dynamicTypeSize: dynamicTypeSize,
      containerWidth: containerWidth > 0 ? containerWidth : nil
    )
  }

  var body: some View {
    ScrollView {
      content(context)
        .padding(HP.Space.md)
        .frame(maxWidth: maxContentWidth, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .top)
    }
    .background(HP.Color.bg)
    .onGeometryChange(for: CGFloat.self) { geometry in
      geometry.size.width
    } action: { newWidth in
      if abs(containerWidth - newWidth) > 0.5 {
        containerWidth = newWidth
      }
    }
  }
}
