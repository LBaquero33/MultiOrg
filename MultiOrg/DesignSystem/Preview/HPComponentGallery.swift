import SwiftUI

/// Preview-only gallery of the Stage 3A design system. Not wired into any
/// production screen. Rendered by Xcode `#Preview` and by the screenshot
/// render test. Sample data comes from `HPSample` (local mock only).
///
/// The gallery is fully width-flexible — it contains **no fixed widths** and is
/// designed to fit within a compact iPhone safe area (≈393 pt). Groups that
/// could otherwise overflow a row (buttons, status badges) use `FlowLayout`,
/// which wraps to additional rows and degrades to a single column when items
/// are wide (e.g. at accessibility text sizes).
struct HPComponentGallery: View {
  var body: some View {
    VStack(alignment: .leading, spacing: HP.Space.lg) {
      HPWorkspaceHeader("Home Plate OS — Design System",
                        orgLabel: "Stage 3A · SF Pro",
                        context: "Token + foundation polish pass") {
        HPButton(title: "Primary", systemImage: "sparkles", size: .sm)
      }
      HPGalleryPaletteSection()
      HPGallerySurfacesSection()
      HPGalleryTypographySection()
      HPGalleryHeadersSection()
      HPGalleryCardsSection()
      HPGalleryButtonsSection()
      HPGalleryBadgesSection()
      HPGalleryMetricsSection()
      HPGalleryStatesSection()
    }
    .padding(HP.Space.lg)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(HP.Color.bg)
  }
}

// MARK: - FlowLayout — wraps subviews to new rows; single column when too wide

private struct FlowLayout: Layout {
  var spacing: CGFloat = HP.Space.sm

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
    let maxWidth = proposal.width ?? .infinity
    var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxRowWidth: CGFloat = 0
    for sub in subviews {
      let size = sub.sizeThatFits(.unspecified)
      if x > 0, x + size.width > maxWidth {
        maxRowWidth = max(maxRowWidth, x - spacing)
        x = 0
        y += rowHeight + spacing
        rowHeight = 0
      }
      x += size.width + spacing
      rowHeight = max(rowHeight, size.height)
    }
    maxRowWidth = max(maxRowWidth, x - spacing)
    return CGSize(width: min(maxRowWidth, maxWidth), height: y + rowHeight)
  }

  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
    let maxWidth = bounds.width
    var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
    for sub in subviews {
      let size = sub.sizeThatFits(.unspecified)
      if x > bounds.minX, x + size.width - bounds.minX > maxWidth {
        x = bounds.minX
        y += rowHeight + spacing
        rowHeight = 0
      }
      sub.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
      x += size.width + spacing
      rowHeight = max(rowHeight, size.height)
    }
  }
}

// MARK: - Section scaffolding

private struct HPGallerySection<Content: View>: View {
  let title: String
  @ViewBuilder let content: () -> Content
  var body: some View {
    VStack(alignment: .leading, spacing: HP.Space.sm) {
      Text(title.uppercased())
        .font(HP.Font.eyebrow).tracking(HP.Font.eyebrowTracking)
        .foregroundStyle(HP.Color.accent)
        .fixedSize(horizontal: false, vertical: true)
      content()
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

// MARK: - Palette (adaptive grid — fewer columns on iPhone)

private struct HPGalleryPaletteSection: View {
  private let swatches: [(String, Color)] = [
    ("bg", HP.Color.bg), ("surface", HP.Color.surface), ("raised", HP.Color.surfaceRaised),
    ("border", HP.Color.border), ("borderStrong", HP.Color.borderStrong),
    ("text", HP.Color.text), ("muted", HP.Color.textMuted), ("tertiary", HP.Color.textTertiary),
    ("primary", HP.Color.primary), ("glow", HP.Color.primaryGlow), ("accent", HP.Color.accent),
    ("danger", HP.Color.danger), ("success", HP.Color.success), ("warning", HP.Color.warning),
    ("info", HP.Color.info),
  ]
  var body: some View {
    HPGallerySection(title: "Color palette") {
      LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: HP.Space.sm)], spacing: HP.Space.sm) {
        ForEach(swatches, id: \.0) { name, color in
          VStack(spacing: 4) {
            RoundedRectangle(cornerRadius: HP.Radius.sm, style: .continuous)
              .fill(color)
              .frame(height: 40)
              .frame(maxWidth: .infinity)
              .overlay(RoundedRectangle(cornerRadius: HP.Radius.sm).strokeBorder(HP.Color.border, lineWidth: 1))
            Text(name).font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
              .lineLimit(1).minimumScaleFactor(0.7)
          }
        }
      }
    }
  }
}

// MARK: - Surfaces (separation ladder — full-width rows, no clipping)

private struct HPGallerySurfacesSection: View {
  var body: some View {
    HPGallerySection(title: "Surface separation") {
      VStack(spacing: 0) {
        swatch("Page background", HP.Color.bg)
        swatch("Flat surface", HP.Color.surface)
        swatch("Raised surface", HP.Color.surfaceRaised)
        swatch("Bordered container", HP.Color.surface, bordered: true)
      }
      .clipShape(RoundedRectangle(cornerRadius: HP.Radius.lg, style: .continuous))
      .overlay(RoundedRectangle(cornerRadius: HP.Radius.lg, style: .continuous).strokeBorder(HP.Color.borderStrong, lineWidth: 1))
    }
  }
  private func swatch(_ label: String, _ color: Color, bordered: Bool = false) -> some View {
    Text(label)
      .font(HP.Font.callout).foregroundStyle(HP.Color.text)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(HP.Space.md)
      .background(color)
      .overlay(alignment: .top) { if bordered { Rectangle().fill(HP.Color.borderStrong).frame(height: 1) } }
  }
}

// MARK: - Typography

private struct HPGalleryTypographySection: View {
  var body: some View {
    HPGallerySection(title: "Typography") {
      HPCard {
        VStack(alignment: .leading, spacing: HP.Space.sm) {
          Text("Display / 34").font(HP.Font.display).tracking(HP.Font.displayTracking).foregroundStyle(HP.Color.text)
          Text("Title / 22").font(HP.Font.title).tracking(HP.Font.titleTracking).foregroundStyle(HP.Color.text)
          Text("Headline / 17").font(HP.Font.headline).foregroundStyle(HP.Color.text)
          Text("Body / 16 — the operating system for baseball organizations.").font(HP.Font.body).foregroundStyle(HP.Color.text)
          Text("Callout / 15").font(HP.Font.callout).foregroundStyle(HP.Color.textMuted)
          Text("Caption / 13").font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
          Text("EYEBROW / 12").font(HP.Font.eyebrow).tracking(HP.Font.eyebrowTracking).foregroundStyle(HP.Color.accent)
          Text("88.4 mph  ·  $18,240").font(HP.Font.number()).foregroundStyle(HP.Color.text)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
  }
}

// MARK: - Workspace headers (standardized: org label · title · context · one action)

private struct HPGalleryHeadersSection: View {
  var body: some View {
    HPGallerySection(title: "Workspace headers — HP identity vs. org identity") {
      VStack(spacing: HP.Space.sm) {
        HPWorkspaceHeader("Finance",
                          orgLabel: "Home Plate",
                          context: "Last 12 weeks · All locations",
                          identity: .homePlate) {
          HPButton(title: "New Expense", systemImage: "plus", size: .sm)
        }
        HPWorkspaceHeader("Finance",
                          orgLabel: HPSample.orgIdentity.name,
                          context: "Last 12 weeks · All locations",
                          identity: HPSample.orgIdentity) {
          HPButton(title: "New Expense", systemImage: "plus", size: .sm)
        }
      }
    }
  }
}

// MARK: - Cards

private struct HPGalleryCardsSection: View {
  @Environment(\.dynamicTypeSize) private var dts
  var body: some View {
    // Collapse to a single full-width column at accessibility sizes.
    let layout = dts.isAccessibilitySize
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: HP.Space.md))
      : AnyLayout(HStackLayout(alignment: .top, spacing: HP.Space.md))
    return HPGallerySection(title: "Cards — flat & elevated") {
      layout {
        HPCard(style: .flat) {
          VStack(alignment: .leading, spacing: 6) {
            HPSectionHeader("Flat card")
            Text("Grouped surface, no shadow.").font(HP.Font.callout).foregroundStyle(HP.Color.textMuted)
              .fixedSize(horizontal: false, vertical: true)
          }.frame(maxWidth: .infinity, alignment: .leading)
        }
        HPCard(style: .elevated) {
          VStack(alignment: .leading, spacing: 6) {
            HPSectionHeader("Elevated card") { HPStatusBadge(text: "Live", kind: .success) }
            Text("Raised surface + soft shadow.").font(HP.Font.callout).foregroundStyle(HP.Color.textMuted)
              .fixedSize(horizontal: false, vertical: true)
          }.frame(maxWidth: .infinity, alignment: .leading)
        }
      }
    }
  }
}

// MARK: - Buttons (variants × states — wrapping flow, full labels)

private struct HPGalleryButtonsSection: View {
  var body: some View {
    HPGallerySection(title: "Buttons — variants & states") {
      HPCard {
        VStack(alignment: .leading, spacing: HP.Space.sm) {
          row("Variants") {
            HPButton(title: "Primary", variant: .primary)
            HPButton(title: "Secondary", variant: .secondary)
            HPButton(title: "Tertiary", variant: .tertiary)
            HPButton(title: "Delete", variant: .destructive)
          }
          row("Sizes") {
            HPButton(title: "Small", size: .sm)
            HPButton(title: "Medium", size: .md)
            HPButton(title: "Large", size: .lg)
          }
          row("States") {
            HPButton(title: "Icon", systemImage: "bolt.fill")
            HPButton(title: "Loading", isLoading: true)
            HPButton(title: "Disabled").disabled(true)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
  }
  @ViewBuilder private func row<C: View>(_ label: String, @ViewBuilder _ content: () -> C) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(label).font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
      FlowLayout(spacing: HP.Space.sm) { content() }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
  }
}

// MARK: - Badges (wrapping flow layout)

private struct HPGalleryBadgesSection: View {
  var body: some View {
    HPGallerySection(title: "Status badges") {
      HPCard {
        FlowLayout(spacing: HP.Space.sm) {
          HPStatusBadge(text: "Neutral", kind: .neutral)
          HPStatusBadge(text: "Paid", kind: .success)
          HPStatusBadge(text: "Overdue", kind: .warning)
          HPStatusBadge(text: "Failed", kind: .danger)
          HPStatusBadge(text: "Info", kind: .info)
          HPStatusBadge(text: "Founding", kind: .gold)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
  }
}

// MARK: - Metrics (player + finance — adaptive 1–2 column grid)

private struct HPGalleryMetricsSection: View {
  @Environment(\.dynamicTypeSize) private var dts

  // Adaptive 2-column at normal sizes; single full-width column at accessibility.
  private var columns: [GridItem] {
    dts.isAccessibilitySize
      ? [GridItem(.flexible(), spacing: HP.Space.sm)]
      : [GridItem(.adaptive(minimum: 150), spacing: HP.Space.sm)]
  }

  var body: some View {
    HPGallerySection(title: "Metrics — player & finance") {
      VStack(alignment: .leading, spacing: HP.Space.sm) {
        Text("Player development").font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
        LazyVGrid(columns: columns, spacing: HP.Space.sm) {
          ForEach(HPSample.playerMetrics) { m in
            HPMetricCard(title: m.title, value: m.value, unit: m.unit, delta: m.delta, trend: m.trend, context: m.context, valueColor: m.valueColor)
          }
        }
        Text("Finance").font(HP.Font.caption).foregroundStyle(HP.Color.textMuted).padding(.top, 4)
        LazyVGrid(columns: columns, spacing: HP.Space.sm) {
          ForEach(HPSample.financeMetrics) { m in
            HPMetricCard(title: m.title, value: m.value, unit: m.unit, delta: m.delta, trend: m.trend, context: m.context, valueColor: m.valueColor)
          }
        }
      }
    }
  }
}

// MARK: - States (loading / empty / error — primary CTA emphasis)

private struct HPGalleryStatesSection: View {
  var body: some View {
    HPGallerySection(title: "States — loading, empty, error") {
      VStack(spacing: HP.Space.sm) {
        HPCard {
          VStack(alignment: .leading, spacing: HP.Space.sm) {
            HPSectionHeader("Loading (skeleton)")
            HPSkeleton(height: 16)
            HPSkeleton(height: 16)
            HPSkeleton(height: 16).frame(maxWidth: 180)
            HPLoadingState(text: "Loading finance overview…")
          }.frame(maxWidth: .infinity, alignment: .leading)
        }
        HPCard {
          HPEmptyState(title: "No payments yet",
                       message: "Successful payments in this range will appear here.",
                       systemImage: "creditcard",
                       actionTitle: "Create request") {}
        }
        HPCard {
          HPErrorState(message: "We couldn't load the finance overview. Check your connection and try again.") {}
        }
      }
    }
  }
}

#if DEBUG
#Preview("iPhone") { ScrollView { HPComponentGallery() }.frame(width: 393) }
#Preview("iPad width") { ScrollView { HPComponentGallery() }.frame(width: 834) }
#Preview("Dynamic Type XL") {
  ScrollView { HPComponentGallery() }.frame(width: 393).environment(\.dynamicTypeSize, .accessibility3)
}
#endif
