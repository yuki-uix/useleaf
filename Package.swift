// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "WordShelf",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "WordShelf", targets: ["WordShelf"]),
        .library(name: "WordShelfCore", targets: ["WordShelfCore"])
    ],
    targets: [
        .systemLibrary(name: "CSQLite"),
        .target(name: "WordShelfCore", dependencies: ["CSQLite"], resources: [.copy("Resources")]),
        .executableTarget(name: "WordShelf", dependencies: ["WordShelfCore"]),
        .testTarget(name: "WordShelfCoreTests", dependencies: ["WordShelfCore"]),
        .testTarget(name: "WordShelfTests", dependencies: ["WordShelf", "WordShelfCore"])
    ],
    swiftLanguageModes: [.v5]
)
