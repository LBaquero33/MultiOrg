import Foundation

enum SupabaseConfigError: LocalizedError, Equatable {
  case missingHost
  case missingAnonKey
  case invalidAnonKey
  case invalidHost(String)

  var errorDescription: String? {
    switch self {
    case .missingHost:
      return "Missing SUPABASE_HOST. Add it in Configs/Secrets.xcconfig."
    case .missingAnonKey:
      return "Missing SUPABASE_ANON_KEY. Add it in Configs/Secrets.xcconfig."
    case .invalidAnonKey:
      return "SUPABASE_ANON_KEY looks wrong. Use the Supabase Dashboard publishable or anon/public key."
    case .invalidHost(let raw):
      return "Invalid SUPABASE_HOST: \(raw)"
    }
  }
}

struct SupabaseConfig: Equatable {
  let url: URL
  let anonKey: String

  static func fromInfoPlist() -> Result<SupabaseConfig, SupabaseConfigError> {
    let hostRaw = (Bundle.main.object(forInfoDictionaryKey: "SUPABASE_HOST") as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let keyRaw = (Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

    guard !hostRaw.isEmpty else {
      return .failure(.missingHost)
    }
    let fullURLRaw = "https://\(hostRaw)"
    guard let url = URL(string: fullURLRaw), url.host != nil else { return .failure(.invalidHost(hostRaw)) }
    guard !keyRaw.isEmpty else {
      return .failure(.missingAnonKey)
    }
    // Legacy anon keys are JWT-like; current Supabase projects use publishable keys.
    guard keyRaw.hasPrefix("eyJ") || keyRaw.hasPrefix("sb_publishable_") else {
      return .failure(.invalidAnonKey)
    }
    return .success(SupabaseConfig(url: url, anonKey: keyRaw))
  }
}
