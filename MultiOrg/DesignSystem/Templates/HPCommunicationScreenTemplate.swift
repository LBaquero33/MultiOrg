import SwiftUI

/// Template 8 — **Communication list / thread split view**.
///
/// Purpose: read and reply. Anatomy: conversation list (`HPAvatar` + name +
/// preview + unread) ↔ thread (message bubbles + composer).
///
/// Responsive: iPhone = list, push to thread (one at a time);
/// iPad/macOS = list left + thread right. AX3 = list only, full width.
///
/// Rules:
/// - Unread is a badge **and** a weight change — never color alone.
/// - The composer stays reachable; Send is the only `.primary` in the thread.
/// - Presentation only — do not rebuild DM transport or notification producers.
struct HPCommunicationScreenTemplate: View {
  @Environment(\.dynamicTypeSize) private var dts

  var isWide: Bool = false
  var state: HPTemplateState = .loaded
  /// On compact widths the screen shows one pane at a time.
  var showsThreadOnCompact: Bool = false

  @State private var draft = ""

  var body: some View {
    Group {
      if isWide && !dts.isAccessibilitySize {
        HStack(alignment: .top, spacing: HP.Space.md) {
          conversationList.frame(width: 320)
          thread.frame(maxWidth: .infinity)
        }
        .padding(HP.Space.md)
      } else {
        ScrollView {
          VStack(alignment: .leading, spacing: HP.Space.md) {
            if showsThreadOnCompact { thread } else { conversationList }
          }
          .padding(HP.Space.md)
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(HP.Color.bg)
  }

  private var conversationList: some View {
    VStack(alignment: .leading, spacing: HP.Space.md) {
      HPWorkspaceHeader("Messages",
                        orgLabel: HPSample.orgIdentity.name,
                        context: "2 unread",
                        identity: HPSample.orgIdentity) {
        HPButton(title: "New", systemImage: "square.and.pencil", variant: .primary, size: .sm)
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
                         actionTitle: "New message")
          case .loaded:
            conversationRow(name: "Coach Ramirez", preview: "Nice work on the squat progression.", time: "2m", unread: 2)
            conversationRow(name: "14U National", preview: "Practice moved to Cage 2 tonight.", time: "1h", unread: 1)
            conversationRow(name: "Front Desk", preview: "Your July invoice is available.", time: "Yesterday", unread: 0)
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

  private var thread: some View {
    VStack(alignment: .leading, spacing: HP.Space.md) {
      HPWorkspaceHeader("Coach Ramirez",
                        orgLabel: HPSample.orgIdentity.name,
                        context: "14U National",
                        identity: HPSample.orgIdentity)
      HPCard {
        VStack(alignment: .leading, spacing: HP.Space.sm) {
          bubble(text: "Nice work on the squat progression.", mine: false, time: "2:14 PM")
          bubble(text: "Thanks! Felt strong today.", mine: true, time: "2:16 PM")
          bubble(text: "Let’s add a heavy triple next week.", mine: false, time: "2:18 PM")
        }
      }
      HPCard {
        let layout = dts.isAccessibilitySize
          ? AnyLayout(VStackLayout(alignment: .leading, spacing: HP.Space.sm))
          : AnyLayout(HStackLayout(alignment: .bottom, spacing: HP.Space.sm))
        layout {
          HPFormField(label: "Message", text: $draft, kind: .multiline, placeholder: "Write a message")
          HPButton(title: "Send", systemImage: "paperplane.fill", variant: .primary, size: .md,
                   fullWidth: dts.isAccessibilitySize)
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
