// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
  name: "DisplayTool",
  platforms: [.macOS(.v13)],
  dependencies: [
    .package(
      url: "https://github.com/apple/swift-argument-parser.git",
      from: "1.5.0"
    )
  ],
  targets: [
    .target(name: "DisplayCore", dependencies: ["VirtualDisplayBridge"]),
    .executableTarget(name: "DisplayMenu", dependencies: ["DisplayCore", "VirtualDisplayBridge"]),
    .target(
      name: "VirtualDisplayBridge",
      cSettings: [.unsafeFlags(["-fobjc-arc"])],
      linkerSettings: [.linkedFramework("CoreGraphics")]
    ),
    // Targets are the basic building blocks of a package, defining a module or a test suite.
    // Targets can depend on other targets in this package and products from dependencies.
    .executableTarget(
      name: "DisplayTool",
      dependencies: [
        "VirtualDisplayBridge",
        "DisplayCore",
        .product(name: "ArgumentParser", package: "swift-argument-parser")
      ]
    ),
    .testTarget(name: "DisplayToolTests", dependencies: ["DisplayTool", "DisplayCore", "DisplayMenu"])
  ]
)
