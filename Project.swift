import ProjectDescription

let project = Project(
    name: "pinkponk",
    packages: [.remote(url: "https://github.com/Lighter-swift/Lighter", requirement: .upToNextMajor(from: "1.4.10"))],
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
            dependencies: [.external(name: "AsyncHTTPClient"), .package(product: "Enlighter", type: .plugin), .external(name: "Lighter")]
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
            dependencies: [.target(name: "pinkponk")]
        ),
    ]
)
