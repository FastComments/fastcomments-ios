// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FastCommentsUI",
    platforms: [.iOS(.v16), .macOS(.v14)],
    products: [
        .library(name: "FastCommentsUI", targets: ["FastCommentsUI"])
    ],
    dependencies: [
        .package(url: "https://github.com/FastComments/fastcomments-swift.git", .upToNextMajor(from: "1.3.0"))
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
