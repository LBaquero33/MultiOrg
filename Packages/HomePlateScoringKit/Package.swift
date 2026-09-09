// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "HomePlateScoringKit",
  platforms: [.iOS(.v17), .macOS(.v14)],
  products: [
    .library(name: "HomePlateScoringCore", targets: ["HomePlateScoringCore"]),
    .library(name: "HomePlateScoringStore", targets: ["HomePlateScoringStore"]),
    .library(name: "HomePlateScoringUI", targets: ["HomePlateScoringUI"]),
  ],
  targets: [
    .target(name: "HomePlateScoringCore"),
    .target(
      name: "HomePlateScoringStore",
      dependencies: ["HomePlateScoringCore"],
      linkerSettings: [.linkedLibrary("sqlite3")]
    ),
    .target(
      name: "HomePlateScoringUI",
      dependencies: ["HomePlateScoringCore", "HomePlateScoringStore"],
      exclude: ["ScoringLabRootView.swift"],
      resources: [.process("Resources")]
    ),
    .testTarget(name: "HomePlateScoringKitTests", dependencies: [
      "HomePlateScoringCore", "HomePlateScoringStore", "HomePlateScoringUI",
    ]),
  ]
)
