// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "BlazePodKit",
    platforms: [.iOS(.v15), .macOS(.v12)],
    products: [
        .library(name: "BlazePodKit", targets: ["BlazePodKit"]),
        .library(name: "BlazePodDrills", targets: ["BlazePodDrills"]),
    ],
    targets: [
        // Pure protocol logic: no CoreBluetooth, fully unit-testable.
        .target(name: "BlazePodProtocol"),
        // CoreBluetooth transport + pod/session management.
        .target(name: "BlazePodKit", dependencies: ["BlazePodProtocol"]),
        // Drill model and engines (Random, Focus); talks to pods through `DrillPodDriver`.
        .target(name: "BlazePodDrills", dependencies: ["BlazePodProtocol"]),
        .testTarget(name: "BlazePodProtocolTests", dependencies: ["BlazePodProtocol"]),
        .testTarget(name: "BlazePodDrillsTests", dependencies: ["BlazePodDrills"]),
    ]
)
