// swift-tools-version:5.9
// 規則引擎：排行程、花費、提醒、喜好。只用 Foundation，所以 Linux 上也能跑測試。
// app 那邊不是把它當套件引用，而是把 Sources/RadishCore 直接編進 app（見 ios/project.yml），
// 這份 Package.swift 只給 `swift test` 用。
import PackageDescription

let package = Package(
    name: "RadishCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "RadishCore", targets: ["RadishCore"])],
    targets: [
        .target(
            name: "RadishCore",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "RadishCoreTests",
            dependencies: ["RadishCore"]
        ),
    ],
    swiftLanguageVersions: [.v5]
)
