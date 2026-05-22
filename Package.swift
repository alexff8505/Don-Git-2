// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "DonGit",
    platforms: [
        .macOS(.v26)
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
                "AGENTS.md",
                "Assets",
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
