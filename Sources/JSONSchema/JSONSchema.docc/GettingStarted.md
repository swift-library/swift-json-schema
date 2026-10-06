# Getting started

Compile a schema once and inspect each validation result.

A compiler defaults to draft 2020-12. A schema can select another supported dialect with `$schema`; compilation resolves the reachable schema graph.

```swift
import JSONSchema
import JSONValue

func validationExample() throws {
  let definition: JSONValue = ["type": "integer", "minimum": 0]
  let validator = try SchemaCompiler().compile(definition)
  let result = validator.validate(42)
  precondition(result.valid)
  precondition(result.output(.flag) == ["valid": true])
}
```

## Results and schema checking

Inspect `valid`, location-rich `errors`, and successful `annotations` on the
result. Select `.flag`, `.basic`, `.detailed`, or `.verbose` with `output`,
or use `humanReadable` for text. `checkSchema()` on a compiled schema performs
metaschema validation separately from compilation.

## References and options

Start with `SchemaRegistry.bundled` and register external schema documents by
URI. Synchronous compilation stays offline. Asynchronous compilation accepts
an explicit HTTPS host policy and resolver; relative file references are not
loaded automatically. Compound bundling requires draft 2020-12.

Format assertion and content evaluation are opt-in validation options.
Evaluation depth defaults to 512; reaching the limit produces an invalid
result. A compiled schema is immutable and `Sendable`, and each call owns its
own evaluation state.
