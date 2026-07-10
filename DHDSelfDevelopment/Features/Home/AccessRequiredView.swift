import SwiftUI

struct AccessRequiredView: View {
  @EnvironmentObject private var appState: AppState
  @Environment(\.openURL) private var openURL

  @State private var checkoutError: String?

  private var stripeSubscribeURL: URL? {
    let rawAny = Bundle.main.object(forInfoDictionaryKey: "DHD_STRIPE_SUBSCRIBE_URL")
    let raw0 = (rawAny as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let raw = raw0.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
    guard !raw.isEmpty else { return nil }
    // `.xcconfig` treats `https://` as a comment (because of `//`). To avoid that, we allow values like:
    // - `buy.stripe.com/abc123`
    // - `https://buy.stripe.com/abc123`
    let candidate = raw.lowercased().hasPrefix("http") ? raw : "https://\(raw)"
    guard let url = URL(string: candidate), url.scheme?.hasPrefix("http") == true, url.host != nil else { return nil }
    return url
  }

  private func withClientReferenceId(base: URL, userId: UUID) -> URL {
    let key = "client_reference_id"
    let val = userId.uuidString

    guard var comps = URLComponents(url: base, resolvingAgainstBaseURL: false) else { return base }
    var items = comps.queryItems ?? []
    // Remove any existing value so we always override.
    items.removeAll { $0.name == key }
    items.append(URLQueryItem(name: key, value: val))
    comps.queryItems = items
    return comps.url ?? base
  }

  var body: some View {
    VStack(spacing: 14) {
      Image(systemName: "lock.shield")
        .font(.system(size: 44, weight: .semibold))
        .foregroundStyle(.secondary)

      Text("Access required")
        .font(.title3.weight(.semibold))

      Text("This app requires an active training membership on your account. If you believe this is a mistake, contact support.")
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)

      HStack(spacing: 10) {
        Button {
          Task { await appState.refreshEntitlement() }
        } label: {
          Label("Retry", systemImage: "arrow.clockwise")
        }
        .buttonStyle(.bordered)

        if let supportEmail = DHDAppConfig.supportEmail, !supportEmail.isEmpty {
          Button {
            if let mail = URL(string: "mailto:\(supportEmail)") {
              openURL(mail)
            } else {
              checkoutError = "Support email is not configured correctly."
            }
          } label: {
            Label("Email support", systemImage: "envelope")
          }
          .buttonStyle(.bordered)
        }
      }

      if let checkoutError {
        Text(checkoutError)
          .font(.footnote)
          .foregroundStyle(.red)
          .multilineTextAlignment(.center)
      }

      Button {
        checkoutError = nil
        Task {
          do {
            guard let supabase = appState.supabase else {
              throw NSError(domain: "DHD", code: 1, userInfo: [NSLocalizedDescriptionKey: "Supabase not configured."])
            }
            guard let base = stripeSubscribeURL else {
              throw NSError(domain: "DHD", code: 2, userInfo: [NSLocalizedDescriptionKey: "Stripe subscribe link not configured."])
            }
            let session = try await supabase.client.auth.session
            let uid = session.user.id
            let url = withClientReferenceId(base: base, userId: uid)
            openURL(url)
          } catch {
            checkoutError = error.localizedDescription
          }
        }
      } label: {
        Text("Subscribe (6-month)")
          .frame(maxWidth: .infinity)
      }
      .buttonStyle(.borderedProminent)

      if let website = DHDAppConfig.websiteURL {
        Button {
          openURL(website)
        } label: {
          Text("Open website")
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(.secondary)
      }

      Button(role: .destructive) {
        Task { await appState.signOut() }
      } label: {
        Text("Sign Out")
          .frame(maxWidth: .infinity)
      }
      .buttonStyle(.borderedProminent)
      .tint(.red)
      .padding(.top, 6)
    }
    .padding()
  }
}
