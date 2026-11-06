// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SubDash",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "SubDash",
            path: "Sources/SubDash"
        )
    ]
)
