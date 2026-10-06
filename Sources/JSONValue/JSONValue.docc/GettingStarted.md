# Getting started

Preserve JSON number tokens and member order while working with a Swift value tree.

Parse UTF-8 JSON, resolve a pointer, and serialize the result. The example retains a decimal value that exceeds the precision of binary64.

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

## Parsing and identity

`JSONParser` accepts UTF-8 and provides `.first`, `.last`, and `.reject`
duplicate-key policies. Parse errors include a byte offset, line, byte column,
and JSON pointer. Nesting defaults to 256 and can be configured.

Object members retain insertion order. String and key equality distinguishes
Unicode spellings by UTF-8 identity. Whitespace is regenerated on serialization.

## Choosing an output form

Compact and pretty output retain `JSONNumber.text`. Canonical output uses
RFC 8785 binary64 number semantics and sorts keys by UTF-16 code units; it can
change number spelling or fail when a number is outside its supported range.
Converting to a bounded Swift number can also fail independently of parsing.
