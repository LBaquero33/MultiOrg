import Foundation

enum DHDAppConfig {
  private static func infoString(_ key: String) -> String? {
    let rawAny = Bundle.main.object(forInfoDictionaryKey: key)
    let raw0 = (rawAny as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let raw = raw0.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
    return raw.isEmpty ? nil : raw
  }

  static var displayName: String {
    if let v = infoString("DHD_APP_DISPLAY_NAME") { return v }
    if let v = infoString("CFBundleDisplayName") { return v }
    if let v = infoString("CFBundleName") { return v }
    return "App"
  }

  static var supportEmail: String? {
    infoString("DHD_SUPPORT_EMAIL")
  }

  static var legacyEmailDomain: String {
    infoString("DHD_LEGACY_EMAIL_DOMAIN") ?? "legacy.dhd.local"
  }
}
