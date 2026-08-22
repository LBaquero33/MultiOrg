import SwiftUI

/// Top of every workspace, standardized to always present the same four slots:
///   1. organization label / identity (eyebrow + gradient mark)
///   2. workspace title
///   3. optional context line (date range, filter, etc.)
///   4. one optional primary action (trailing)
///
/// Identity chrome (the gradient mark + org label) uses `HPIdentity` — Home
/// Plate green by default, or an organization's brand color. Semantic controls
/// in `trailing` stay HP-owned (decision 1). Evolves from `DHDHeaderCard` +
/// `DHDOrgMenuHeader`.
struct HPWorkspaceHeader<Trailing: View>: View {
  private let title: String
  private let orgLabel: String
  private let context: String?
  private let identity: HPIdentity
  private let trailing: Trailing

  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass

  /// - Parameters:
  ///   - title: the workspace title.
  ///   - orgLabel: identity/org label shown as the eyebrow. Defaults to the
  ///     identity's name so Home Plate and org examples are consistent.
  ///   - context: optional secondary line under the title.
  ///   - identity: identity chrome (Home Plate by default).
  ///   - trailing: one primary action.
  init(_ title: String,
       orgLabel: String? = nil,
       context: String? = nil,
       identity: HPIdentity = .homePlate,
       @ViewBuilder trailing: () -> Trailing) {
    self.title = title
    self.orgLabel = orgLabel ?? identity.name
    self.context = context
    self.identity = identity
    self.trailing = trailing()
  }

  var body: some View {
    let layout = dynamicTypeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: HP.Space.sm))
      : AnyLayout(HStackLayout(alignment: .center, spacing: HP.Space.md))

    layout {
      titleBlock
      trailing
        .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : nil,
               alignment: .leading)
        .environment(\.hpForceFullWidthAction, dynamicTypeSize.isAccessibilitySize)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var titleBlock: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(title)
        .font(dynamicTypeSize.isAccessibilitySize
          ? HP.Font.title
          : (horizontalSizeClass == .regular ? HP.Font.display : HP.Font.pageTitle))
        .tracking(HP.Font.titleTracking)
        .foregroundStyle(HP.Color.text)
        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
        .truncationMode(.tail)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityAddTraits(.isHeader)
      if let context {
        Text(context)
          .font(HP.Font.body)
          .foregroundStyle(HP.Color.textMuted)
          .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

extension HPWorkspaceHeader where Trailing == EmptyView {
  init(_ title: String,
       orgLabel: String? = nil,
       context: String? = nil,
       identity: HPIdentity = .homePlate) {
    self.init(title, orgLabel: orgLabel, context: context, identity: identity) { EmptyView() }
  }
}
