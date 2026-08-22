import SwiftUI

/// Identity avatar. Initials or SF Symbol on a tinted disc. The tint may be an
/// organization's brand color (identity chrome). No network image loading in
/// Stage 3B (previews must not contact the network).
enum HPAvatarSize {
  case xs, sm, md, lg
  var dim: CGFloat { switch self { case .xs: 24; case .sm: 32; case .md: 44; case .lg: 64 } }
  var font: Font { switch self { case .xs: HP.Font.caption; case .sm: HP.Font.callout; case .md: HP.Font.headline; case .lg: HP.Font.title } }
}

struct HPAvatar: View {
  var name: String
  var systemImage: String? = nil
  var size: HPAvatarSize = .md
  var imageURL: URL? = nil
  /// Identity tint — org brand color is allowed here (chrome only).
  var tint: Color = HP.Color.primary
  var showsStatus: Bool = false
  var statusColor: Color = HP.Color.success

  var body: some View {
    ZStack {
      Circle().fill(tint.opacity(0.22))
      Circle().strokeBorder(tint.opacity(0.5), lineWidth: 1)
      if let imageURL {
        AsyncImage(url: imageURL) { phase in
          if let image = phase.image {
            image.resizable().scaledToFill()
          } else {
            Text(initials).font(size.font.weight(.semibold)).foregroundStyle(tint)
          }
        }
        .clipShape(Circle())
      } else if let systemImage {
        Image(systemName: systemImage).font(size.font).foregroundStyle(tint)
      } else {
        Text(initials).font(size.font.weight(.semibold)).foregroundStyle(tint)
      }
    }
    .frame(width: size.dim, height: size.dim)
    .overlay(alignment: .bottomTrailing) {
      if showsStatus {
        Circle().fill(statusColor)
          .frame(width: size.dim * 0.28, height: size.dim * 0.28)
          .overlay(Circle().strokeBorder(HP.Color.bg, lineWidth: 2))
      }
    }
    .accessibilityElement()
    .accessibilityLabel(name)
  }

  private var initials: String {
    let parts = name.split(separator: " ").prefix(2)
    let letters = parts.compactMap { $0.first }.map(String.init)
    return letters.joined().uppercased()
  }
}

struct HPProfileAvatarButton: View {
  @EnvironmentObject private var appState: AppState
  let profile: Profile
  var size: HPAvatarSize = .md
  var showsName = false

  @State private var isPresented = false

  var body: some View {
    Button {
      isPresented = true
    } label: {
      HStack(spacing: HP.Space.xs) {
        HPAvatar(name: profile.displayName, size: size, imageURL: avatarURL)
        if showsName {
          Text(profile.displayName)
            .font(HP.Font.body.weight(.semibold))
            .foregroundStyle(HP.Color.text)
            .lineLimit(1)
        }
      }
    }
    .buttonStyle(.plain)
    .accessibilityLabel("View \(profile.displayName)'s profile")
    .sheet(isPresented: $isPresented) {
      HPProfileSheet(profile: profile)
        .environmentObject(appState)
    }
  }

  private var avatarURL: URL? {
    guard let path = profile.avatar_path else { return nil }
    return appState.supabase?.publicAvatarURL(path: path)
  }
}

private struct HPProfileSheet: View {
  @EnvironmentObject private var appState: AppState
  @Environment(\.dismiss) private var dismiss
  let profile: Profile

  @State private var details: SupabaseService.SDProfileDetails?
  @State private var isLoading = false
  @State private var errorText: String?

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: HP.Space.md) {
          HPAvatar(
            name: details?.full_name ?? profile.displayName,
            size: .lg,
            imageURL: (details?.avatar_path ?? profile.avatar_path).flatMap {
              appState.supabase?.publicAvatarURL(path: $0)
            }
          )
          Text(details?.full_name ?? profile.displayName)
            .font(HP.Font.title.weight(.bold))
            .foregroundStyle(HP.Color.text)
          HPStatusBadge(text: (details?.role ?? profile.role).capitalized, kind: .info)

          if isLoading {
            HPLoadingState(text: "Loading profile…")
          } else if let errorText {
            HPErrorState(message: errorText, onRetry: { Task { await load() } })
          } else if let details {
            HPCard {
              VStack(alignment: .leading, spacing: HP.Space.sm) {
                profileFact("Title", details.professional_title)
                profileFact("Position", details.primary_position)
                profileFact("School", details.school)
                profileFact("Team", details.team)
                profileFact("Graduation year", details.grad_year.map(String.init))
                profileFact("Specialties", details.specialties)
                if let bio = details.bio, !bio.isEmpty {
                  Divider().overlay(HP.Color.border)
                  Text(bio).font(HP.Font.body).foregroundStyle(HP.Color.text)
                }
                if let website = details.website,
                   let url = URL(string: website.hasPrefix("http") ? website : "https://\(website)") {
                  Link(destination: url) {
                    Label("View website", systemImage: "arrow.up.right.square")
                  }
                }
              }
            }
          }
        }
        .padding(HP.Space.md)
      }
      .background(HP.Color.bg)
      .navigationTitle("Profile")
      .toolbar {
        ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
      }
      .task { await load() }
    }
  }

  @ViewBuilder
  private func profileFact(_ label: String, _ value: String?) -> some View {
    if let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      HStack(alignment: .firstTextBaseline) {
        Text(label).font(HP.Font.caption).foregroundStyle(HP.Color.textMuted)
        Spacer()
        Text(value).font(HP.Font.body).foregroundStyle(HP.Color.text).multilineTextAlignment(.trailing)
      }
    }
  }

  private func load() async {
    guard let supabase = appState.supabase else { return }
    isLoading = true
    errorText = nil
    defer { isLoading = false }
    do {
      details = try await supabase.fetchProfileDetails(userId: profile.id)
    } catch {
      errorText = "This profile could not be loaded."
    }
  }
}
