// swift-tools-version: 6.2
// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2026 Xudong Xu
import CompilerPluginSupport
import PackageDescription

let package = Package(
  name: "swift-json-schema", platforms: [.iOS(.v18), .macOS(.v15)],
  products: [
    .library(name: "JSONValue", targets: ["JSONValue"]),
    .library(name: "JSONSchema", targets: ["JSONSchema"]),
    .library(name: "JSONSchemaBuilder", targets: ["JSONSchemaBuilder"]),
    .library(name: "JSONSchemaConversion", targets: ["JSONSchemaConversion"]),
    .library(name: "JSONSchemaFoundationModels", targets: ["JSONSchemaFoundationModels"]),
    .executable(name: "json-schema", targets: ["JSONSchemaCLI"]),
  ],
  dependencies: [
    .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "602.0.0"),
    .package(url: "https://github.com/apple/swift-collections.git", from: "1.1.0"),
  ],
  targets: [
    .target(
      name: "JSONValue",
      dependencies: [.product(name: "OrderedCollections", package: "swift-collections")]),
    .target(name: "JSONSchema", dependencies: ["JSONValue"], resources: [.copy("Metaschemas")]),
    .macro(
      name: "JSONSchemaMacros",
      dependencies: [
        .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
        .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
        .product(name: "SwiftSyntaxBuilder", package: "swift-syntax"),
        .product(name: "SwiftDiagnostics", package: "swift-syntax"),
      ]),
    .target(name: "JSONSchemaBuilder", dependencies: ["JSONSchema", "JSONSchemaMacros"]),
    .target(name: "JSONSchemaConversion", dependencies: ["JSONSchemaBuilder"]),
    .target(name: "JSONSchemaFoundationModels", dependencies: ["JSONSchema"]),
    .executableTarget(
      name: "JSONSchemaCLI", dependencies: ["JSONSchema"], plugins: ["JSONSchemaVersionPlugin"]),
    .plugin(name: "JSONSchemaVersionPlugin", capability: .buildTool()),
    .testTarget(
      name: "JSONValueTests", dependencies: ["JSONValue"], resources: [.copy("JSONTestSuite")]),
    .testTarget(
      name: "JSONSchemaTests", dependencies: ["JSONSchema"],
      resources: [.copy("JSONSchemaTestSuite")]),
    .testTarget(name: "JSONSchemaBuilderTests", dependencies: ["JSONSchemaBuilder"]),
    .testTarget(
      name: "JSONSchemaMacroTests",
      dependencies: [
        "JSONSchemaMacros", .product(name: "SwiftParser", package: "swift-syntax"),
        .product(name: "SwiftSyntaxMacroExpansion", package: "swift-syntax"),
      ]),
    .testTarget(name: "JSONSchemaConversionTests", dependencies: ["JSONSchemaConversion"]),
    .testTarget(
      name: "JSONSchemaFoundationModelsTests", dependencies: ["JSONSchemaFoundationModels"]),
  ], swiftLanguageModes: [.v6]
)
