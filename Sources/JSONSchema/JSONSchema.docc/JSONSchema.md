# ``JSONSchema``

Compile and validate JSON Schema drafts 2020-12, 2019-09, 07, 06, and 04.

@Metadata {
    @PageImage(purpose: icon, source: "jsonschema-icon", alt: "swift-json-schema logo")
    @PageColor(purple)
}

Compile a schema once, reuse its immutable validator, and choose structured or human-readable results. Registries provide offline references; asynchronous resolution requires an explicit HTTPS host policy.

## Topics

### Getting started

- <doc:GettingStarted>
- <doc:Validation>

### API

- ``Dialect``
- ``SchemaCompiler``
- ``CompiledSchema``
- ``SchemaRegistry``
- ``SchemaResolver``
- ``ResolverPolicy``
- ``SchemaVocabulary``
- ``SchemaKeyword``
- ``KeywordResult``
- ``ValidationOptions``
- ``ValidationResult``
- ``ValidationUnit``
- ``OutputFormat``
- ``ECMARegularExpression``
- ``FormatValidation``
- ``SchemaError``
