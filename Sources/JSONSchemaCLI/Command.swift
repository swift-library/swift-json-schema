// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2026 Xudong Xu

import Foundation
import JSONSchema
import JSONValue

#if canImport(Darwin)
  import Darwin
#else
  import Glibc
#endif

@main
struct SchemaCommand {
  static func main() async {
    do { exit(try await run(Array(CommandLine.arguments.dropFirst()))) } catch {
      FileHandle.standardError.write(Data(("json-schema: \(error)\n").utf8))
      exit(2)
    }
  }
  static func read(_ path: String) throws -> JSONValue {
    try JSONValue.parse(
      path == "-"
        ? FileHandle.standardInput.readDataToEndOfFile()
        : Data(contentsOf: URL(fileURLWithPath: path)))
  }
  static func run(_ arguments: [String]) async throws -> Int32 {
    if arguments == ["--version"] {
      print(PackageVersion.value)
      return 0
    }
    if arguments.isEmpty || arguments.contains("--help") {
      print(
        """
        Usage: json-schema validate SCHEMA INSTANCE [--output flag|basic|detailed|verbose|human]
               json-schema check SCHEMA [--output FORMAT]
               json-schema bundle SCHEMA
        Options: --draft 2020-12|2019-09|7|6|4, --registry URI=FILE (repeatable),
                 --assert-formats, --allow-host HOST (repeatable), --version
        Use '-' for stdin. Resolution is offline unless a host is allowed.
        Exit status: 0 valid/success, 1 invalid, 2 usage/schema/resolution failure.
        """)
      return 0
    }
    let command = arguments[0]
    var positional: [String] = []
    var output = "basic"
    var dialect = Dialect.draft2020
    var registry = SchemaRegistry.bundled
    var hosts = Set<String>()
    var assertFormats = false
    var i = 1
    while i < arguments.count {
      let arg = arguments[i]
      i += 1
      if arg == "--assert-formats" {
        assertFormats = true
        continue
      }
      if ["--draft", "--output", "--registry", "--allow-host"].contains(arg) {
        guard i < arguments.count else {
          throw SchemaError.invalidSchema("Missing value for \(arg)")
        }
        let value = arguments[i]
        i += 1
        switch arg {
        case "--output": output = value
        case "--allow-host": hosts.insert(value)
        case "--registry":
          let parts = value.split(separator: "=", maxSplits: 1)
          guard parts.count == 2 else {
            throw SchemaError.invalidSchema("Registry syntax is URI=FILE")
          }
          registry.register(try read(String(parts[1])), at: String(parts[0]))
        default:
          let drafts: [String: Dialect] = [
            "2020-12": .draft2020, "2019-09": .draft2019, "7": .draft7, "6": .draft6, "4": .draft4,
          ]
          guard let selected = drafts[value] else { throw SchemaError.unknownDialect(value) }
          dialect = selected
        }
      } else if arg.hasPrefix("--") {
        throw SchemaError.invalidSchema("Unknown option \(arg)")
      } else {
        positional.append(arg)
      }
    }
    let required = command == "validate" ? 2 : 1
    guard ["validate", "check", "bundle"].contains(command), positional.count == required,
      output == "human" || OutputFormat(rawValue: output) != nil
    else { throw SchemaError.invalidSchema("Invalid command arguments; use --help") }
    let document = try read(positional[0])
    let base =
      positional[0] == "-"
      ? "urn:json-schema:stdin" : URL(fileURLWithPath: positional[0]).absoluteString
    let compiler = SchemaCompiler(
      dialect: dialect, registry: registry, options: .init(assertFormats: assertFormats))
    let compiled = try await compiler.compile(
      document, baseURI: base, policy: hosts.isEmpty ? .offline : .https(hosts: hosts))
    if command == "bundle" {
      print(try compiled.bundle().serialized(.pretty))
      return 0
    }
    let result =
      command == "check" ? try compiled.checkSchema() : try compiled.validate(read(positional[1]))
    print(
      output == "human"
        ? result.humanReadable
        : try result.output(OutputFormat(rawValue: output)!).serialized(.pretty))
    return result.valid ? 0 : 1
  }
}
