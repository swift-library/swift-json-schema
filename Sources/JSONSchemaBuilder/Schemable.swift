// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2026 Xudong Xu

import JSONSchema
import JSONValue

/// Provides a reusable schema definition that a context can reference recursively.
public protocol Schemable {
  /// The key transformation applied throughout the generated schema and typed decoding.
  static var schemaKeyStrategy: JSONKeyStrategy { get }
  /// Builds this type's schema, registering nested types through the supplied context.
  static func schemaDefinition(in context: inout SchemaContext) -> JSONValue
}

/// Definition collection inserts a placeholder before traversing recursive types.
public struct SchemaContext {
  /// Collected definitions keyed by reflected Swift type name.
  public private(set) var definitions = JSONObject()
  /// A single key strategy applies throughout a generated document.
  public let keyStrategy: JSONKeyStrategy
  /// Creates an empty definition context using one key strategy for the document.
  public init(keyStrategy: JSONKeyStrategy = .identity) { self.keyStrategy = keyStrategy }
  /// Registers a type once and returns its escaped local `$defs` reference.
  /// A temporary placeholder permits recursive definitions.
  public mutating func reference<T: Schemable>(_ type: T.Type) -> JSONValue {
    let name = String(reflecting: type)
    if definitions[name] == nil {
      definitions[name] = .bool(true)
      let definition = type.schemaDefinition(in: &self)
      definitions[name] = definition
    }
    return ["$ref": .string("#" + JSONPointer(tokens: ["$defs", name]).description)]
  }
  /// Builds a draft 2020-12 document with the type as a root reference and all collected definitions.
  public mutating func document<T: Schemable>(_ type: T.Type) -> JSONValue {
    var root = reference(type)
    root["$schema"] = .string(Dialect.draft2020.rawValue)
    root["$defs"] = .object(definitions)
    return root
  }
}

extension Schemable {
  /// The default identity key strategy used when a conformer does not supply one.
  public static var schemaKeyStrategy: JSONKeyStrategy { .identity }
  /// A fresh complete draft 2020-12 document for this type.
  public static var schema: JSONValue {
    var context = SchemaContext(keyStrategy: schemaKeyStrategy)
    return context.document(Self.self)
  }
  /// Compiles the generated schema using bundled metaschemas and default validation options.
  public static func compile() throws -> CompiledSchema { try SchemaCompiler().compile(schema) }
}

extension Schemable where Self: Decodable {
  /// Validates JSON against the generated schema, then decodes using the type's key strategy.
  /// Validation failures carry their result; compilation and Codable errors propagate.
  public static func decode(from value: JSONValue) throws -> Self {
    let result = try compile().validate(value)
    guard result.valid else { throw SchemaDecodingError.invalid(result) }
    return try JSONValueDecoder(keyStrategy: schemaKeyStrategy).decode(Self.self, from: value)
  }
}

/// The JSON key strategy used by schema generation and its matching Codable conversion.
public typealias SchemaKeyStrategy = JSONKeyStrategy

/// Annotation conversion helpers used by generated schema definitions.
public enum SchemaMetadata {
  /// Converts an optional string into an annotation, omitting `nil`.
  public static func text(_ value: String?) -> JSONValue? { value.map(JSONValue.string) }
  /// Applies a schema key strategy to a source property name.
  public static func key(_ text: String, strategy: SchemaKeyStrategy) -> String {
    strategy.key(text)
  }
  /// Converts an optional finite binary64 value into a JSON number.
  /// A nonfinite supplied value violates a precondition.
  public static func number(_ value: Double?) -> JSONValue? {
    guard let value else { return nil }
    precondition(value.isFinite, "Schema bounds must be finite")
    return .number(try! JSONNumber(value))
  }
  /// Converts an optional integer into an exact JSON numeric annotation.
  public static func integer(_ value: Int?) -> JSONValue? { value.map { .number(JSONNumber($0)) } }
  /// An unrepresentable default is omitted from annotations.
  public static func defaultValue<T>(
    _ value: T, keyStrategy: JSONKeyStrategy = .identity
  ) -> JSONValue? {
    guard let encodable = value as? any Encodable else { return nil }
    return try? JSONValueEncoder(keyStrategy: keyStrategy).encode(encodable)
  }
}

/// Synthesizes a schema definition and key strategy for a supported Swift type.
/// Generated schemas use draft 2020-12 and recursive definitions through `SchemaContext`.
@attached(member, names: named(schemaDefinition), named(schemaKeyStrategy))
@attached(extension, conformances: Schemable)
public macro Schemable(keyStrategy: SchemaKeyStrategy = .identity) =
  #externalMacro(module: "JSONSchemaMacros", type: "SchemableMacro")

/// Adds schema constraints to a property consumed by the `Schemable` macro.
/// Defaults are absent; these arguments describe validation, not runtime property initialization.
@attached(peer)
public macro SchemaConstraint(
  minimum: Double? = nil, maximum: Double? = nil, minLength: Int? = nil, maxLength: Int? = nil,
  pattern: String? = nil, format: String? = nil, minItems: Int? = nil, maxItems: Int? = nil,
  description: String? = nil
) = #externalMacro(module: "JSONSchemaMacros", type: "ConstraintMacro")

extension String: Schemable {
  public static func schemaDefinition(in context: inout SchemaContext) -> JSONValue {
    ["type": "string"]
  }
}
extension Bool: Schemable {
  public static func schemaDefinition(in context: inout SchemaContext) -> JSONValue {
    ["type": "boolean"]
  }
}
extension Int: Schemable {
  public static func schemaDefinition(in context: inout SchemaContext) -> JSONValue {
    ["type": "integer"]
  }
}
extension Int8: Schemable {
  public static func schemaDefinition(in context: inout SchemaContext) -> JSONValue {
    ["type": "integer"]
  }
}
extension Int16: Schemable {
  public static func schemaDefinition(in context: inout SchemaContext) -> JSONValue {
    ["type": "integer"]
  }
}
extension Int32: Schemable {
  public static func schemaDefinition(in context: inout SchemaContext) -> JSONValue {
    ["type": "integer"]
  }
}
extension Int64: Schemable {
  public static func schemaDefinition(in context: inout SchemaContext) -> JSONValue {
    ["type": "integer"]
  }
}
extension UInt: Schemable {
  public static func schemaDefinition(in context: inout SchemaContext) -> JSONValue {
    ["type": "integer", "minimum": 0]
  }
}
extension UInt8: Schemable {
  public static func schemaDefinition(in context: inout SchemaContext) -> JSONValue {
    ["type": "integer", "minimum": 0]
  }
}
extension UInt16: Schemable {
  public static func schemaDefinition(in context: inout SchemaContext) -> JSONValue {
    ["type": "integer", "minimum": 0]
  }
}
extension UInt32: Schemable {
  public static func schemaDefinition(in context: inout SchemaContext) -> JSONValue {
    ["type": "integer", "minimum": 0]
  }
}
extension UInt64: Schemable {
  public static func schemaDefinition(in context: inout SchemaContext) -> JSONValue {
    ["type": "integer", "minimum": 0]
  }
}
extension Double: Schemable {
  public static func schemaDefinition(in context: inout SchemaContext) -> JSONValue {
    ["type": "number"]
  }
}
extension Float: Schemable {
  public static func schemaDefinition(in context: inout SchemaContext) -> JSONValue {
    ["type": "number"]
  }
}
extension JSONValue: Schemable {
  public static func schemaDefinition(in context: inout SchemaContext) -> JSONValue { .bool(true) }
}
extension JSONNumber: Schemable {
  public static func schemaDefinition(in context: inout SchemaContext) -> JSONValue {
    ["type": "number"]
  }
}
extension Optional: Schemable where Wrapped: Schemable {
  public static func schemaDefinition(in context: inout SchemaContext) -> JSONValue {
    ["anyOf": .array([context.reference(Wrapped.self), ["type": "null"]])]
  }
}
extension Array: Schemable where Element: Schemable {
  public static func schemaDefinition(in context: inout SchemaContext) -> JSONValue {
    ["type": "array", "items": context.reference(Element.self)]
  }
}
extension Dictionary: Schemable where Key == String, Value: Schemable {
  public static func schemaDefinition(in context: inout SchemaContext) -> JSONValue {
    ["type": "object", "additionalProperties": context.reference(Value.self)]
  }
}
