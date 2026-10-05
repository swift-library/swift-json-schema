# Getting started

A compiling example for JSONSchemaConversion.

```swift
import Foundation
import JSONSchemaConversion
import JSONValue

func foundationExample() throws {
  let timestamp = try FoundationSchema.date.decode(from: JSONValue.string("1970-01-01T00:00:00Z"))
  precondition(timestamp.timeIntervalSince1970 == 0)
  let bytes = try FoundationSchema.data.decode(from: JSONValue.string("AQID"))
  precondition(bytes == Data([1, 2, 3]))
}
```
