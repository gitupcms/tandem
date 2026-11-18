// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TandemKit",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "TandemKit", targets: ["TandemKit"]),
        .executable(name: "TandemProbe", targets: ["TandemProbe"]),
    ],
    targets: [
        .target(name: "TandemKit"),
        .executableTarget(name: "TandemProbe", dependencies: ["TandemKit"]),
        .testTarget(name: "TandemKitTests", dependencies: ["TandemKit"]),
    ]
)
