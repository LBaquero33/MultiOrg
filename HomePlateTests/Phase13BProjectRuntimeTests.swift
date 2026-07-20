import Foundation
import Testing
@testable import HomePlate

@Suite("Phase 13B project and runtime identity")
struct Phase13BProjectRuntimeTests {
  private let phase13ASources = [
    "RootView.swift",
    "AppState.swift",
    "TeamOperationsModels.swift",
    "HomePlateNavigationShell.swift",
    "CoachRootView.swift",
    "CoachTeamCommandCenterView.swift",
    "CoachTeamScheduleView.swift",
  ]

  @Test("iOS and macOS targets compile the current Phase 13A shell")
  func currentShellTargetMembership() throws {
    let project = try sourceFile("HomePlate.xcodeproj/project.pbxproj")
    for target in ["HomePlate", "HomePlateMac"] {
      let sources = try sourcePhase(for: target, in: project)
      for filename in phase13ASources {
        #expect(sources.contains("/* \(filename) in Sources */"), "\(filename) is missing from \(target)")
      }
      #expect(sources.contains("/* HPBuildDiagnostics.swift in Sources */"))
      #expect(sources.contains("/* HomePlateApp.swift in Sources */"))
    }
  }

  @Test("production source has one app entry and the current root chain")
  func oneProductionEntryAndCurrentRoot() throws {
    let swiftFiles = try recursiveSwiftFiles(in: root.appendingPathComponent("HomePlate"))
    let entryFiles = try swiftFiles.filter {
      try String(contentsOf: $0, encoding: .utf8).contains("@main")
    }
    #expect(entryFiles.map(\.lastPathComponent) == ["HomePlateApp.swift"])

    let app = try sourceFile("HomePlate/App/HomePlateApp.swift")
    let rootView = try sourceFile("HomePlate/App/RootView.swift")
    let homeView = try sourceFile("HomePlate/Features/Home/HomeView.swift")
    #expect(app.contains("RootView()"))
    #expect(rootView.contains("HomeView()"))
    #expect(homeView.contains("SDAuthenticatedWorkspace.resolve"))
    #expect(homeView.contains("CoachRootView()"))
  }

  @Test("legacy owner workspace block is not wired into production")
  func legacyOwnerBlockAbsent() throws {
    let ownerOverview = try sourceFile("HomePlate/Features/Coach/CoachTeamCommandCenterView.swift")
    #expect(!ownerOverview.contains("Open authoritative workspace"))
    #expect(!ownerOverview.contains("Registration and Organization Administration"))
    #expect(!ownerOverview.contains("Review Receivables and Expenses"))
  }

  @Test("schemes run, profile, analyze, and archive intended targets")
  func sharedSchemes() throws {
    let ios = try sourceFile("HomePlate.xcodeproj/xcshareddata/xcschemes/HomePlate.xcscheme")
    let mac = try sourceFile("HomePlate.xcodeproj/xcshareddata/xcschemes/HomePlateMac.xcscheme")

    try expectScheme(ios, target: "HomePlate", includesTests: true)
    try expectScheme(mac, target: "HomePlateMac", includesTests: false)
  }

  @Test("project source of truth preserves identifiers and presents Home Plate")
  func projectAndInfoContracts() throws {
    let spec = try sourceFile("project.yml")
    #expect(spec.contains("name: HomePlate"))
    #expect(spec.contains("HomePlate:\n    type: application\n    platform: iOS\n    productName: Home Plate"))
    #expect(spec.contains("HomePlateMac:\n    type: application\n    platform: macOS\n    productName: Home Plate"))
    #expect(spec.contains("PRODUCT_BUNDLE_IDENTIFIER: com.multiorg.app\n"))
    #expect(spec.contains("PRODUCT_BUNDLE_IDENTIFIER: com.multiorg.app.mac\n"))
    #expect(spec.contains("path: Configs/HomePlate-iOS-Info.plist"))
    #expect(spec.contains("path: Configs/HomePlate-macOS-Info.plist"))

    for path in ["Configs/HomePlate-iOS-Info.plist", "Configs/HomePlate-macOS-Info.plist"] {
      let info = try propertyList(path)
      #expect(info["CFBundleDisplayName"] as? String == "Home Plate")
      #expect(info["CFBundleName"] as? String == "Home Plate")
      #expect(info["DHD_APP_DISPLAY_NAME"] as? String == "Home Plate")
      #expect(info["CFBundleShortVersionString"] as? String == "$(MARKETING_VERSION)")
      #expect(info["CFBundleVersion"] as? String == "$(CURRENT_PROJECT_VERSION)")
      let urlTypes = try #require(info["CFBundleURLTypes"] as? [[String: Any]])
      #expect(urlTypes.first?["CFBundleURLName"] as? String == "com.homeplate.invitation")
      #expect(urlTypes.first?["CFBundleURLSchemes"] as? [String] == ["homeplate"])
    }
  }

  @Test("debug builds embed a complete runtime identity contract")
  func buildIdentityContract() throws {
    let spec = try sourceFile("project.yml")
    let diagnostics = try sourceFile("HomePlate/Core/HPBuildDiagnostics.swift")
    let app = try sourceFile("HomePlate/App/HomePlateApp.swift")

    for key in ["CommitSHA", "BuildTimestamp", "TargetName", "SchemeName", "Configuration", "BundleIdentifier", "MarketingVersion", "BuildNumber", "RootShellIdentifier"] {
      #expect(spec.contains("Add :\(key) string"), "Missing embedded build identity key \(key)")
      #expect(diagnostics.contains(key), "Runtime diagnostics do not report \(key)")
    }
    #expect(spec.components(separatedBy: "homeplate.phase13a.root").count - 1 == 2)
    #expect(diagnostics.contains("#if DEBUG"))
    #expect(diagnostics.contains("static let rootShellIdentifier = \"homeplate.phase13a.root\""))
    #expect(app.contains("HPBuildDiagnostics.logRuntimeIdentity()"))
  }

  @Test("owner navigation keeps Phase 13A scope boundaries")
  func ownerNavigationScope() throws {
    let shell = try sourceFile("HomePlate/Features/Home/HomePlateNavigationShell.swift")
    let team = try sourceFile("HomePlate/Features/Coach/CoachTeamCommandCenterView.swift")
    let schedule = try sourceFile("HomePlate/Features/Coach/CoachTeamScheduleView.swift")
    let admin = try sourceFile("HomePlate/Features/Admin/OrgAdminConsoleView.swift")

    #expect(shell.contains("let team = item(.coachTeam, \"Team\""))
    #expect(shell.contains("let schedule = item(.coachSchedule, \"Schedule\""))
    #expect(shell.contains("let organization = item(.organizationAdmin, \"Organization\""))
    #expect(team.contains("CoachTeamSelector()"))
    #expect(schedule.contains("Visible filter: \\(selectedTeamFilterName)"))
    #expect(schedule.contains("Button(allTeamsLabel) { teamFilterId = nil }"))
    #expect(schedule.contains("Label(selectedTeamFilterName, systemImage: \"person.3\")"))
    #expect(!admin.contains("CoachTeamSelector()"))
    for title in ["Overview", "People", "Teams & Seasons", "Business", "Settings"] {
      #expect(admin.contains("= \"\(title)\""))
    }
  }

  private func expectScheme(_ source: String, target: String, includesTests: Bool) throws {
    #expect(source.contains("BlueprintName = \"\(target)\""))
    #expect(source.contains("BuildableName = \"Home Plate.app\""))
    #expect(source.contains("<LaunchAction\n      buildConfiguration = \"Debug\""))
    #expect(source.contains("<ProfileAction\n      buildConfiguration = \"Release\""))
    #expect(source.contains("<AnalyzeAction\n      buildConfiguration = \"Debug\""))
    #expect(source.contains("<ArchiveAction\n      buildConfiguration = \"Release\""))
    #expect(source.contains("BlueprintName = \"HomePlateTests\"") == includesTests)
  }

  private func sourcePhase(for target: String, in project: String) throws -> String {
    let nativeTargets = try slice(project, from: "/* Begin PBXNativeTarget section */", to: "/* End PBXNativeTarget section */")
    let targetBody = try slice(nativeTargets, from: "/* \(target) */ = {", to: "\n\t\t};")
    let sourceLine = try #require(targetBody.split(separator: "\n").first { $0.contains("/* Sources */") })
    let sourceID = try #require(
      sourceLine.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ").first.map(String.init)
    )
    return try slice(project, from: "\(sourceID) /* Sources */ = {", to: "\n\t\t};")
  }

  private func propertyList(_ relativePath: String) throws -> [String: Any] {
    let data = try Data(contentsOf: root.appendingPathComponent(relativePath))
    return try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
  }

  private func recursiveSwiftFiles(in directory: URL) throws -> [URL] {
    let enumerator = try #require(FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil))
    return enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }.sorted { $0.path < $1.path }
  }

  private func sourceFile(_ relativePath: String) throws -> String {
    try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
  }

  private func slice(_ source: String, from start: String, to end: String) throws -> String {
    let lower = try #require(source.range(of: start))
    let upper = try #require(source.range(of: end, range: lower.upperBound..<source.endIndex))
    return String(source[lower.lowerBound..<upper.lowerBound])
  }

  private var root: URL {
    URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
  }
}
