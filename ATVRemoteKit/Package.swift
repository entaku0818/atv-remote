// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ATVRemoteKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "ATVRemoteKit", targets: ["ATVRemoteKit"]),
        .executable(name: "atvremote-cli", targets: ["atvremote-cli"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.28.0"),
    ],
    targets: [
        .target(
            name: "ATVRemoteKit",
            dependencies: [
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
            ]
        ),
        .executableTarget(
            name: "atvremote-cli",
            dependencies: ["ATVRemoteKit"]
        ),
        .testTarget(
            name: "ATVRemoteKitTests",
            dependencies: ["ATVRemoteKit"]
        ),
    ]
)
