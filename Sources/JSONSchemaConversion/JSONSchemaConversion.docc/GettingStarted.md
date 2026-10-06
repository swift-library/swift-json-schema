# Getting started

Extract Foundation values from their JSON wire representations.

The conversion components validate their schema and then check whether Foundation can represent the value. This example decodes an RFC 3339 timestamp and canonical base64 data.

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

## Wire representations

The URL component accepts absolute URI strings. UUIDs use UUID strings; dates
use RFC 3339 timestamps; data uses canonical base64. Decimal conversion checks
that Foundation preserves the exact JSON number and throws on precision loss.

These types also gain `Schemable` conformances. Schema generation describes
the wire format; extraction performs the representation checks needed to
produce the corresponding Foundation value.
