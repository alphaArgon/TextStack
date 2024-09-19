// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let settings = [
    .define("USE_TEXT_BITMAP_CACHE")  //  Enabling bitmap caching might be slower.
] as [SwiftSetting]


let package = Package(
    name: "TextStack",

    products: [
        .library(name: "TextStack", targets: ["TextStack"]),
    ],

    targets: [
        .target(name: "TextStack", swiftSettings: settings),
        .testTarget(name: "TextStackTests", dependencies: ["TextStack"], swiftSettings: settings),
    ]
)
