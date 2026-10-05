# Getting started

A compiling example for JSONValue.

```swift
import JSONValue

func exactJSONExample() throws {
  let value = try JSONValue.parse(#"{"amount":12345678901234567890.125,"tags":["swift"]}"#)
  let amount = try JSONPointer("/amount").resolve(in: value)
  precondition(amount.numberValue?.text == "12345678901234567890.125")
  let text = try value.serialized()
  precondition(text.contains("12345678901234567890.125"))
}
```
