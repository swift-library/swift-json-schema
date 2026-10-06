# ``JSONSchemaBuilder``

Construct draft 2020-12 schemas with a typed DSL and Swift macros.

@Metadata {
    @PageImage(purpose: icon, source: "jsonschemabuilder-icon", alt: "swift-json-schema logo")
    @PageColor(purple)
}

Build a ``SchemaComponent`` from property and composition builders, or use the `@Schemable` macro on a model. Both paths validate JSON before extracting a Swift value.

## Topics

### Getting started

- <doc:GettingStarted>

### API

- ``Schema``
- ``SchemaComponent``
- ``SchemaProperty``
- ``PropertyBuilder``
- ``SchemaListBuilder``
- ``SchemaContext``
- ``SchemaMetadata``
- ``SchemaKeyStrategy``
- ``Schemable-swift.protocol``
- ``Schemable(keyStrategy:)``
- ``SchemaConstraint(minimum:maximum:minLength:maxLength:pattern:format:minItems:maxItems:description:)``
