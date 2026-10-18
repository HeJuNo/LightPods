// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "BlazePodKit",
    platforms: [.iOS(.v15), .macOS(.v12)],
    products: [
        .library(name: "BlazePodKit", targets: ["BlazePodKit"]),
    ],
    targets: [
        // Pure protocol logic: no CoreBluetooth, fully unit-testable.
        .target(name: "BlazePodProtocol"),
        // CoreBluetooth transport + pod/session management.
        .target(name: "BlazePodKit", dependencies: ["BlazePodProtocol"]),
        .testTarget(name: "BlazePodProtocolTests", dependencies: ["BlazePodProtocol"]),
    ]
)
