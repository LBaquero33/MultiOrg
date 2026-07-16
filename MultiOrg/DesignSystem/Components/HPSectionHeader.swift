import SwiftUI

/// Title + optional trailing accessory. Evolves from `DHDSectionHeader`.
struct HPSectionHeader<Accessory: View>: View {
  private let title: String
  private let accessory: Accessory

  init(_ title: String, @ViewBuilder accessory: () -> Accessory) {
    self.title = title
    self.accessory = accessory()
  }

  var body: some View {
    HStack(alignment: .firstTextBaseline) {
      Text(title)
        .font(HP.Font.headline)
        .foregroundStyle(HP.Color.text)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityAddTraits(.isHeader)
      Spacer(minLength: HP.Space.sm)
      accessory
    }
  }
}

extension HPSectionHeader where Accessory == EmptyView {
  init(_ title: String) {
    self.init(title) { EmptyView() }
  }
}
