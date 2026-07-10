import SwiftUI

#if canImport(UIKit)
import UIKit

/// UIKit-backed 2-axis scrolling for smoother panning than SwiftUI's nested ScrollViews.
/// This is used for the facilities day timeline so you can pan horizontally+vertically
/// from basically anywhere in the schedule area.
struct TwoAxisScrollView<Content: View>: UIViewRepresentable {
  var showsIndicators: Bool = true
  var bounce: Bool = true
  @ViewBuilder var content: () -> Content

  func makeUIView(context: Context) -> UIScrollView {
    let scrollView = UIScrollView()
    scrollView.alwaysBounceVertical = bounce
    scrollView.alwaysBounceHorizontal = bounce
    scrollView.showsVerticalScrollIndicator = showsIndicators
    scrollView.showsHorizontalScrollIndicator = showsIndicators
    scrollView.bounces = bounce
    scrollView.decelerationRate = .normal
    scrollView.delaysContentTouches = false
    scrollView.canCancelContentTouches = true

    let host = UIHostingController(rootView: content())
    host.view.backgroundColor = .clear
    host.view.translatesAutoresizingMaskIntoConstraints = false

    scrollView.addSubview(host.view)

    // Pin hosted content to the scroll view's content layout guide.
    NSLayoutConstraint.activate([
      host.view.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
      host.view.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
      host.view.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
      host.view.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
    ])

    context.coordinator.hostingController = host
    return scrollView
  }

  func updateUIView(_ scrollView: UIScrollView, context: Context) {
    if let host = context.coordinator.hostingController {
      host.rootView = content()
      host.view.setNeedsLayout()
    }
  }

  func makeCoordinator() -> Coordinator { Coordinator() }

  final class Coordinator {
    var hostingController: UIHostingController<Content>?
  }
}

#else

/// Fallback for non-UIKit platforms (macOS uses its own scroll behaviors).
struct TwoAxisScrollView<Content: View>: View {
  var showsIndicators: Bool = true
  var bounce: Bool = true
  @ViewBuilder var content: () -> Content

  var body: some View {
    ScrollView([.horizontal, .vertical], showsIndicators: showsIndicators) { content() }
  }
}

#endif

