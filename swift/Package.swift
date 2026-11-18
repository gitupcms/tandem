// swift-tools-version:5.9
import CompilerPluginSupport
import PackageDescription

let package = Package(
    name: "TandemKit",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "TandemKit", targets: ["TandemKit"]),
        // Macros that generate state JSON, input schemas and input decoding. swift-syntax is a build-time dependency only.
        .library(name: "TandemIntrospection", targets: ["TandemIntrospection"]),
        .executable(name: "TandemProbe", targets: ["TandemProbe"]),
    ],
    dependencies: [.package(url: "https://github.com/swiftlang/swift-syntax.git", "601.0.0"..<"700.0.0")],
    targets: [
        .target(name: "TandemKit"),
        .macro(name: "TandemMacros", dependencies: [
            .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
            .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
        ]),
        .target(name: "TandemIntrospection", dependencies: ["TandemKit", "TandemMacros"]),
        .executableTarget(name: "TandemProbe", dependencies: ["TandemKit"]),
        .testTarget(name: "TandemKitTests", dependencies: ["TandemKit"]),
        .testTarget(name: "TandemMacrosTests", dependencies: [
            "TandemIntrospection", "TandemMacros",
            .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax"),
        ]),
    ]
)
