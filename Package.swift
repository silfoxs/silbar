// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SilBar",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .executable(name: "SilBar", targets: ["SilBar"])
    ],
    targets: [
        .executableTarget(
            name: "SilBar",
            path: "Sources/SilBar",
            linkerSettings: [
                .linkedFramework("IOKit")
            ]
        )
    ]
)
