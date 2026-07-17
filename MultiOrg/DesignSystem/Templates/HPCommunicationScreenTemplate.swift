import SwiftUI

enum HPCommunicationCompactPane: Equatable, Sendable {
  case conversations
  case thread
}

/// Reusable presentation shell for a conversation directory and active thread.
///
/// Unlike the general screen scaffold, this layout intentionally adds no outer
/// `ScrollView`: each pane owns its scrolling so a thread can keep its composer
/// pinned. Transport, navigation, unread state, and send behavior stay with the
/// embedding feature.
struct HPCommunicationScreenLayout<ConversationList: View, Thread: View>: View {
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @State private var containerWidth: CGFloat = 0

  private let widthMode: HPScreenWidthMode
  private let compactPane: HPCommunicationCompactPane
  private let conversationList: (HPScreenLayoutContext) -> ConversationList
  private let thread: (HPScreenLayoutContext) -> Thread

  init(
    widthMode: HPScreenWidthMode = .automatic,
    compactPane: HPCommunicationCompactPane,
    @ViewBuilder conversationList: @escaping (HPScreenLayoutContext) -> ConversationList,
    @ViewBuilder thread: @escaping (HPScreenLayoutContext) -> Thread
  ) {
    self.widthMode = widthMode
    self.compactPane = compactPane
    self.conversationList = conversationList
    self.thread = thread
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
    Group {
      if context.isExpanded {
        HStack(alignment: .top, spacing: HP.Space.md) {
          conversationList(context)
            .frame(width: 320, alignment: .topLeading)
          Rectangle()
            .fill(HP.Color.border)
            .frame(width: 1)
            .accessibilityHidden(true)
          thread(context)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
      } else {
        switch compactPane {
        case .conversations: conversationList(context)
        case .thread: thread(context)
        }
      }
    }
    .padding(HP.Space.md)
    .frame(maxWidth: .infinity, alignment: .topLeading)
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

/// Template 8 — **Communication list / thread split view**.
///
/// Purpose: read and reply. Anatomy: conversation list (`HPAvatar` + name +
/// preview + unread) ↔ thread (message bubbles + composer).
///
/// Responsive: iPhone = list, push to thread (one at a time);
/// iPad/macOS = list left + thread right. AX3 = one active pane at full width
/// (the list by default, or the thread after navigation).
///
/// Rules:
/// - Unread is a badge **and** a weight change — never color alone.
/// - The composer stays reachable; Send is the only `.primary` in the thread.
/// - Presentation only — do not rebuild DM transport or notification producers.
struct HPCommunicationScreenTemplate: View {
  var isWide: Bool = false
  var state: HPTemplateState = .loaded
  /// On compact widths the screen shows one pane at a time.
  var showsThreadOnCompact: Bool = false

  @State private var draft = ""

  var body: some View {
    HPCommunicationScreenLayout(
      widthMode: isWide ? .automatic : .compact,
      compactPane: showsThreadOnCompact ? .thread : .conversations
    ) { context in
      conversationList(context)
    } thread: { context in
      thread(context)
    }
  }

  private func conversationList(_ context: HPScreenLayoutContext) -> some View {
    ScrollView {
      VStack(alignment: .leading, spacing: HP.Space.md) {
        HPWorkspaceHeader("Messages",
                          orgLabel: HPSample.orgIdentity.name,
                          context: "2 unread",
                          identity: HPSample.orgIdentity) {
          HPButton(title: "New", systemImage: "square.and.pencil",
                   variant: context.isExpanded ? .secondary : .primary, size: .sm)
        }
        HPCard {
          VStack(alignment: .leading, spacing: HP.Space.sm) {
            switch state {
            case .loading: HPLoadingState(text: "Loading conversations…")
            case .error:   HPErrorState(message: "We couldn’t load your messages.", onRetry: {})
            case .empty:
              HPEmptyState(title: "No conversations yet",
                           message: "Start a message with your coach or team.",
                           systemImage: "bubble.left.and.bubble.right",
                           actionTitle: "New message",
                           actionIsPrimary: !context.isExpanded,
                           action: {})
            case .loaded:
              conversationRow(name: "Coach Ramirez", preview: "Nice work on the squat progression.", time: "2m", unread: 2)
              conversationRow(name: "14U National", preview: "Practice moved to Cage 2 tonight.", time: "1h", unread: 1)
              conversationRow(name: "Front Desk", preview: "Your July invoice is available.", time: "Yesterday", unread: 0)
            }
          }
        }
      }
    }
  }

  private func conversationRow(name: String, preview: String, time: String, unread: Int) -> some View {
    HStack(alignment: .top, spacing: HP.Space.sm) {
      HPAvatar(name: name, size: .md)
      VStack(alignment: .leading, spacing: 2) {
        HStack {
          // Unread = heavier weight AND a badge (never color alone).
          Text(name)
            .font(unread > 0 ? HP.Font.headline : HP.Font.callout)
            .foregroundStyle(HP.Color.text)
            .fixedSize(horizontal: false, vertical: true)
          Spacer(minLength: HP.Space.xs)
          Text(time).font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
        }
        Text(preview)
          .font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
          .lineLimit(2).fixedSize(horizontal: false, vertical: true)
        if unread > 0 {
          HPStatusBadge(text: "\(unread) unread", kind: .gold)
        }
      }
    }
    .padding(.vertical, 6)
    .accessibilityElement(children: .combine)
  }

  private func thread(_ context: HPScreenLayoutContext) -> some View {
    VStack(alignment: .leading, spacing: HP.Space.md) {
      HPWorkspaceHeader("Coach Ramirez",
                        orgLabel: HPSample.orgIdentity.name,
                        context: "14U National",
                        identity: HPSample.orgIdentity)

      ScrollView {
        HPCard {
          VStack(alignment: .leading, spacing: HP.Space.sm) {
            bubble(text: "Nice work on the squat progression.", mine: false, time: "2:14 PM")
            bubble(text: "Thanks! Felt strong today.", mine: true, time: "2:16 PM")
            bubble(text: "Let’s add a heavy triple next week.", mine: false, time: "2:18 PM")
          }
        }
      }

      HPCard {
        let layout = context.isAccessibilitySize
          ? AnyLayout(VStackLayout(alignment: .leading, spacing: HP.Space.sm))
          : AnyLayout(HStackLayout(alignment: .bottom, spacing: HP.Space.sm))
        layout {
          HPFormField(label: "Message", text: $draft, kind: .multiline, placeholder: "Write a message")
          HPButton(title: "Send", systemImage: "paperplane.fill", variant: .primary, size: .md,
                   fullWidth: context.isAccessibilitySize)
        }
      }
    }
  }

  private func bubble(text: String, mine: Bool, time: String) -> some View {
    VStack(alignment: mine ? .trailing : .leading, spacing: 2) {
      Text(text)
        .font(HP.Font.callout)
        .foregroundStyle(mine ? HP.Color.accentText : HP.Color.text)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, HP.Space.sm)
        .padding(.vertical, HP.Space.xs)
        .background(RoundedRectangle(cornerRadius: HP.Radius.md, style: .continuous)
          .fill(mine ? HP.Color.accent : HP.Color.surfaceRaised))
      Text(time).font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
    }
    .frame(maxWidth: .infinity, alignment: mine ? .trailing : .leading)
    .accessibilityElement(children: .combine)
  }
}

#Preview("Communication — iPhone list") { HPCommunicationScreenTemplate() }
#Preview("Communication — iPhone thread") { HPCommunicationScreenTemplate(showsThreadOnCompact: true) }
#Preview("Communication — iPad/macOS split") { HPCommunicationScreenTemplate(isWide: true) }
