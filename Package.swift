// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "DraftSmith",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "DraftSmith", targets: ["DraftSmith"])
    ],
    targets: [
        .executableTarget(
            name: "DraftSmith",
            path: "AppSources/DraftSmith",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("NaturalLanguage"),
                .linkedFramework("PDFKit"),
                .linkedFramework("Security"),
                .linkedFramework("Vision")
            ]
        ),
        .testTarget(
            name: "DraftSmithTests",
            dependencies: ["DraftSmith"],
            path: "Tests/DraftSmithTests"
        )
    ],
    swiftLanguageModes: [.v5]
)
