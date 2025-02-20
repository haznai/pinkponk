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
