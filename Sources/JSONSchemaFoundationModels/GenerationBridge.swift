// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2026 Xudong Xu

#if canImport(FoundationModels)
  import FoundationModels
  import JSONSchema
  import JSONValue

  @available(iOS 26.0, macOS 26.0, *)
  public enum GenerationBridgeError: Error {
    case unsupportedKeyword(String)
    case unsupportedShape(String)
    case unresolvedDefinition(String)
  }
  /// Converts representable shapes; validate generated content with the original schema.
  @available(iOS 26.0, macOS 26.0, *)
  public enum GenerationBridge {
    public static func schema(_ document: JSONValue, name: String) throws -> GenerationSchema {
      let definitions = document["$defs"]?.objectValue ?? JSONObject()
      let dependencies = try definitions.map {
        try convert($0.1, name: $0.0, definitions: definitions)
      }
      return try GenerationSchema(
        root: convert(document, name: name, definitions: definitions), dependencies: dependencies)
    }
    public static func toolInput(_ document: JSONValue, name: String) throws -> GenerationSchema {
      var root = document
      if let reference = document["$ref"]?.stringValue, let pointer = try? JSONPointer(reference),
        let resolved = try? pointer.resolve(in: document)
      {
        root = resolved
      }
      guard root["type"]?.stringValue == "object" else {
        throw GenerationBridgeError.unsupportedShape("Tool input must be an object")
      }
      return try schema(document, name: name)
    }
    private static func convert(_ document: JSONValue, name: String, definitions: JSONObject) throws
      -> DynamicGenerationSchema
    {
      guard document.objectValue != nil else {
        throw GenerationBridgeError.unsupportedShape("Boolean schemas have no generation shape")
      }
      let accepted = Set([
        "$schema", "$id", "$defs", "$ref", "title", "description", "default", "deprecated", "type",
        "properties", "required", "additionalProperties", "items", "minItems", "maxItems", "enum",
        "anyOf", "oneOf",
      ])
      for (keyword, _) in document.objectValue! where !accepted.contains(keyword) {
        throw GenerationBridgeError.unsupportedKeyword(keyword)
      }
      if let reference = document["$ref"]?.stringValue {
        let pointer = try JSONPointer(reference)
        guard pointer.tokens.count == 2, pointer.tokens[0] == "$defs",
          definitions[pointer.tokens[1]] != nil
        else { throw GenerationBridgeError.unresolvedDefinition(reference) }
        return DynamicGenerationSchema(referenceTo: pointer.tokens[1])
      }
      let description = document["description"]?.stringValue
      if let choices = document["enum"]?.arrayValue {
        guard choices.allSatisfy({ $0.stringValue != nil }) else {
          throw GenerationBridgeError.unsupportedShape("Generation enums require strings")
        }
        return DynamicGenerationSchema(
          name: name, description: description, anyOf: choices.compactMap(\.stringValue))
      }
      if let alternatives = document["anyOf"]?.arrayValue ?? document["oneOf"]?.arrayValue {
        let choices = try alternatives.enumerated().map {
          try convert($0.element, name: name + "-\($0.offset)", definitions: definitions)
        }
        return DynamicGenerationSchema(name: name, description: description, anyOf: choices)
      }
      switch document["type"]?.stringValue {
      case "string":
        return DynamicGenerationSchema(
          name: name, description: description, anyOf: [DynamicGenerationSchema(type: String.self)])
      case "integer":
        return DynamicGenerationSchema(
          name: name, description: description, anyOf: [DynamicGenerationSchema(type: Int.self)])
      case "number":
        return DynamicGenerationSchema(
          name: name, description: description, anyOf: [DynamicGenerationSchema(type: Double.self)])
      case "boolean":
        return DynamicGenerationSchema(
          name: name, description: description, anyOf: [DynamicGenerationSchema(type: Bool.self)])
      case "array":
        guard let items = document["items"] else {
          throw GenerationBridgeError.unsupportedShape("Arrays require an item shape")
        }
        return try DynamicGenerationSchema(
          name: name, description: description,
          anyOf: [
            DynamicGenerationSchema(
              arrayOf: convert(items, name: name + "-item", definitions: definitions),
              minimumElements: document["minItems"]?.numberValue?.intValue,
              maximumElements: document["maxItems"]?.numberValue?.intValue)
          ])
      case "object":
        if let additional = document["additionalProperties"], additional != .bool(false) {
          throw GenerationBridgeError.unsupportedShape(
            "Generation objects require named properties")
        }
        let required = document["required"]?.arrayValue?.compactMap(\.stringValue) ?? []
        let properties = try (document["properties"]?.objectValue ?? JSONObject()).map {
          key, value in
          DynamicGenerationSchema.Property(
            name: key, description: value["description"]?.stringValue,
            schema: try convert(value, name: name + "-" + key, definitions: definitions),
            isOptional: !required.contains(key))
        }
        return DynamicGenerationSchema(name: name, description: description, properties: properties)
      default:
        throw GenerationBridgeError.unsupportedShape("Schema needs a concrete generation type")
      }
    }
  }
#endif
