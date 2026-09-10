// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SourceDesk",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "SourceDesk",
            path: "SourceDesk",
            exclude: [
                "Resources"
            ],
            linkerSettings: [
                .linkedFramework("SwiftData"),
                .linkedFramework("Network"),
                .linkedFramework("PDFKit"),
                .linkedFramework("Security"),
                .linkedFramework("AppKit"),
                .linkedFramework("UniformTypeIdentifiers"),
                .linkedFramework("SwiftUI")
            ]
        ),
        .testTarget(
            name: "SourceDeskTests",
            dependencies: ["SourceDesk"],
            path: "SourceDeskTests"
        )
    ]
)