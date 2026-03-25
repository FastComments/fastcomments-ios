// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FastCommentsUI",
    platforms: [.iOS(.v16)],
    products: [
        .library(name: "FastCommentsUI", targets: ["FastCommentsUI"])
    ],
    dependencies: [
        .package(url: "git@github.com:FastComments/fastcomments-swift.git", from: "1.2.1")
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
