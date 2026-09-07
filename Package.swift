// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Hypertime",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "HypertimeCore", targets: ["HypertimeCore"]),
        .executable(name: "Hypertime", targets: ["Hypertime"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
    ],
    targets: [
        .target(
            name: "HypertimeCore",
            dependencies: [.product(name: "GRDB", package: "GRDB.swift")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "Hypertime",
            dependencies: ["HypertimeCore"],
            path: "Sources/Hypertime",
            exclude: ["Resources/Info.plist", "Resources/Hypertime.entitlements", "Resources/AppIcon.appiconset"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "HypertimeCoreTests",
            dependencies: ["HypertimeCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
