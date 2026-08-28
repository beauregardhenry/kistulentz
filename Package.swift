// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Kistulentz",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "Kistulentz", targets: ["Kistulentz"])
    ],
    targets: [
        .executableTarget(
            name: "Kistulentz",
            path: "AppSources/Kistulentz",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("NaturalLanguage"),
                .linkedFramework("PDFKit"),
                .linkedFramework("Security"),
                .linkedFramework("Vision")
            ]
        ),
        .testTarget(
            name: "KistulentzTests",
            dependencies: ["Kistulentz"],
            path: "Tests/KistulentzTests"
        )
    ],
    swiftLanguageModes: [.v5]
)
