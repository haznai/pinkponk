// swift-tools-version: 6.0
import PackageDescription

#if TUIST
  import struct ProjectDescription.PackageSettings

  let packageSettings =
    PackageSettings(  // Customize the product types for specific package product
    // Default is .staticFramework
    // productTypes: ["Alamofire": .framework,]
    )
#endif

let package = Package(
  name: "pinkponk",
  dependencies: [
    .package(url: "https://github.com/swift-server/async-http-client", from: "1.25.1"),
    .package(url: "https://github.com/Lighter-swift/Lighter", from: "1.4.10"),
    .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.18.0"),
    .package(url: "https://github.com/apple/swift-async-algorithms", from: "1.0.3"),
  ]
)
