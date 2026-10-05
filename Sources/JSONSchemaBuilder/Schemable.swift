// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2026 Xudong Xu

import JSONSchema
import JSONValue

public protocol Schemable {
  static var schemaKeyStrategy: JSONKeyStrategy { get }
  static func schemaDefinition(in context: inout SchemaContext) -> JSONValue
}

/// Definition collection inserts a placeholder before traversing recursive types.
public struct SchemaContext {
  public private(set) var definitions = JSONObject()
  public init() {}
  public mutating func reference<T: Schemable>(_ type: T.Type) -> JSONValue {
    let name = String(reflecting: type)
    if definitions[name] == nil {
      definitions[name] = .bool(true)
      let definition = type.schemaDefinition(in: &self)
      definitions[name] = definition
    }
    return ["$ref": .string("#" + JSONPointer(tokens: ["$defs", name]).description)]
  }
  public mutating func document<T: Schemable>(_ type: T.Type) -> JSONValue {
    var root = reference(type)
    root["$schema"] = .string(Dialect.draft2020.rawValue)
    root["$defs"] = .object(definitions)
    return root
  }
}

extension Schemable {
  public static var schemaKeyStrategy: JSONKeyStrategy { .identity }
  public static var schema: JSONValue {
    var context = SchemaContext()
    return context.document(Self.self)
  }
  public static func compile() throws -> CompiledSchema { try SchemaCompiler().compile(schema) }
}

extension Schemable where Self: Decodable {
  public static func decode(from value: JSONValue) throws -> Self {
    let result = try compile().validate(value)
    guard result.valid else { throw SchemaDecodingError.invalid(result) }
    return try JSONValueDecoder(keyStrategy: schemaKeyStrategy).decode(Self.self, from: value)
  }
}

public typealias SchemaKeyStrategy = JSONKeyStrategy

public enum SchemaMetadata {
  public static func text(_ value: String?) -> JSONValue? { value.map(JSONValue.string) }
  public static func key(_ text: String, strategy: SchemaKeyStrategy) -> String {
    strategy.key(text)
  }
  public static func number(_ value: Double?) -> JSONValue? {
    guard let value else { return nil }
    precondition(value.isFinite, "Schema bounds must be finite")
    return .number(try! JSONNumber(value))
  }
  public static func integer(_ value: Int?) -> JSONValue? { value.map { .number(JSONNumber($0)) } }
  /// An unrepresentable default is omitted from annotations.
  public static func defaultValue<T: Encodable>(_ value: T) -> JSONValue? {
    try? JSONValueEncoder().encode(value)
  }
}

@attached(member, names: named(schemaDefinition), named(schemaKeyStrategy))
@attached(extension, conformances: Schemable)
public macro Schemable(keyStrategy: SchemaKeyStrategy = .identity) =
  #externalMacro(module: "JSONSchemaMacros", type: "SchemableMacro")

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
