// swift-tools-version: 6.0

import PackageDescription

var products: [Product] = [
    .library(name: "StrengthTrackerShared", targets: ["StrengthTrackerShared"]),
]

var targets: [Target] = [
    // Shared module with DDD architecture:
    // - Models/Domain: Domain models (Exercise, Workout, etc.)
    // - Repositories/Protocols: Repository interfaces
    // - Persistence/SwiftData/Entities: SwiftData @Model entities
    // - Persistence/SwiftData/Repositories: SwiftData repository implementations
    // - Persistence/Mappers: Domain ↔ Entity mappers
    // - DI: Dependency injection container
    // - Services: Domain services and business logic
    // - ViewModels: Presentation layer view models
    .target(
        name: "StrengthTrackerShared",
        path: "Shared"
    ),
    .testTarget(
        name: "StrengthTrackerTests",
        dependencies: ["StrengthTrackerShared"],
        path: "Tests"
    ),
]

#if !os(Linux)
products.append(contentsOf: [
    .library(name: "StrengthTrackeriOS", targets: ["StrengthTrackeriOS"]),
    .library(name: "StrengthTrackerWatch", targets: ["StrengthTrackerWatch"]),
])

targets.append(contentsOf: [
    .target(
        name: "StrengthTrackeriOS",
        dependencies: ["StrengthTrackerShared"],
        path: "iOS"
    ),
    .target(
        name: "StrengthTrackerWatch",
        dependencies: ["StrengthTrackerShared"],
        path: "WatchApp"
    ),
])
#endif

let package = Package(
    name: "StrengthTracker",
    platforms: [
        .iOS(.v17),
        .watchOS(.v10),
        .macOS(.v14)
    ],
    products: products,
    targets: targets
)
