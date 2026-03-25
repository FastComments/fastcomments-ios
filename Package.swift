// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FastCommentsUI",
    platforms: [.iOS(.v16), .macOS(.v14)],
    products: [
        .library(name: "FastCommentsUI", targets: ["FastCommentsUI"])
    ],
    dependencies: [
        .package(name: "fastcomments-swift", path: "../fastcomments-swift")
    ],
    targets: [
        .target(
            name: "FastCommentsUI",
            dependencies: [
                .product(name: "FastCommentsSwift", package: "fastcomments-swift")
            ],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "FastCommentsUITests",
            dependencies: ["FastCommentsUI"]
        )
    ]
)
