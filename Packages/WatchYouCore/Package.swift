// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WatchYouCore",
    platforms: [.iOS(.v18), .watchOS(.v11), .macOS(.v14)],
    products: [.library(name: "WatchYouCore", targets: ["WatchYouCore"])],
    targets: [
        .target(name: "WatchYouCore"),
        .testTarget(name: "WatchYouCoreTests", dependencies: ["WatchYouCore"]),
    ]
)
