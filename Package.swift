// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "OMFK",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "OMFK", targets: ["OMFK"])
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "OMFK",
            dependencies: [],
            path: "OMFK/Sources",
            resources: [
                .process("Resources")
            ],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "OMFKTests",
            dependencies: ["OMFK"],
            path: "OMFK/Tests"
        )
    ]
)
