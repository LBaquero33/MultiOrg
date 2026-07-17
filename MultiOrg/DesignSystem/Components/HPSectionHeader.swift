import SwiftUI

/// Title + optional trailing accessory. Evolves from `DHDSectionHeader`.
struct HPSectionHeader<Accessory: View>: View {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  private let title: String
  private let accessory: Accessory

  init(_ title: String, @ViewBuilder accessory: () -> Accessory) {
    self.title = title
    self.accessory = accessory()
  }

  var body: some View {
    let layout = dynamicTypeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: HP.Space.xs))
      : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: HP.Space.sm))

    layout {
      Text(title)
        .font(HP.Font.headline)
        .foregroundStyle(HP.Color.text)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityAddTraits(.isHeader)
      if !dynamicTypeSize.isAccessibilitySize {
        Spacer(minLength: HP.Space.sm)
      }
      accessory
    }
  }
}

extension HPSectionHeader where Accessory == EmptyView {
  init(_ title: String) {
    self.init(title) { EmptyView() }
  }
}
