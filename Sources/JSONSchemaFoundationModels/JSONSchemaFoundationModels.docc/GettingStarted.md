# Getting started

Create a generation schema for an object-shaped tool input.

The bridge requires a Foundation Models SDK and iOS 26 or macOS 26. Guard the import surface and runtime availability when your package also supports older systems.

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

## Supported shapes

The bridge supports concrete string, integer, number, boolean, array, and
named-object shapes, string enums, alternatives, and references to `$defs`.
Arrays need an item shape. Tool inputs need an object root. Boolean schemas,
null shapes, arbitrary additional properties, and unsupported validation
keywords produce an error.

## Validate generated content

The bridge constructs generation schemas; it does not perform model inference.
Generation shapes do not replace full JSON Schema validation. Keep the original
schema and validate the generated JSON with `JSONSchema` before decoding or
using it.
