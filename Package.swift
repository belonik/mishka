// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Mishka",
    platforms: [
        .macOS(.v15)
    ],
    targets: [
        .executableTarget(
            name: "Mishka",
            path: "Sources/Mishka",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
