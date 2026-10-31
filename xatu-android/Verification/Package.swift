// swift-tools-version: 6.1
import PackageDescription
let package = Package(
    name: "XatuPortabilityChecks",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "SessionProbe", targets: ["SessionProbe"])],
    dependencies: [.package(url: "https://github.com/krzyzanowskim/CryptoSwift.git", exact: "1.10.0")],
    targets: [.executableTarget(name: "SessionProbe", dependencies: [.product(name: "CryptoSwift", package: "CryptoSwift")]), .testTarget(name: "PortabilityTests", dependencies: [.product(name: "CryptoSwift", package: "CryptoSwift")])],
    swiftLanguageModes: [.v5]
)
