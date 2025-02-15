import ProjectDescription

func baseSettings() -> SettingsDictionary {
  var settings: SettingsDictionary = [:]
  settings["SWIFT_VERSION"] = "6"
  settings["_EXPERIMENTAL_SWIFT_EXPLICIT_MODULES"] = "true"
  settings["SWIFT_STRICT_CONCURRENCY"] = "complete"

  return settings
}

let project = Project(
  name: "pinkponk",
  packages: [
    .remote(
      // This is declaration for the "Enlighter" Plugin, the `Package.swift` file has the
      // declaration for the "Lighter" Dependency
      url: "https://github.com/Lighter-swift/Lighter", requirement: .upToNextMajor(from: "1.4.10"))
  ],
  targets: [
    .target(
      name: "pinkponk",
      destinations: .macOS,
      product: .app,
      bundleId: "io.tuist.pinkponk",
      deploymentTargets: .macOS("15.1"),
      infoPlist: .default,
      sources: ["pinkponk/Sources/**"],
      resources: ["pinkponk/Resources/**"],
      dependencies: [
        .external(name: "AsyncHTTPClient"),
        .package(product: "Enlighter", type: .plugin),
        .external(name: "Lighter"),
        .external(name: "InlineSnapshotTesting"),
      ],
      settings: Settings.settings(
        base: baseSettings())
    ),
    .target(
      name: "pinkponkTests",
      destinations: .macOS,
      product: .unitTests,
      bundleId: "io.tuist.pinkponkTests",
      deploymentTargets: .macOS("15.1"),
      infoPlist: .default,
      sources: ["pinkponk/Tests/**"],
      resources: [],
      dependencies: [.target(name: "pinkponk")],
      settings: Settings.settings(
        base: baseSettings())
    ),
  ]
)
