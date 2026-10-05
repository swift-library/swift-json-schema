// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2026 Xudong Xu

import Foundation
import JSONSchema
import JSONValue
import Testing

@Suite struct ValidatorContracts {
  @Test func officialOutputContent() throws {
    let suite = Bundle.module.resourceURL!.appendingPathComponent(
      "JSONSchemaTestSuite/output-tests")
    var count = 0
    for draft in [Dialect.draft2019, .draft2020] {
      let directory = suite.appendingPathComponent(draft.testDirectory)
      var registry = SchemaRegistry.bundled
      registry.register(
        try JSONValue.parse(
          Data(contentsOf: directory.appendingPathComponent("output-schema.json"))),
        at: "https://json-schema.org/draft/" + (draft == .draft2020 ? "2020-12" : "2019-09")
          + "/output/schema")
      let compiler = SchemaCompiler(
        dialect: draft, registry: registry, options: .init(assertFormats: true))
      for file in try FileManager.default.contentsOfDirectory(
        at: directory.appendingPathComponent("content"), includingPropertiesForKeys: nil)
      where file.pathExtension == "json" {
        for group in try #require(JSONValue.parse(Data(contentsOf: file)).arrayValue) {
          let schema = try compiler.compile(try #require(group["schema"]))
          for test in try #require(group["tests"]?.arrayValue) {
            let result = schema.validate(try #require(test["data"]))
            for (format, expected) in try #require(test["output"]?.objectValue) {
              let output = result.output(try #require(OutputFormat(rawValue: format)))
              let validation = try compiler.compile(expected).validate(output)
              #expect(
                validation.valid,
                Comment(rawValue: file.lastPathComponent + ": " + validation.humanReadable))
              count += 1
            }
          }
        }
      }
    }
    #expect(count == 8)
    print("Official output assertions: \(count)")
  }

  @Test func allFormatsSatisfyOutputSchema() throws {
    let compiler = SchemaCompiler(options: .init(assertFormats: true))
    let outputValidator = try compiler.compile([
      "$ref": "https://json-schema.org/draft/2020-12/output/schema"
    ])
    let schema = try compiler.compile([
      "$id": "https://example.test/schema", "type": "object",
      "properties": ["name": ["type": "string", "description": "A name"]], "required": ["name"],
    ])
    for value: JSONValue in [["name": "Ada"], ["name": 2], [:]] {
      let result = schema.validate(value)
      for format in OutputFormat.allCases {
        #expect(outputValidator.validate(result.output(format)).valid)
      }
    }
    #expect(
      schema.validate(["name": 2]).errors.contains {
        $0.instanceLocation.description == "/name"
          && $0.keywordLocation.description == "/properties/name/type"
      })
  }

  @Test func resolverPolicyAndBundle() async throws {
    let root: JSONValue = ["$id": "https://example.test/root", "$ref": "number"]
    let resolver = SchemaResolver { _ in ["$id": "https://example.test/number", "type": "integer"] }
    let compiler = SchemaCompiler()
    await #expect(throws: SchemaError.self) {
      try await compiler.compile(root, policy: .offline, resolver: resolver)
    }
    let schema = try await compiler.compile(
      root, policy: .https(hosts: ["example.test"]), resolver: resolver)
    #expect(schema.validate(1).valid)
    #expect(!schema.validate(JSONValue.string("text")).valid)
    let bundle = try schema.bundle()
    #expect(try SchemaCompiler(registry: .init()).compile(bundle).validate(1).valid)
    await #expect(throws: SchemaError.self) {
      try await compiler.compile(root, policy: .https(hosts: ["other.test"]), resolver: resolver)
    }
    await #expect(throws: SchemaError.self) {
      try await compiler.compile(
        root, policy: .https(hosts: ["example.test"], maximumDocuments: 0), resolver: resolver)
    }
  }

  @Test func customVocabularyControlsActivation() throws {
    let uri = "https://example.test/vocab/even"
    var registry = SchemaRegistry.bundled
    registry.register(
      SchemaVocabulary(
        uri: uri,
        keywords: [
          SchemaKeyword("even") { parameter, value in
            KeywordResult(
              valid: parameter != true || value.numberValue?.isMultiple(of: JSONNumber(2)) == true,
              annotation: "checked parity")
          }
        ]))
    registry.register(
      [
        "$schema": .string(Dialect.draft2020.rawValue),
        "$vocabulary": ["https://json-schema.org/draft/2020-12/vocab/core": true, uri: true],
      ], at: "https://example.test/meta")
    let validator = try SchemaCompiler(registry: registry).compile([
      "$schema": "https://example.test/meta", "even": true, "type": "string",
    ])
    #expect(validator.validate(2).valid)
    #expect(!validator.validate(3).valid)
    #expect(validator.validate(2).annotations.contains { $0.annotation == "checked parity" })
    #expect(throws: SchemaError.self) { try SchemaCompiler().compile(["$vocabulary": [uri: true]]) }
  }

  @Test func contentIsAnnotatedAndExplicitlyEvaluated() throws {
    let definition: JSONValue = [
      "contentEncoding": "base64", "contentMediaType": "application/json",
      "contentSchema": ["type": "integer"],
    ]
    #expect(try SchemaCompiler().compile(definition).validate(JSONValue.string("e30=")).valid)
    let validator = try SchemaCompiler(options: .init(evaluateContent: true)).compile(definition)
    #expect(validator.validate(JSONValue.string("MQ==")).valid)
    #expect(!validator.validate(JSONValue.string("e30=")).valid)
    #expect(!validator.validate(JSONValue.string("%invalid")).valid)
  }

  @Test func bundleContainsEachDocumentOnceAndResolvesAliases() throws {
    var registry = SchemaRegistry.bundled
    registry.register(
      [
        "$id": "https://example.test/canonical",
        "$defs": ["child": ["$id": "child", "type": "integer"]], "$ref": "child",
      ], at: "https://example.test/retrieval")
    let validator = try SchemaCompiler(registry: registry).compile([
      "$id": "https://example.test/root", "$ref": "retrieval",
    ])
    let bundle = try validator.bundle()
    #expect(bundle["$defs"]?.objectValue?.count == 1)
    let offline = try SchemaCompiler(registry: .init()).compile(bundle)
    #expect(offline.validate(2).valid)
    #expect(!offline.validate(JSONValue.string("wrong")).valid)
  }

  @Test func propertyNamesRetainUnicodeIdentity() throws {
    let validator = try SchemaCompiler().compile([
      "properties": ["é": ["type": "integer"], "e\u{301}": ["type": "string"]],
      "required": ["é", "e\u{301}"],
    ])
    #expect(validator.validate(["é": 1, "e\u{301}": "text"]).valid)
    #expect(!validator.validate(["é": "text", "e\u{301}": 1]).valid)
  }

  @Test func concurrentReuseDoesNotShareAnnotations() async throws {
    let validator = try SchemaCompiler().compile([
      "anyOf": [
        ["properties": ["left": true], "required": ["left"]],
        ["properties": ["right": true], "required": ["right"]],
      ], "unevaluatedProperties": false,
    ])
    await withTaskGroup(of: Bool.self) { group in
      for i in 0..<100 {
        group.addTask { validator.validate(i % 2 == 0 ? ["left": 1] : ["right": 2]).valid }
      }
      for await valid in group { #expect(valid) }
    }
    #expect(!validator.validate(["left": 1, "extra": 2]).valid)
  }

  @Test func annotationsRetainKeywordLocationsAndSuccessfulBranches() throws {
    let validator = try SchemaCompiler().compile([
      "$id": "https://example.test/annotations", "é": 1, "e\u{301}": 2,
      "anyOf": [
        ["type": "integer", "description": "an integer"],
        ["type": "string", "description": "a string"],
      ],
    ])
    let result = validator.validate(1)
    #expect(result.valid)
    #expect(result.annotations.contains { $0.annotation == "an integer" })
    #expect(!result.annotations.contains { $0.annotation == "a string" })
    let first = try #require(result.annotations.first { $0.annotation == 1 })
    let second = try #require(result.annotations.first { $0.annotation == 2 })
    #expect(first.absoluteKeywordLocation != second.absoluteKeywordLocation)
    #expect(
      Array(first.keywordLocation.tokens.last!.utf8)
        != Array(second.keywordLocation.tokens.last!.utf8))
  }

  @Test func dialectAndVocabularySelectCompilationBehavior() throws {
    let legacy: JSONValue = [
      "$schema": .string(Dialect.draft7.rawValue), "$ref": "#/definitions/value", "pattern": "[",
      "definitions": ["value": ["type": "integer"]],
    ]
    #expect(try SchemaCompiler().compile(legacy).validate(1).valid)
    var registry = SchemaRegistry.bundled
    registry.register(
      [
        "$schema": .string(Dialect.draft2020.rawValue),
        "$vocabulary": ["https://json-schema.org/draft/2020-12/vocab/core": true],
      ], at: "https://example.test/core-meta")
    let validator = try SchemaCompiler(registry: registry).compile([
      "$schema": "https://example.test/core-meta", "pattern": "[", "properties": ["x": 42],
    ])
    let result = validator.validate(["x": "text"])
    #expect(result.valid)
    #expect(result.annotations.contains { $0.annotation == "[" })
  }

  @Test func deeplyNestedCompilationAndEvaluationLimits() throws {
    var definition: JSONValue = ["type": "integer", "title": "leaf"]
    for _ in 0..<100 { definition = ["allOf": .array([definition])] }
    let compiler = SchemaCompiler(options: .init(maximumDepth: 8))
    let validator = try compiler.compile(definition)
    #expect(!validator.validate(1).valid)
    let result = try SchemaCompiler().compile(definition).validate(1)
    #expect(result.valid)
    #expect(result.annotations.contains { $0.annotation == "leaf" })
    for format in OutputFormat.allCases { #expect(try !result.output(format).serialized().isEmpty) }
  }

  @Test func unicodeRegexSemantics() throws {
    #expect(try ECMARegularExpression(#"^(?<word>\w+)\s\k<word>$"#).matches("abc abc"))
    #expect(try !ECMARegularExpression(#"^\d+$"#).matches("١٢"))
    #expect(try ECMARegularExpression(#"(?<=a+)b"#).matches("aaab"))
    #expect(try !ECMARegularExpression("^abc$").matches("abc\n"))
    #expect(try ECMARegularExpression(#"^\p{Letter}+$"#).matches("文字"))
    #expect(try ECMARegularExpression(#"^(?:(a)|(b))*\1$"#).matches("ab"))
    #expect(try !ECMARegularExpression(#"^(?=(a+))a*b\1$"#).matches("aaaba"))
    #expect(try ECMARegularExpression(#"^(?=(a+))a*b\1$"#).matches("aaabaaa"))
    #expect(try ECMARegularExpression(#"(?<=([ab]+)([bc]+))\1$"#).matches("abca"))
    #expect(try ECMARegularExpression(#"^\1(a)$"#).matches("a"))
    #expect(try ECMARegularExpression(#"^(?<\u0061>x)\k<a>$"#).matches("xx"))
    for invalid in [#"\1"#, #"\k<missing>"#, #"(?<1x>a)"#, #"a}"#, #"\01"#, #"[\B]"#] {
      #expect(throws: SchemaError.self) { try ECMARegularExpression(invalid) }
    }
  }
}
