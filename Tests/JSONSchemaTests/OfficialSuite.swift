// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2026 Xudong Xu

import Foundation
import JSONSchema
import JSONValue
import Testing

private let suiteURL = Bundle.module.resourceURL!.appendingPathComponent("JSONSchemaTestSuite")

private func registry() throws -> SchemaRegistry {
  var result = SchemaRegistry.bundled
  let remotes = suiteURL.appendingPathComponent("remotes")
  let files = FileManager.default.enumerator(at: remotes, includingPropertiesForKeys: nil)!
  for case let file as URL in files where file.pathExtension == "json" {
    let relative = String(file.path.dropFirst(remotes.path.count + 1))
    result.register(
      try JSONValue.parse(Data(contentsOf: file)), at: "http://localhost:1234/" + relative)
  }
  return result
}

private func exercise(_ dialect: Dialect, category: String) throws {
  let root = suiteURL.appendingPathComponent("tests/" + dialect.testDirectory)
  let directory =
    category == "required"
    ? root : root.appendingPathComponent(category == "format" ? "optional/format" : "optional")
  let files = try FileManager.default.contentsOfDirectory(
    at: directory, includingPropertiesForKeys: nil
  ).filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
  #expect(!files.isEmpty, "Official suite directory must contain fixtures")
  let compiler = SchemaCompiler(
    dialect: dialect, registry: try registry(),
    options: .init(assertFormats: category == "format", evaluateContent: category == "optional"))
  var total = 0
  var passed = 0
  var failures: [String] = []
  for file in files {
    let groups = try #require(JSONValue.parse(Data(contentsOf: file)).arrayValue)
    for group in groups {
      let tests = try #require(group["tests"]?.arrayValue)
      total += tests.count
      let groupDescription = group["description"]?.stringValue ?? ""
      do {
        let schema = try compiler.compile(try #require(group["schema"]))
        for test in tests {
          guard let expected = test["valid"]?.boolValue else {
            throw SchemaError.invalidSchema("Fixture requires a boolean result")
          }
          let actual = schema.validate(try #require(test["data"]))
          if actual.valid == expected {
            passed += 1
          } else {
            let testDescription = test["description"]?.stringValue ?? ""
            let message =
              "\(file.lastPathComponent): \(groupDescription) / \(testDescription) expected \(expected); \(actual.humanReadable)"
            failures.append(message)
            if category == "required" { Issue.record(Comment(rawValue: message)) }
          }
        }
      } catch {
        let message = "\(file.lastPathComponent): \(groupDescription) / compile: \(error)"
        failures.append(message)
        if category == "required" { Issue.record(Comment(rawValue: message)) }
      }
    }
  }
  let report: JSONValue = [
    "draft": .string(dialect.testDirectory), "category": .string(category),
    "total": .number(JSONNumber(total)), "passed": .number(JSONNumber(passed)),
    "failures": .array(failures.map(JSONValue.string)),
  ]
  let output = URL(
    fileURLWithPath: ProcessInfo.processInfo.environment["JSON_SCHEMA_REPORT_DIR"]
      ?? ".build/compliance", isDirectory: true)
  try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
  try report.serializedData(.pretty).write(
    to: output.appendingPathComponent(category + "-" + dialect.testDirectory + ".json"),
    options: .atomic)
  print(
    "\(dialect.testDirectory) \(category): \(passed)/\(total) (\(total == 0 ? 0 : Double(passed) * 100 / Double(total))%)"
  )
}

@Suite("Official JSON Schema conformance")
struct OfficialSuite {
  @Test(arguments: Dialect.allCases)
  func required(draft: Dialect) throws { try exercise(draft, category: "required") }
  @Test(arguments: Dialect.allCases)
  func formats(draft: Dialect) throws { try exercise(draft, category: "format") }
  @Test(arguments: Dialect.allCases)
  func optional(draft: Dialect) throws { try exercise(draft, category: "optional") }
}
