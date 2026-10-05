// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2026 Xudong Xu

import JSONSchemaBuilder
import Testing

/// Contact record.
@Schemable(keyStrategy: .snakeCase)
struct Contact: Codable, Equatable {
  /// Display name.
  @SchemaConstraint(minLength: 2)
  var displayName: String
  var age: Int = 18
  var email: String?
}

@Schemable
struct Envelope<T: Codable>: Codable { var value: T }

@Schemable
enum Command: Codable, Equatable {
  case ping
  case move(x: Int, y: Int)
  case message(String)
}

@Schemable
enum Color: String, Codable {
  case red = "r"
  case blue
}

@Schemable
struct Tree: Codable {
  var value: Int
  var children: [Tree]
}

@Schemable
struct Renamed: Codable {
  var value: String
  var ignored: Int = 0
  enum CodingKeys: String, CodingKey { case value = "wire" }
}

@Schemable(keyStrategy: .snakeCase)
enum WireCommand: Codable, Equatable {
  case moveFast(offsetY: Int)
  case done
  enum CodingKeys: String, CodingKey {
    case moveFast = "fast_move"
    case done
  }
  enum MoveFastCodingKeys: String, CodingKey { case offsetY = "distanceY" }
}

@Schemable
struct EscapedKey: Codable {
  var value: String
  enum CodingKeys: String, CodingKey { case value = "wire\n" }
}

@Schemable
struct ContactDetails: Codable { var customerID: Int = 7 }

@Schemable(keyStrategy: .snakeCase)
struct NestedContact: Codable { var details: ContactDetails = ContactDetails() }

@Schemable
enum Mode { case minimal }

@Schemable
struct Settings { var mode: Mode = .minimal }

@Suite struct SchemaConstruction {
  @Test func validatesBeforeExtraction() throws {
    let definition = Schema.object {
      SchemaProperty("name", Schema.string().minLength(2))
      SchemaProperty("age", Schema.integer().minimum(0), required: false)
    }.additionalProperties(false)
    #expect(try definition.decode(from: #"{"name":"Ada","age":21}"#)["name"] == "Ada")
    #expect(throws: SchemaDecodingError.self) { try definition.decode(from: #"{"name":"A"}"#) }
    #expect(try Schema.integer().array().decode(from: "[1,2,3]") == [1, 2, 3])
    #expect(try Schema.string().nullable().decode(from: "null") == nil)
    #expect(try Schema.integer().map { $0 * 2 }.decode(from: "7") == 14)
  }

  @Test func generatedDefinitionsAndMetadata() throws {
    let root = try JSONPointer(Contact.schema["$ref"]!.stringValue!).resolve(in: Contact.schema)
    #expect(root["description"] == "Contact record.")
    #expect(root["properties"]?["display_name"]?["description"] == "Display name.")
    #expect(root["properties"]?["age"]?["default"] == 18)
    #expect(
      try Contact.compile().validate(JSONValue.parse(#"{"display_name":"Ada","age":21}"#)).valid)
    let contact = try Contact.decode(from: ["display_name": "Ada", "age": 21])
    #expect(contact.displayName == "Ada")
    #expect(
      try JSONValueEncoder(keyStrategy: Contact.schemaKeyStrategy).encode(contact)["display_name"]
        == "Ada")
    #expect(
      try !Contact.compile().validate(JSONValue.parse(#"{"display_name":"A","age":21}"#)).valid)
    #expect(try Envelope<Int>.decode(from: ["value": 7]).value == 7)
    #expect(try Renamed.decode(from: ["wire": "text"]).value == "text")
    #expect(try EscapedKey.decode(from: ["wire\n": "text"]).value == "text")
    #expect(try !Renamed.compile().validate(["value": "text"]).valid)
    let encoded = try JSONValueEncoder(keyStrategy: NestedContact.schemaKeyStrategy).encode(
      NestedContact())
    #expect(encoded["details"]?["customer_id"] == 7)
    #expect(try NestedContact.decode(from: encoded).details.customerID == 7)
    let nested = try JSONPointer(NestedContact.schema["$ref"]!.stringValue!).resolve(
      in: NestedContact.schema)
    #expect(nested["properties"]?["details"]?["default"] == ["customer_id": 7])
    #expect(try ContactDetails.compile().validate(["customerID": 7]).valid)
    #expect(try Settings.compile().validate(["mode": ["minimal": [:]]]).valid)
  }

  @Test func enumWireShapesAndRecursion() throws {
    let encoder = JSONValueEncoder()
    for command in [Command.ping, .move(x: 2, y: 4), .message("hello")] {
      let value = try encoder.encode(command)
      #expect(try Command.decode(from: value) == command)
    }
    #expect(try Color.compile().validate(JSONValue.string("r")).valid)
    #expect(try !Color.compile().validate(JSONValue.string("red")).valid)
    #expect(
      try Tree.decode(from: ["value": 1, "children": [["value": 2, "children": []]]]).children[0]
        .value == 2)
    let command = WireCommand.moveFast(offsetY: 12)
    let wire = try JSONValueEncoder(keyStrategy: WireCommand.schemaKeyStrategy).encode(command)
    #expect(wire["fast_move"]?["distance_y"] == 12)
    #expect(try WireCommand.decode(from: wire) == command)
  }
}
