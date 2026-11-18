// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Inventory",
    platforms: [.macOS(.v13)],
    // tandem-kit is a symlink to ../../../swift: a path dependency takes its identity from the last path
    // component, and "swift" would collide with this package's own directory name (cyclic dependency error).
    dependencies: [.package(path: "tandem-kit")],
    targets: [
        .target(name: "InventoryCore"),
        .executableTarget(name: "InventoryCLI", dependencies: ["InventoryCore", .product(name: "TandemKit", package: "tandem-kit")]),
        .testTarget(name: "InventoryCoreTests", dependencies: ["InventoryCore"]),
    ]
)
