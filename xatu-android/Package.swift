// swift-tools-version: 6.1
// This is a Skip (https://skip.dev) package.
import PackageDescription

let package = Package(
    name: "xatu-android",
    defaultLocalization: "zh-Hans",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "XatuAndroid", type: .dynamic, targets: ["XatuAndroid"]),
    ],
    dependencies: [
        .package(url: "https://github.com/skiptools/skip.git", from: "1.9.20"),
        .package(url: "https://github.com/skiptools/skip-fuse-ui.git", from: "1.19.3"),
        .package(url: "https://github.com/skiptools/skip-keychain.git", from: "0.3.4"),
        // Includes the official fix for null request headers during Android WebView redirects.
        .package(url: "https://github.com/skiptools/skip-web.git", revision: "4ae9b16f5835d37ab63dc4cb4064df4fef3574a4"),
        .package(url: "https://github.com/krzyzanowskim/CryptoSwift.git", from: "1.9.0")
    ],
    targets: [
        .target(name: "XatuAndroid", dependencies: [
            .product(name: "SkipFuseUI", package: "skip-fuse-ui"),
            .product(name: "SkipKeychain", package: "skip-keychain"),
            .product(name: "SkipWeb", package: "skip-web"),
            .product(name: "CryptoSwift", package: "CryptoSwift")
        ], resources: [.process("Resources")], plugins: [.plugin(name: "skipstone", package: "skip")]),
    ],
    swiftLanguageModes: [.v5]
)
