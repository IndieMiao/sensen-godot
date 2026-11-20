// swift-tools-version:6.1
import PackageDescription
import Foundation
let localSDK = ProcessInfo.processInfo.environment["SENSEN_LIVEKIT_SWIFT_SOURCE"]
let dependency: Package.Dependency = localSDK.map { .package(name: "client-sdk-swift", path: $0) }
    ?? .package(url: "https://github.com/livekit/client-sdk-swift.git", exact: "2.19.0")
let package = Package(name: "SensenVoiceApple", platforms: [.iOS(.v15), .macOS(.v12)],
    products: [.library(name: "SensenVoiceApple", type: .dynamic, targets: ["SensenVoiceApple"])],
    dependencies: [dependency],
    targets: [.target(name: "SensenVoiceApple", dependencies: [.product(name: "LiveKit", package: "client-sdk-swift")])],
    swiftLanguageModes: [.v5])
