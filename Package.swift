// swift-tools-version: 5.7
import PackageDescription

var products: [Product] = [.library(name: "DurlyCore", targets: ["DurlyCore"])]
var targets: [Target] = [
    .target(name: "DurlyCore"),
    .testTarget(name: "DurlyCoreTests", dependencies: ["DurlyCore"])
]
#if os(macOS)
products.append(.executable(name: "Durly", targets: ["Durly"]))
targets.append(.executableTarget(name: "Durly", dependencies: ["DurlyCore"],
    linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("AppKit")]))
#endif
let package = Package(name: "Durly", platforms: [.macOS(.v12)], products: products, targets: targets)
