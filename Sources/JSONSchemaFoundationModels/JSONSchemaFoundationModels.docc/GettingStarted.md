# Getting started

A compiling example for JSONSchemaFoundationModels.

```swift
import JSONSchemaFoundationModels
import JSONValue

func generationExample() throws {
  #if canImport(FoundationModels)
  if #available(iOS 26.0, macOS 26.0, *) {
    let definition: JSONValue = ["type": "object", "properties": ["city": ["type": "string"]], "required": ["city"], "additionalProperties": false]
    _ = try GenerationBridge.toolInput(definition, name: "WeatherRequest")
  }
  #endif
}
```
