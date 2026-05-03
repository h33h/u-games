// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "UGames",
    platforms: [.iOS(.v15)],
    products: [
        .library(name: "UGames", targets: ["UGames"]),
    ],
    targets: [
        .target(
            name: "UGames",
            path: "UGames",
            exclude: ["Info.plist"],
            resources: [
                .copy("Resources/honest-path.js"),
                .copy("Resources/ya-sdk-stub.js"),
                .copy("Resources/pwa-mode.css"),
                .copy("Resources/pwa-mode.js"),
                .copy("Resources/ad-domains.txt"),
            ]
        ),
    ]
)
