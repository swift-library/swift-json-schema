// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2026 Xudong Xu

import JSONSchemaFoundationModels
import JSONValue
import Testing

#if canImport(FoundationModels)
  import FoundationModels

  @Suite struct Bridge {
    @Test func namedToolInput() throws {
      if #available(macOS 26.0, iOS 26.0, *) {
        let schema: JSONValue = [
          "type": "object", "properties": ["city": ["type": "string"]], "required": ["city"],
          "additionalProperties": false,
        ]
        _ = try GenerationBridge.toolInput(schema, name: "WeatherRequest")
        #expect(throws: GenerationBridgeError.self) {
          try GenerationBridge.schema(["type": "string", "pattern": "^[A-Z]+$"], name: "Code")
        }
      }
    }

    @Test func namedDefinitions() throws {
      if #available(macOS 26.0, iOS 26.0, *) {
        let schema: JSONValue = [
          "$ref": "#/$defs/Record",
          "$defs": [
            "Record": [
              "type": "object", "properties": ["name": ["$ref": "#/$defs/Text"]],
              "required": ["name"],
            ], "Text": ["type": "string"],
          ],
        ]
        _ = try GenerationBridge.toolInput(schema, name: "Record")
      }
    }
  }
#else
  @Test func platformModuleIsImportable() { #expect(true) }
#endif
