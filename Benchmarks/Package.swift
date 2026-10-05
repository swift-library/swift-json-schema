// swift-tools-version: 6.2
// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2026 Xudong Xu

import PackageDescription

let package = Package(
  name: "SchemaBenchmarks",
  platforms: [.macOS(.v15)],
  dependencies: [
    .package(path: ".."),
    .package(
      url: "https://github.com/swift-library/swift-benchmark.git", .upToNextMinor(from: "0.1.2")),
  ],
  targets: [
    .executableTarget(
      name: "SchemaBenchmarks",
      dependencies: [
        .product(name: "JSONSchema", package: "swift-json-schema"),
        .product(name: "Benchmark", package: "swift-benchmark"),
      ])
  ]
)
