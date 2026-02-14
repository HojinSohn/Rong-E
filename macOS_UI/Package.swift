// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Rong-E",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "Rong-E",
            path: "Rong-E", // Points to your inner source folder
            exclude: [
                "Info.plist",
                "Rong-E.entitlements",
                "Assets.xcassets",
                "Rong-E-Icon.png"
            ]
        )
    ]
)