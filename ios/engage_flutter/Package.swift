// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "engage_flutter",
    platforms: [
        .iOS("15.0")
    ],
    products: [
        .library(name: "engage-flutter", targets: ["engage_flutter"])
    ],
    dependencies: [
        .package(path: "../../../../ios")
    ],
    targets: [
        .target(
            name: "engage_flutter",
            dependencies: [
                .product(name: "EngageSDK", package: "ios")
            ]
        )
    ]
)
