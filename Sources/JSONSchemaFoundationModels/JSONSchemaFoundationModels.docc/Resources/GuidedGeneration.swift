// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2026 Xudong Xu

import JSONSchemaFoundationModels
import JSONValue

func generationExample() throws {
  #if canImport(FoundationModels)
    if #available(iOS 26.0, macOS 26.0, *) {
      let definition: JSONValue = [
        "type": "object", "properties": ["city": ["type": "string"]], "required": ["city"],
        "additionalProperties": false,
      ]
      _ = try GenerationBridge.toolInput(definition, name: "WeatherRequest")
    }
  #endif
}
