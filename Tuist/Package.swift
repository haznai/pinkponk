// swift-tools-version: 6.0
import PackageDescription

#if TUIST
  import struct ProjectDescription.PackageSettings

  let packageSettings =
    PackageSettings(// Customize the product types for specific package product
    // Default is .staticFramework
    // productTypes: ["Alamofire": .framework,]
    )
#endif

let package = Package(
  name: "pinkponk",
  dependencies: [
    .package(url: "https://github.com/swift-server/async-http-client", from: "1.25.1"),
    // Careful: This package and version has been defined in `Project.Swift` aswell
    // The `Project.Swift` containts the Build Tool plugin, here we import the `Lighter` Library used
    // By the derivatives of the Enlighter Build tool Plugin.
    .package(url: "https://github.com/Lighter-swift/Lighter", from: "1.4.10"),
    .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.18.0"),
  ],
  swiftLanguageModes: [.v6]
)
