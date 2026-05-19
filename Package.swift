// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "DonGit",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "DonGit", targets: ["DonGit"])
    ],
    targets: [
        .executableTarget(
            name: "DonGit",
            path: ".",
            exclude: [
                ".codex",
                ".git",
                "dist",
                "script"
            ],
            sources: [
                "App",
                "Models",
                "Services",
                "Stores",
                "Support",
                "Views"
            ]
        )
    ]
)
