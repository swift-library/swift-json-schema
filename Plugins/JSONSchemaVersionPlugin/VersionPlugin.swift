// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2026 Xudong Xu

import Foundation
import PackagePlugin

@main
struct VersionPlugin: BuildToolPlugin {
  func createBuildCommands(context: PluginContext, target: any Target) async throws -> [Command] {
    let root = context.package.directoryURL
    let input = root.appendingPathComponent("VERSION")
    let script = root.appendingPathComponent("Scripts/generate-version")
    let output = context.pluginWorkDirectoryURL.appendingPathComponent("PackageVersion.swift")
    return [
      .buildCommand(
        displayName: "Generate package version", executable: URL(fileURLWithPath: "/usr/bin/env"),
        arguments: ["python3", script.path, input.path, output.path], inputFiles: [input, script],
        outputFiles: [output])
    ]
  }
}
