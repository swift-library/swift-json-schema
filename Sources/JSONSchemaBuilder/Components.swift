// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2026 Xudong Xu

import JSONSchema
import JSONValue

/// Failures from schema validation or typed extraction after validation.
public enum SchemaDecodingError: Error, Sendable {
  /// The instance failed schema validation; the associated value preserves the complete result.
  case invalid(ValidationResult)
  /// The valid JSON value could not be represented by the requested Swift type.
  case extraction(String)
}

/// A schema document paired with a Swift extraction function.
public struct SchemaComponent<Output>: Sendable {
  /// The schema document used for compilation and validation.
  public let schema: JSONValue
  private let extract: @Sendable (JSONValue) throws -> Output
  /// Pairs a schema with a sendable extractor. Decoding compiles and validates before invoking it.
  public init(schema: JSONValue, extract: @escaping @Sendable (JSONValue) throws -> Output) {
    self.schema = schema
    self.extract = extract
  }
  /// Compiles this component's schema with the supplied compiler, or its default configuration.
  public func compile(using compiler: SchemaCompiler = .init()) throws -> CompiledSchema {
    try compiler.compile(schema)
  }
  /// Compiles and validates the value, then runs its typed extractor.
  /// Throws `invalid` with the validation result or propagates compilation and extraction errors.
  public func decode(from value: JSONValue, using compiler: SchemaCompiler = .init()) throws
    -> Output
  {
    let result = try compile(using: compiler).validate(value)
    guard result.valid else { throw SchemaDecodingError.invalid(result) }
    return try extract(value)
  }
  /// Parses JSON text using default parser limits before validation and typed extraction.
  public func decode(from text: String, using compiler: SchemaCompiler = .init()) throws -> Output {
    try decode(from: JSONValue.parse(text), using: compiler)
  }
  /// Validates against this component's schema and decodes the requested Codable type.
  /// Uses `JSONValueDecoder` with its default key strategy; this overload does not invoke the component extractor.
  public func decode<T: Decodable>(
    _ type: T.Type, from value: JSONValue, using compiler: SchemaCompiler = .init()
  ) throws -> T {
    let result = try compile(using: compiler).validate(value)
    guard result.valid else { throw SchemaDecodingError.invalid(result) }
    return try JSONValueDecoder().decode(type, from: value)
  }
  /// Composes a throwing transform after typed extraction while preserving the schema.
  public func map<T>(_ transform: @escaping @Sendable (Output) throws -> T) -> SchemaComponent<T> {
    SchemaComponent<T>(schema: schema) { try transform(extract($0)) }
  }
  /// Returns a component with a keyword replaced or added, retaining the extractor.
  /// A boolean schema is first wrapped in `allOf`; keyword values are not validated here.
  public func keyword(_ name: String, _ value: JSONValue) -> Self {
    var definition = schema
    if definition.objectValue == nil { definition = ["allOf": .array([definition])] }
    definition[name] = value
    return Self(schema: definition, extract: extract)
  }
  /// Adds a descriptive annotation without changing typed extraction.
  public func description(_ text: String) -> Self { keyword("description", .string(text)) }
  /// Adds a title annotation without changing typed extraction.
  public func title(_ text: String) -> Self { keyword("title", .string(text)) }
  /// Declares a format; assertion depends on the compiler's validation options.
  public func format(_ name: String) -> Self { keyword("format", .string(name)) }
  /// Adds an exact inclusive numeric lower bound.
  public func minimum(_ value: JSONNumber) -> Self { keyword("minimum", .number(value)) }
  /// Adds an exact inclusive numeric upper bound.
  public func maximum(_ value: JSONNumber) -> Self { keyword("maximum", .number(value)) }
  /// Adds an inclusive lower bound using the integer's exact decimal value.
  public func minimum(_ value: Int) -> Self { minimum(JSONNumber(value)) }
  /// Adds an inclusive upper bound using the integer's exact decimal value.
  public func maximum(_ value: Int) -> Self { maximum(JSONNumber(value)) }
  /// Adds a minimum Unicode code-point count for string instances.
  public func minLength(_ value: Int) -> Self { keyword("minLength", .number(JSONNumber(value))) }
  /// Adds a maximum Unicode code-point count for string instances.
  public func maxLength(_ value: Int) -> Self { keyword("maxLength", .number(JSONNumber(value))) }
  /// Adds an unanchored ECMA-262 pattern; invalid expressions fail during compilation.
  public func pattern(_ expression: String) -> Self { keyword("pattern", .string(expression)) }
  /// Adds a minimum array element count.
  public func minItems(_ count: Int) -> Self { keyword("minItems", .number(JSONNumber(count))) }
  /// Adds a maximum array element count.
  public func maxItems(_ count: Int) -> Self { keyword("maxItems", .number(JSONNumber(count))) }
  /// Restricts values to the supplied JSON alternatives using JSON value equality.
  public func enumerated(_ values: [JSONValue]) -> Self { keyword("enum", .array(values)) }
  /// Adds a default annotation; decoding does not insert missing values.
  public func defaultValue(_ value: JSONValue) -> Self { keyword("default", value) }
  /// Marks the schema with a deprecation annotation, defaulting to `true`.
  public func deprecated(_ yes: Bool = true) -> Self { keyword("deprecated", .bool(yes)) }
  /// Sets the schema for object properties not matched by declared property schemas.
  public func additionalProperties(_ schema: JSONValue) -> Self {
    keyword("additionalProperties", schema)
  }
  /// Accepts JSON null as `nil` and applies the original extractor to non-null values.
  public func nullable() -> SchemaComponent<Output?> {
    SchemaComponent<Output?>(schema: ["anyOf": .array([schema, ["type": "null"]])]) { value in
      value == .null ? nil : try extract(value)
    }
  }
  /// Validates an array of this schema and extracts each element in order.
  public func array() -> SchemaComponent<[Output]> {
    SchemaComponent<[Output]>(schema: ["type": "array", "items": schema]) { value in
      guard let list = value.arrayValue else {
        throw SchemaDecodingError.extraction("Expected array")
      }
      return try list.map(extract)
    }
  }
}

/// An object-property schema and its requiredness in a builder declaration.
public struct SchemaProperty: Sendable {
  /// The JSON object key emitted into the properties map.
  public let name: String
  /// The subschema applied to this property's JSON value.
  public let schema: JSONValue
  /// Whether the generated object requires this key; defaults to `true`.
  public let required: Bool
  /// Captures a component's schema for a named property; the object builder does not run its extractor.
  public init<T>(_ name: String, _ component: SchemaComponent<T>, required: Bool = true) {
    self.name = name
    schema = component.schema
    self.required = required
  }
}

/// Collects object-property declarations, preserving source order across control-flow branches.
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

/// Collects schema documents for composition, discarding typed component extractors.
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
  /// Accepts any JSON value and returns it unchanged.
  public static func any() -> SchemaComponent<JSONValue> {
    .init(schema: .bool(true), extract: { $0 })
  }
  /// Requires a JSON string and extracts its Swift string value.
  public static func string() -> SchemaComponent<String> {
    .init(schema: ["type": "string"]) { value in
      guard let text = value.stringValue else {
        throw SchemaDecodingError.extraction("Expected string")
      }
      return text
    }
  }
  /// Requires a mathematical integer and extracts `Int`; values outside its range throw.
  public static func integer() -> SchemaComponent<Int> {
    .init(schema: ["type": "integer"]) { value in
      guard let number = value.numberValue?.intValue else {
        throw SchemaDecodingError.extraction("Integer exceeds Int range")
      }
      return number
    }
  }
  /// Requires a JSON number and preserves its exact number representation.
  public static func number() -> SchemaComponent<JSONNumber> {
    .init(schema: ["type": "number"]) { value in
      guard let number = value.numberValue else {
        throw SchemaDecodingError.extraction("Expected number")
      }
      return number
    }
  }
  /// Requires a JSON boolean and extracts its Swift value.
  public static func boolean() -> SchemaComponent<Bool> {
    .init(schema: ["type": "boolean"]) { value in
      guard let flag = value.boolValue else {
        throw SchemaDecodingError.extraction("Expected boolean")
      }
      return flag
    }
  }
  /// Builds an object schema from named properties and returns the validated ordered object.
  /// Additional properties are accepted unless explicitly constrained.
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
  /// Builds a `$ref` schema and returns validated JSON unchanged; compilation must resolve the URI.
  public static func reference(_ uri: String) -> SchemaComponent<JSONValue> {
    .init(schema: ["$ref": .string(uri)], extract: { $0 })
  }
  /// Requires every supplied schema and returns the validated JSON unchanged.
  public static func allOf(@SchemaListBuilder _ body: () -> [JSONValue]) -> SchemaComponent<
    JSONValue
  > { .init(schema: ["allOf": .array(body())], extract: { $0 }) }
  /// Requires at least one supplied schema and returns the validated JSON unchanged.
  public static func anyOf(@SchemaListBuilder _ body: () -> [JSONValue]) -> SchemaComponent<
    JSONValue
  > { .init(schema: ["anyOf": .array(body())], extract: { $0 }) }
  /// Requires exactly one supplied schema and returns the validated JSON unchanged.
  public static func oneOf(@SchemaListBuilder _ body: () -> [JSONValue]) -> SchemaComponent<
    JSONValue
  > { .init(schema: ["oneOf": .array(body())], extract: { $0 }) }
}
