import Foundation

enum HPBuildDiagnostics {
  static let rootShellIdentifier = "homeplate.phase13a.root"

  static func logRuntimeIdentity() {
    #if DEBUG
    let identity = embeddedIdentity
    let value: (String) -> String = { key in
      identity[key] as? String ?? "unknown"
    }
    let version = value("MarketingVersion")
    let build = value("BuildNumber")
    print(
      "[HomePlate.Runtime] "
        + "commit=\(value("CommitSHA")) "
        + "built=\(value("BuildTimestamp")) "
        + "target=\(value("TargetName")) "
        + "scheme=\(value("SchemeName")) "
        + "configuration=\(value("Configuration")) "
        + "bundle=\(value("BundleIdentifier")) "
        + "product=\(value("ProductName")) "
        + "version=\(version)(\(build)) "
        + "root=\(value("RootShellIdentifier"))"
    )
    #endif
  }

  private static var embeddedIdentity: [String: Any] {
    guard let url = Bundle.main.url(forResource: "HomePlateBuildIdentity", withExtension: "plist"),
          let data = try? Data(contentsOf: url),
          let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
          let identity = plist as? [String: Any] else {
      return [
        "BundleIdentifier": Bundle.main.bundleIdentifier ?? "unknown",
        "MarketingVersion": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
        "BuildNumber": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
        "RootShellIdentifier": rootShellIdentifier,
      ]
    }
    return identity
  }
}
