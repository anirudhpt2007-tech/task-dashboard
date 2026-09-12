// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HonestFaceID",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "HonestFaceID", targets: ["HonestFaceID"])
    ],
    targets: [
        .executableTarget(name: "HonestFaceID"),
        .testTarget(name: "HonestFaceIDTests", dependencies: ["HonestFaceID"])
    ]
)
