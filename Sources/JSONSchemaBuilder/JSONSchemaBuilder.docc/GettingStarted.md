# Getting started

A compiling example for JSONSchemaBuilder.

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
