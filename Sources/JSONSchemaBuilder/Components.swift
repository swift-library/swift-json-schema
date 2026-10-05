// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2026 Xudong Xu

import JSONSchema
import JSONValue

public enum SchemaDecodingError: Error, Sendable {
  case invalid(ValidationResult)
  case extraction(String)
}

/// A schema document paired with a Swift extraction function.
public struct SchemaComponent<Output>: Sendable {
  public let schema: JSONValue
  private let extract: @Sendable (JSONValue) throws -> Output
  public init(schema: JSONValue, extract: @escaping @Sendable (JSONValue) throws -> Output) {
    self.schema = schema
    self.extract = extract
  }
  public func compile(using compiler: SchemaCompiler = .init()) throws -> CompiledSchema {
    try compiler.compile(schema)
  }
  public func decode(from value: JSONValue, using compiler: SchemaCompiler = .init()) throws
    -> Output
  {
    let result = try compile(using: compiler).validate(value)
    guard result.valid else { throw SchemaDecodingError.invalid(result) }
    return try extract(value)
  }
  public func decode(from text: String, using compiler: SchemaCompiler = .init()) throws -> Output {
    try decode(from: JSONValue.parse(text), using: compiler)
  }
  public func decode<T: Decodable>(
    _ type: T.Type, from value: JSONValue, using compiler: SchemaCompiler = .init()
  ) throws -> T {
    let result = try compile(using: compiler).validate(value)
    guard result.valid else { throw SchemaDecodingError.invalid(result) }
    return try JSONValueDecoder().decode(type, from: value)
  }
  public func map<T>(_ transform: @escaping @Sendable (Output) throws -> T) -> SchemaComponent<T> {
    SchemaComponent<T>(schema: schema) { try transform(extract($0)) }
  }
  public func keyword(_ name: String, _ value: JSONValue) -> Self {
    var definition = schema
    if definition.objectValue == nil { definition = ["allOf": .array([definition])] }
    definition[name] = value
    return Self(schema: definition, extract: extract)
  }
  public func description(_ text: String) -> Self { keyword("description", .string(text)) }
  public func title(_ text: String) -> Self { keyword("title", .string(text)) }
  public func format(_ name: String) -> Self { keyword("format", .string(name)) }
  public func minimum(_ value: JSONNumber) -> Self { keyword("minimum", .number(value)) }
  public func maximum(_ value: JSONNumber) -> Self { keyword("maximum", .number(value)) }
  public func minimum(_ value: Int) -> Self { minimum(JSONNumber(value)) }
  public func maximum(_ value: Int) -> Self { maximum(JSONNumber(value)) }
  public func minLength(_ value: Int) -> Self { keyword("minLength", .number(JSONNumber(value))) }
  public func maxLength(_ value: Int) -> Self { keyword("maxLength", .number(JSONNumber(value))) }
  public func pattern(_ expression: String) -> Self { keyword("pattern", .string(expression)) }
  public func minItems(_ count: Int) -> Self { keyword("minItems", .number(JSONNumber(count))) }
  public func maxItems(_ count: Int) -> Self { keyword("maxItems", .number(JSONNumber(count))) }
  public func enumerated(_ values: [JSONValue]) -> Self { keyword("enum", .array(values)) }
  public func defaultValue(_ value: JSONValue) -> Self { keyword("default", value) }
  public func deprecated(_ yes: Bool = true) -> Self { keyword("deprecated", .bool(yes)) }
  public func additionalProperties(_ schema: JSONValue) -> Self {
    keyword("additionalProperties", schema)
  }
  public func nullable() -> SchemaComponent<Output?> {
    SchemaComponent<Output?>(schema: ["anyOf": .array([schema, ["type": "null"]])]) { value in
      value == .null ? nil : try extract(value)
    }
  }
  public func array() -> SchemaComponent<[Output]> {
    SchemaComponent<[Output]>(schema: ["type": "array", "items": schema]) { value in
      guard let list = value.arrayValue else {
        throw SchemaDecodingError.extraction("Expected array")
      }
      return try list.map(extract)
    }
  }
}

public struct SchemaProperty: Sendable {
  public let name: String
  public let schema: JSONValue
  public let required: Bool
  public init<T>(_ name: String, _ component: SchemaComponent<T>, required: Bool = true) {
    self.name = name
    schema = component.schema
    self.required = required
  }
}

@resultBuilder public enum PropertyBuilder {
  public static func buildExpression(_ property: SchemaProperty) -> [SchemaProperty] { [property] }
  public static func buildBlock(_ lists: [SchemaProperty]...) -> [SchemaProperty] {
    lists.flatMap { $0 }
  }
  public static func buildOptional(_ list: [SchemaProperty]?) -> [SchemaProperty] { list ?? [] }
  public static func buildEither(first: [SchemaProperty]) -> [SchemaProperty] { first }
  public static func buildEither(second: [SchemaProperty]) -> [SchemaProperty] { second }
  public static func buildArray(_ lists: [[SchemaProperty]]) -> [SchemaProperty] {
    lists.flatMap { $0 }
  }
  public static func buildLimitedAvailability(_ list: [SchemaProperty]) -> [SchemaProperty] { list }
}

@resultBuilder public enum SchemaListBuilder {
  public static func buildExpression<T>(_ component: SchemaComponent<T>) -> [JSONValue] {
    [component.schema]
  }
  public static func buildExpression(_ schema: JSONValue) -> [JSONValue] { [schema] }
  public static func buildBlock(_ lists: [JSONValue]...) -> [JSONValue] { lists.flatMap { $0 } }
  public static func buildOptional(_ list: [JSONValue]?) -> [JSONValue] { list ?? [] }
  public static func buildEither(first: [JSONValue]) -> [JSONValue] { first }
  public static func buildEither(second: [JSONValue]) -> [JSONValue] { second }
  public static func buildArray(_ lists: [[JSONValue]]) -> [JSONValue] { lists.flatMap { $0 } }
}

/// Constructors emit draft 2020-12 schemas.
public enum Schema {
  public static func any() -> SchemaComponent<JSONValue> {
    .init(schema: .bool(true), extract: { $0 })
  }
  public static func string() -> SchemaComponent<String> {
    .init(schema: ["type": "string"]) { value in
      guard let text = value.stringValue else {
        throw SchemaDecodingError.extraction("Expected string")
      }
      return text
    }
  }
  public static func integer() -> SchemaComponent<Int> {
    .init(schema: ["type": "integer"]) { value in
      guard let number = value.numberValue?.intValue else {
        throw SchemaDecodingError.extraction("Integer exceeds Int range")
      }
      return number
    }
  }
  public static func number() -> SchemaComponent<JSONNumber> {
    .init(schema: ["type": "number"]) { value in
      guard let number = value.numberValue else {
        throw SchemaDecodingError.extraction("Expected number")
      }
      return number
    }
  }
  public static func boolean() -> SchemaComponent<Bool> {
    .init(schema: ["type": "boolean"]) { value in
      guard let flag = value.boolValue else {
        throw SchemaDecodingError.extraction("Expected boolean")
      }
      return flag
    }
  }
  public static func object(@PropertyBuilder _ properties: () -> [SchemaProperty])
    -> SchemaComponent<JSONObject>
  {
    let entries = properties()
    let members = JSONObject(entries.map { ($0.name, $0.schema) })
    let required = entries.filter(\.required).map { JSONValue.string($0.name) }
    return .init(schema: [
      "type": "object", "properties": .object(members), "required": .array(required),
    ]) { value in
      guard let object = value.objectValue else {
        throw SchemaDecodingError.extraction("Expected object")
      }
      return object
    }
  }
  public static func reference(_ uri: String) -> SchemaComponent<JSONValue> {
    .init(schema: ["$ref": .string(uri)], extract: { $0 })
  }
  public static func allOf(@SchemaListBuilder _ body: () -> [JSONValue]) -> SchemaComponent<
    JSONValue
  > { .init(schema: ["allOf": .array(body())], extract: { $0 }) }
  public static func anyOf(@SchemaListBuilder _ body: () -> [JSONValue]) -> SchemaComponent<
    JSONValue
  > { .init(schema: ["anyOf": .array(body())], extract: { $0 }) }
  public static func oneOf(@SchemaListBuilder _ body: () -> [JSONValue]) -> SchemaComponent<
    JSONValue
  > { .init(schema: ["oneOf": .array(body())], extract: { $0 }) }
}
