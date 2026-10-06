# Getting started

Describe an object with the DSL or derive its schema from a Swift model.

The example validates the same object with an explicit component and an `@Schemable` model. `SchemaProperty` is required by default.

```swift
import JSONSchemaBuilder

@Schemable
struct Person: Codable {
  @SchemaConstraint(minLength: 1)
  var name: String
  @SchemaConstraint(minimum: 0)
  var age: Int
}

func builderExample() throws {
  let definition = Schema.object {
    SchemaProperty("name", Schema.string().minLength(1))
    SchemaProperty("age", Schema.integer().minimum(0))
  }.additionalProperties(false)
  let value: JSONValue = ["name": "Ada", "age": 42]
  let person = try definition.decode(Person.self, from: value)
  precondition(person.name == "Ada")
  let generated = try Person.decode(from: value)
  precondition(generated.age == 42)
}
```

## Validation and extraction

A component pairs a schema document with a Swift extraction function. `decode`
validates before extraction. Schema validity does not guarantee that a numeric
value fits `Int` or another bounded destination; extraction can still throw.

Use `required: false` for an optional property and `nullable()` when JSON null
is an accepted value. These describe different aspects of an object. A
`defaultValue` annotation does not insert a missing property.

## Generated schemas

`@Schemable` emits draft 2020-12 schemas and collects referenced types under
`$defs`, including recursive types. The root key strategy applies throughout
the document. Keep the Codable wire naming and the selected strategy aligned;
case conversion may not preserve an arbitrary original spelling.
