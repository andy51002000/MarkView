// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MarkView",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "MarkView",
            path: "Sources/MarkView"
        ),
        .testTarget(
            name: "MarkViewTests",
            dependencies: ["MarkView"],
            path: "Tests/MarkViewTests"
        )
    ]
)
