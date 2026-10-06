// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2026 Xudong Xu

import Foundation
import JSONValue

/// A compiled schema can be reused concurrently; all evaluation state is call-local.
public struct CompiledSchema: Sendable {
  /// The original schema document supplied to compilation.
  public let schema: JSONValue
  let nodes: [SchemaNode]
  let root: Int
  let anchors: [String: [String: Int]]
  let options: ValidationOptions
  let custom: [String: SchemaVocabulary]
  let registry: SchemaRegistry
  /// The root resource's effective dialect after resolving its `$schema` declaration.
  public var dialect: Dialect { nodes[root].dialect }
  /// Validates a JSON value with call-local evaluation state and returns a structured result.
  /// An invalid instance or an exhausted evaluation limit is reported in the result.
  public func validate(_ value: JSONValue) -> ValidationResult {
    var evaluation = Evaluator(compiled: self)
    return ValidationResult(
      tree: evaluation.run(root, value: value, instance: .init(), path: .init(), scopes: []).unit)
  }
  /// Parses JSON text with the parser's default limits, then validates it.
  /// Parsing errors throw; schema violations are returned in the result.
  public func validate(_ text: String) throws -> ValidationResult {
    validate(try JSONValue.parse(text))
  }
  /// Validates the schema document against its registered metaschema with format assertions enabled.
  /// Throws if the metaschema cannot be found or compiled.
  public func checkSchema() throws -> ValidationResult {
    let uri = schema["$schema"]?.stringValue ?? dialect.rawValue
    guard let meta = registry.documents[URI.document(uri)] else {
      throw SchemaError.unresolvedReference(uri)
    }
    return try SchemaCompiler(
      dialect: dialect, registry: registry, options: .init(assertFormats: true)
    ).compile(meta, baseURI: uri).validate(schema)
  }
}

private struct Visit: Hashable {
  let node: Int
  let location: JSONPointer
  let scope: [String]
}

private struct EvaluationRequest {
  let index: Int
  let value: JSONValue
  let instance: JSONPointer
  let path: JSONPointer
  let scopes: [String]
}

private final class EvaluationBatch {
  var results: [Evaluation] = []
}

private typealias EvaluationAction = (inout Evaluator) -> Void

private struct Evaluator {
  let compiled: CompiledSchema
  var visits: Set<Visit> = []
  var depth = 0
  var actions: [EvaluationAction] = []

  mutating func run(
    _ index: Int, value: JSONValue, instance: JSONPointer, path: JSONPointer, scopes: [String]
  ) -> Evaluation {
    let result = EvaluationBatch()
    enter(
      EvaluationRequest(index: index, value: value, instance: instance, path: path, scopes: scopes)
    ) { _, evaluation in result.results.append(evaluation) }
    while let action = actions.popLast() { action(&self) }
    return result.results[0]
  }

  private mutating func enqueue(_ sequence: [EvaluationAction]) {
    // Child evaluations finish before the parent's next keyword collects annotations.
    actions.append(contentsOf: sequence.reversed())
  }

  private mutating func batch(
    _ requests: [EvaluationRequest], complete: @escaping (inout Evaluator, [Evaluation]) -> Void
  ) {
    let batch = EvaluationBatch()
    actions.append { evaluator in complete(&evaluator, batch.results) }
    for request in requests.reversed() {
      actions.append { evaluator in
        evaluator.enter(request) { _, result in batch.results.append(result) }
      }
    }
  }

  private mutating func enter(
    _ request: EvaluationRequest, complete: @escaping (inout Evaluator, Evaluation) -> Void
  ) {
    let node = compiled.nodes[request.index]
    var scopes = request.scopes
    if scopes.last != node.resource { scopes.append(node.resource) }
    let visit = Visit(
      node: request.index, location: request.instance, scope: Array(Set(scopes)).sorted())
    let absolute = node.locations[Data()] ?? URI.location(node.resource, node.pointer)
    if depth >= compiled.options.maximumDepth || visits.contains(visit) {
      let reason =
        depth >= compiled.options.maximumDepth
        ? "Maximum evaluation depth exceeded" : "Reference recursion did not make progress"
      complete(
        &self,
        Evaluation(
          unit: ValidationUnit(
            valid: false, keywordLocation: request.path, absoluteKeywordLocation: absolute,
            instanceLocation: request.instance, error: reason, annotation: nil, children: [])))
      return
    }
    if let flag = node.value.boolValue {
      complete(
        &self,
        Evaluation(
          unit: ValidationUnit(
            valid: flag, keywordLocation: request.path, absoluteKeywordLocation: absolute,
            instanceLocation: request.instance,
            error: flag ? nil : "Boolean schema rejects the value", annotation: nil, children: [])))
      return
    }
    visits.insert(visit)
    depth += 1
    let frame = EvaluationFrame(
      node: node, value: request.value, instance: request.instance, path: request.path,
      scopes: scopes)
    actions.append { evaluator in
      evaluator.visits.remove(visit)
      evaluator.depth -= 1
      complete(&evaluator, frame.result())
    }
    if !node.dialect.modern && node.references["$ref"] != nil {
      actions.append { $0.references(frame) }
    } else {
      enqueue([
        { $0.references(frame) }, { $0.scalars(frame) }, { $0.combinations(frame) },
        { $0.objects(frame) }, { $0.arrays(frame) }, { $0.customKeywords(frame) },
        { $0.unevaluated(frame) }, { $0.metadata(frame) },
      ])
    }
  }

  private func request(
    _ frame: EvaluationFrame, tokens: [String], value: JSONValue? = nil,
    instance: JSONPointer? = nil
  ) -> EvaluationRequest? {
    guard let index = frame.child(tokens) else { return nil }
    return EvaluationRequest(
      index: index, value: value ?? frame.value, instance: instance ?? frame.instance,
      path: JSONPointer(tokens: frame.path.tokens + tokens), scopes: frame.scopes)
  }

  private mutating func references(_ frame: EvaluationFrame) {
    var keywords: [String] = []
    var requests: [EvaluationRequest] = []
    for keyword in ["$ref", "$dynamicRef", "$recursiveRef"] {
      guard var target = frame.node.references[keyword] else { continue }
      let initial = compiled.nodes[target]
      if keyword == "$dynamicRef", let name = initial.dynamicName,
        URI.fragment(
          try! URI.resolve(frame.node.value[keyword]!.stringValue!, against: frame.node.base))
          == name
      {
        for resource in frame.scopes {
          if let dynamic = compiled.anchors[resource]?[name] {
            target = dynamic
            break
          }
        }
      }
      if keyword == "$recursiveRef", initial.dynamicName == "" {
        for resource in frame.scopes {
          if let recursive = compiled.anchors[resource]?[""] {
            target = recursive
            break
          }
        }
      }
      keywords.append(keyword)
      requests.append(
        EvaluationRequest(
          index: target, value: frame.value, instance: frame.instance,
          path: frame.path.appending(keyword), scopes: frame.scopes))
    }
    batch(requests) { _, results in
      for (keyword, result) in zip(keywords, results) {
        frame.units.append(frame.unit(keyword, valid: result.valid, children: [result.unit]))
        if result.valid { frame.absorb([result]) }
      }
    }
  }
  private mutating func scalars(_ frame: EvaluationFrame) {
    let node = frame.node
    let definition = frame.node.value
    let value = frame.value
    let instance = frame.instance
    let path = frame.path
    let scopes = frame.scopes
    if frame.enabled("type"), let type = definition["type"] {
      let types = type.arrayValue ?? [type]
      let accepts = types.contains { expected in
        guard let name = expected.stringValue else { return false }
        return name == value.typeName || (name == "integer" && value.numberValue?.isInteger == true)
      }
      frame.units.append(
        frame.unit(
          "type", valid: accepts,
          message:
            "Expected \(types.compactMap(\.stringValue).joined(separator: " or ")), found \(value.typeName)"
        ))
    }
    if frame.enabled("enum"), let cases = definition["enum"]?.arrayValue {
      frame.units.append(
        frame.unit(
          "enum", valid: cases.contains(value), message: "Value is outside the enumeration"))
    }
    if frame.enabled("const"), node.dialect != .draft4, let constant = definition["const"] {
      frame.units.append(
        frame.unit("const", valid: constant == value, message: "Value differs from the constant"))
    }
    if let number = value.numberValue {
      for keyword in ["minimum", "maximum", "exclusiveMinimum", "exclusiveMaximum", "multipleOf"]
      where frame.enabled(keyword) {
        guard let limit = definition[keyword]?.numberValue else { continue }
        if node.dialect == .draft4 && keyword.hasPrefix("exclusive") { continue }
        let accepts: Bool
        switch keyword {
        case "minimum":
          accepts =
            node.dialect == .draft4 && definition["exclusiveMinimum"]?.boolValue == true
            ? number > limit : number >= limit
        case "maximum":
          accepts =
            node.dialect == .draft4 && definition["exclusiveMaximum"]?.boolValue == true
            ? number < limit : number <= limit
        case "exclusiveMinimum": accepts = number > limit
        case "exclusiveMaximum": accepts = number < limit
        default: accepts = number.isMultiple(of: limit)
        }
        frame.units.append(
          frame.unit(keyword, valid: accepts, message: "Number fails \(keyword) \(limit.text)"))
      }
    }
    if let string = value.stringValue {
      for keyword in ["minLength", "maxLength"] where frame.enabled(keyword) {
        guard let limit = definition[keyword]?.numberValue else { continue }
        let size = JSONNumber(string.unicodeScalars.count)
        frame.units.append(
          frame.unit(
            keyword, valid: keyword == "minLength" ? size >= limit : size <= limit,
            message: "String fails \(keyword)"))
      }
      if frame.enabled("pattern"), let regex = node.patterns[Data("pattern".utf8)] {
        frame.units.append(
          frame.unit(
            "pattern", valid: regex.matches(string), message: "String does not match the pattern"))
      }
      if frame.enabled("format"), let name = definition["format"]?.stringValue {
        let asserted =
          compiled.options.assertFormats
          || node.active?.contains(where: { $0.hasSuffix("/format-assertion") }) == true
        frame.units.append(
          frame.unit(
            "format",
            valid: !asserted
              || FormatValidation.matches(string, format: name, dialect: node.dialect),
            message: "String is not a valid \(name)", annotation: .string(name)))
      }
      if frame.enabled("contentEncoding") {
        for key in ["contentEncoding", "contentMediaType", "contentSchema"] {
          if let annotation = definition[key] {
            frame.units.append(frame.unit(key, annotation: annotation))
          }
        }
        if compiled.options.evaluateContent {
          let encoding = definition["contentEncoding"]?.stringValue
          guard let data = ContentDecoding.decode(string, encoding: encoding) else {
            frame.units.append(
              frame.unit("contentEncoding", valid: false, message: "Invalid encoded content"))
            return
          }
          let mediaType = definition["contentMediaType"]?.stringValue?.split(separator: ";").first?
            .trimmingCharacters(in: .whitespaces).lowercased()
          if mediaType == "application/json" || mediaType?.hasSuffix("+json") == true {
            guard let decoded = try? JSONValue.parse(data) else {
              frame.units.append(
                frame.unit("contentMediaType", valid: false, message: "Content is not JSON"))
              return
            }
            if let content = frame.child(["contentSchema"]) {
              batch([
                EvaluationRequest(
                  index: content, value: decoded, instance: instance,
                  path: path.appending("contentSchema"), scopes: scopes)
              ]) { _, results in
                frame.units.append(
                  frame.unit("contentSchema", valid: results[0].valid, children: [results[0].unit]))
              }
            }
          }
        }
      }
    }
  }

  private mutating func combinations(_ frame: EvaluationFrame) {
    var sequence: [EvaluationAction] = []
    for keyword in ["allOf", "anyOf", "oneOf"] where frame.enabled(keyword) {
      guard let branches = frame.node.value[keyword]?.arrayValue else { continue }
      sequence.append { evaluator in
        let requests = branches.indices.compactMap {
          evaluator.request(frame, tokens: [keyword, String($0)])
        }
        evaluator.batch(requests) { _, results in
          let successes = results.filter(\.valid)
          let valid =
            keyword == "allOf"
            ? successes.count == results.count
            : keyword == "oneOf" ? successes.count == 1 : !successes.isEmpty
          frame.units.append(
            frame.unit(
              keyword, valid: valid,
              message: keyword == "oneOf"
                ? "Expected exactly one matching branch" : "No applicable branch combination",
              children: results.map(\.unit)))
          if valid { frame.absorb(successes) }
        }
      }
    }
    if frame.enabled("not"), let child = request(frame, tokens: ["not"]) {
      sequence.append { evaluator in
        evaluator.batch([child]) { _, results in
          frame.units.append(
            frame.unit(
              "not", valid: !results[0].valid, message: "Negated schema matched",
              children: [results[0].unit]))
        }
      }
    }
    if frame.enabled("if"), let condition = request(frame, tokens: ["if"]) {
      sequence.append { evaluator in
        evaluator.batch([condition]) { evaluator, results in
          let result = results[0]
          frame.units.append(frame.unit("if", children: [result.unit]))
          if result.valid { frame.absorb([result]) }
          let branch = result.valid ? "then" : "else"
          if let child = evaluator.request(frame, tokens: [branch]) {
            evaluator.batch([child]) { _, selected in
              frame.units.append(
                frame.unit(branch, valid: selected[0].valid, children: [selected[0].unit]))
              if selected[0].valid { frame.absorb(selected) }
            }
          }
        }
      }
    }
    enqueue(sequence)
  }

  private mutating func objects(_ frame: EvaluationFrame) {
    guard let object = frame.value.objectValue else { return }
    let definition = frame.node.value
    for keyword in ["minProperties", "maxProperties"] where frame.enabled(keyword) {
      if let limit = definition[keyword]?.numberValue {
        frame.units.append(
          frame.unit(
            keyword,
            valid: keyword == "minProperties"
              ? JSONNumber(object.count) >= limit : JSONNumber(object.count) <= limit,
            message: "Object fails \(keyword)"))
      }
    }
    if frame.enabled("required"), let names = definition["required"]?.arrayValue {
      let absent = names.compactMap(\.stringValue).filter { object[$0] == nil }
      frame.units.append(
        frame.unit(
          "required", valid: absent.isEmpty,
          message: "Missing members: " + absent.joined(separator: ", ")))
    }
    var sequence: [EvaluationAction] = []
    for keyword in ["dependencies", "dependentRequired", "dependentSchemas"]
    where frame.enabled(keyword) {
      if keyword != "dependencies" && !frame.node.dialect.modern { continue }
      guard let dependencies = definition[keyword]?.objectValue else { continue }
      sequence.append { evaluator in
        var children: [ValidationUnit] = []
        var slots: [Int] = []
        var requests: [EvaluationRequest] = []
        for (name, dependency) in dependencies where object[name] != nil {
          if let list = dependency.arrayValue {
            children.append(
              frame.unit(
                keyword, valid: list.compactMap(\.stringValue).allSatisfy { object[$0] != nil },
                message: "Missing dependencies of \(name)"))
          } else if let child = evaluator.request(frame, tokens: [keyword, name]) {
            slots.append(children.count)
            children.append(frame.unit(keyword))
            requests.append(child)
          }
        }
        evaluator.batch(requests) { _, results in
          for (slot, result) in zip(slots, results) { children[slot] = result.unit }
          let valid = children.allSatisfy(\.valid)
          frame.units.append(frame.unit(keyword, valid: valid, children: children))
          if valid { frame.absorb(results.filter(\.valid)) }
        }
      }
    }
    for keyword in ["properties", "patternProperties"] where frame.enabled(keyword) {
      guard let map = definition[keyword]?.objectValue else { continue }
      sequence.append { evaluator in
        var requests: [EvaluationRequest] = []
        var names: [String] = []
        for (name, member) in object {
          for (pattern, _) in map
          where keyword == "properties"
            ? name.utf8.elementsEqual(pattern.utf8)
            : frame.node.patterns[Data(pattern.utf8)]?.matches(name) == true
          {
            frame.matched.insert(frame.identity(name))
            names.append(name)
            if let child = evaluator.request(
              frame, tokens: [keyword, pattern], value: member,
              instance: frame.instance.appending(name))
            {
              requests.append(child)
            }
          }
        }
        evaluator.batch(requests) { _, results in
          let valid = results.allSatisfy(\.valid)
          frame.units.append(
            frame.unit(
              keyword, valid: valid, annotation: .array(names.map(JSONValue.string)),
              children: results.map(\.unit)))
          if valid { frame.properties.formUnion(names.map(frame.identity)) }
        }
      }
    }
    if frame.enabled("additionalProperties"), frame.child(["additionalProperties"]) != nil {
      sequence.append { evaluator in
        let names = object.keys.filter { !frame.matched.contains(frame.identity($0)) }
        let requests = names.compactMap {
          evaluator.request(
            frame, tokens: ["additionalProperties"], value: object[$0]!,
            instance: frame.instance.appending($0))
        }
        evaluator.batch(requests) { _, results in
          let valid = results.allSatisfy(\.valid)
          frame.units.append(
            frame.unit(
              "additionalProperties", valid: valid, annotation: .array(names.map(JSONValue.string)),
              children: results.map(\.unit)))
          if valid { frame.properties.formUnion(names.map(frame.identity)) }
        }
      }
    }
    if frame.enabled("propertyNames"), frame.child(["propertyNames"]) != nil {
      sequence.append { evaluator in
        let requests = object.keys.compactMap {
          evaluator.request(frame, tokens: ["propertyNames"], value: .string($0))
        }
        evaluator.batch(requests) { _, results in
          frame.units.append(
            frame.unit(
              "propertyNames", valid: results.allSatisfy(\.valid), children: results.map(\.unit)))
        }
      }
    }
    enqueue(sequence)
  }

  private mutating func arrays(_ frame: EvaluationFrame) {
    guard let array = frame.value.arrayValue else { return }
    let definition = frame.node.value
    for keyword in ["minItems", "maxItems"] where frame.enabled(keyword) {
      if let limit = definition[keyword]?.numberValue {
        frame.units.append(
          frame.unit(
            keyword,
            valid: keyword == "minItems"
              ? JSONNumber(array.count) >= limit : JSONNumber(array.count) <= limit,
            message: "Array fails \(keyword)"))
      }
    }
    if frame.enabled("uniqueItems"), definition["uniqueItems"]?.boolValue == true {
      let unique = array.indices.allSatisfy { !array[..<$0].contains(array[$0]) }
      frame.units.append(
        frame.unit("uniqueItems", valid: unique, message: "Array contains equal items"))
    }
    var sequence: [EvaluationAction] = []
    let prefixKeyword = frame.node.dialect == .draft2020 ? "prefixItems" : "items"
    let tuple = frame.enabled(prefixKeyword) ? definition[prefixKeyword]?.arrayValue : nil
    if let tuple {
      let indexes = Array(0..<min(tuple.count, array.count))
      sequence.append { evaluator in
        let requests = indexes.compactMap {
          evaluator.request(
            frame, tokens: [prefixKeyword, String($0)], value: array[$0],
            instance: frame.instance.appending(String($0)))
        }
        evaluator.batch(requests) { _, results in
          let valid = results.allSatisfy(\.valid)
          let annotation: JSONValue =
            frame.node.dialect == .draft2020
            ? (array.count <= tuple.count ? .bool(true) : .number(JSONNumber(indexes.last ?? -1)))
            : .array(indexes.map { .number(JSONNumber($0)) })
          frame.units.append(
            frame.unit(
              prefixKeyword, valid: valid, annotation: annotation, children: results.map(\.unit)))
          if valid { frame.items.formUnion(indexes) }
        }
      }
    }
    let itemKeyword = frame.node.dialect == .draft2020 || tuple == nil ? "items" : "additionalItems"
    if frame.enabled(itemKeyword), frame.child([itemKeyword]) != nil {
      let indexes = Array(min(tuple?.count ?? 0, array.count)..<array.count)
      sequence.append { evaluator in
        let requests = indexes.compactMap {
          evaluator.request(
            frame, tokens: [itemKeyword], value: array[$0],
            instance: frame.instance.appending(String($0)))
        }
        evaluator.batch(requests) { _, results in
          let valid = results.allSatisfy(\.valid)
          frame.units.append(
            frame.unit(
              itemKeyword, valid: valid, annotation: .bool(true), children: results.map(\.unit)))
          if valid { frame.items.formUnion(indexes) }
        }
      }
    }
    if frame.enabled("contains"), frame.child(["contains"]) != nil {
      sequence.append { evaluator in
        let requests = array.indices.compactMap {
          evaluator.request(
            frame, tokens: ["contains"], value: array[$0],
            instance: frame.instance.appending(String($0)))
        }
        evaluator.batch(requests) { _, results in
          let matches = results.indices.filter { results[$0].valid }
          let minimum =
            frame.node.dialect.modern && frame.enabled("minContains")
            ? definition["minContains"]?.numberValue ?? JSONNumber(1) : JSONNumber(1)
          let maximum =
            frame.node.dialect.modern && frame.enabled("maxContains")
            ? definition["maxContains"]?.numberValue : nil
          let valid =
            JSONNumber(matches.count) >= minimum
            && (maximum == nil || JSONNumber(matches.count) <= maximum!)
          frame.units.append(
            frame.unit(
              "contains", valid: valid, message: "Array has \(matches.count) matching items",
              annotation: .array(matches.map { .number(JSONNumber($0)) }),
              children: results.map(\.unit)))
          if valid && frame.node.dialect == .draft2020 { frame.items.formUnion(matches) }
        }
      }
    }
    enqueue(sequence)
  }
  private mutating func customKeywords(_ frame: EvaluationFrame) {
    let node = frame.node
    let definition = frame.node.value
    let value = frame.value
    for vocabulary in compiled.custom.values.sorted(by: { $0.uri < $1.uri })
    where node.active == nil || node.active!.contains(vocabulary.uri) {
      for keyword in vocabulary.keywords {
        if let parameter = definition[keyword.name] {
          let result = keyword.evaluate(parameter, value)
          frame.units.append(
            frame.unit(
              keyword.name, valid: result.valid, message: result.message ?? "Custom keyword failed",
              annotation: result.annotation))
          if result.valid {
            frame.properties.formUnion(result.evaluatedProperties.map(frame.identity))
            frame.items.formUnion(result.evaluatedItems)
          }
        }
      }
    }
  }

  private mutating func unevaluated(_ frame: EvaluationFrame) {
    guard frame.node.dialect.modern else { return }
    var sequence: [EvaluationAction] = []
    if frame.enabled("unevaluatedProperties"), let object = frame.value.objectValue,
      frame.child(["unevaluatedProperties"]) != nil
    {
      sequence.append { evaluator in
        let names = object.keys.filter { !frame.properties.contains(frame.identity($0)) }
        let requests = names.compactMap {
          evaluator.request(
            frame, tokens: ["unevaluatedProperties"], value: object[$0]!,
            instance: frame.instance.appending($0))
        }
        evaluator.batch(requests) { _, results in
          let valid = results.allSatisfy(\.valid)
          frame.units.append(
            frame.unit(
              "unevaluatedProperties", valid: valid,
              annotation: .array(names.map(JSONValue.string)), children: results.map(\.unit)))
          if valid { frame.properties.formUnion(names.map(frame.identity)) }
        }
      }
    }
    if frame.enabled("unevaluatedItems"), let array = frame.value.arrayValue,
      frame.child(["unevaluatedItems"]) != nil
    {
      sequence.append { evaluator in
        let indexes = array.indices.filter { !frame.items.contains($0) }
        let requests = indexes.compactMap {
          evaluator.request(
            frame, tokens: ["unevaluatedItems"], value: array[$0],
            instance: frame.instance.appending(String($0)))
        }
        evaluator.batch(requests) { _, results in
          let valid = results.allSatisfy(\.valid)
          frame.units.append(
            frame.unit(
              "unevaluatedItems", valid: valid, annotation: .bool(true),
              children: results.map(\.unit)))
          if valid { frame.items.formUnion(indexes) }
        }
      }
    }
    enqueue(sequence)
  }
  private mutating func metadata(_ frame: EvaluationFrame) {
    let definition = frame.node.value
    for keyword in [
      "title", "description", "default", "examples", "deprecated", "readOnly", "writeOnly",
    ] where frame.enabled(keyword) {
      if let annotation = definition[keyword] {
        frame.units.append(frame.unit(keyword, annotation: annotation))
      }
    }
    if frame.node.dialect.modern {
      let custom = Set(
        compiled.custom.values.filter {
          frame.node.active == nil || frame.node.active!.contains($0.uri)
        }.flatMap { $0.keywords.map { Data($0.name.utf8) } })
      for (keyword, annotation) in definition.objectValue ?? JSONObject()
      where
        (!recognizedKeywords.contains(keyword)
        || (!keyword.hasPrefix("$") && keyword != "definitions" && !frame.enabled(keyword)))
        && !custom.contains(Data(keyword.utf8))
      {
        frame.units.append(frame.unit(keyword, annotation: annotation))
      }
    }
  }
}

private final class EvaluationFrame {
  let node: SchemaNode
  let value: JSONValue
  let instance: JSONPointer
  let path: JSONPointer
  let scopes: [String]
  var units: [ValidationUnit] = []
  var properties: Set<Data> = []
  var matched: Set<Data> = []
  var items: Set<Int> = []
  init(
    node: SchemaNode, value: JSONValue, instance: JSONPointer, path: JSONPointer, scopes: [String]
  ) {
    self.node = node
    self.value = value
    self.instance = instance
    self.path = path
    self.scopes = scopes
  }
  func unit(
    _ keyword: String, valid: Bool = true, message: String? = nil, annotation: JSONValue? = nil,
    children: [ValidationUnit] = []
  ) -> ValidationUnit {
    ValidationUnit(
      valid: valid, keywordLocation: path.appending(keyword),
      absoluteKeywordLocation: node.locations[Data(keyword.utf8)]
        ?? URI.location(node.resource, node.pointer.appending(keyword)), instanceLocation: instance,
      error: valid ? nil : message, annotation: valid ? annotation : nil, children: children)
  }
  func enabled(_ keyword: String) -> Bool {
    keywordEnabled(keyword, active: node.active, dialect: node.dialect)
  }
  func child(_ tokens: [String]) -> Int? { node.children[JSONPointer(tokens: tokens)] }
  func identity(_ name: String) -> Data { Data(name.utf8) }
  func absorb(_ results: [Evaluation]) {
    for result in results {
      properties.formUnion(result.properties)
      items.formUnion(result.items)
    }
  }
  func result() -> Evaluation {
    let valid = units.filter { $0.keywordLocation != path.appending("if") }.allSatisfy(\.valid)
    let tree = ValidationUnit(
      valid: valid, keywordLocation: path,
      absoluteKeywordLocation: node.locations[Data()] ?? URI.location(node.resource, node.pointer),
      instanceLocation: instance, error: nil, annotation: nil, children: units)
    return Evaluation(properties: valid ? properties : [], items: valid ? items : [], unit: tree)
  }
}

private let recognizedKeywords: Set<String> = [
  "$schema", "$id", "$ref", "$anchor", "$dynamicRef", "$dynamicAnchor", "$recursiveRef",
  "$recursiveAnchor", "$vocabulary", "$comment", "$defs", "definitions", "id",
  "type", "enum", "const", "minimum", "maximum", "exclusiveMinimum", "exclusiveMaximum",
  "multipleOf", "minLength", "maxLength", "pattern", "format",
  "minItems", "maxItems", "uniqueItems", "items", "additionalItems", "prefixItems", "contains",
  "minContains", "maxContains", "unevaluatedItems",
  "properties", "patternProperties", "additionalProperties", "propertyNames", "required",
  "minProperties", "maxProperties", "dependencies", "dependentRequired", "dependentSchemas",
  "unevaluatedProperties",
  "allOf", "anyOf", "oneOf", "not", "if", "then", "else", "contentEncoding", "contentMediaType",
  "contentSchema", "title", "description", "default", "examples", "deprecated", "readOnly",
  "writeOnly",
]

func keywordEnabled(_ name: String, active: Set<String>?, dialect: Dialect) -> Bool {
  guard let active, dialect.modern else { return true }
  let group: String
  if [
    "type", "enum", "const", "minimum", "maximum", "exclusiveMinimum", "exclusiveMaximum",
    "multipleOf", "minLength", "maxLength", "pattern", "minItems", "maxItems", "uniqueItems",
    "required", "minProperties", "maxProperties", "dependentRequired", "minContains", "maxContains",
  ].contains(name) {
    group = "validation"
  } else if name.hasPrefix("unevaluated") {
    group = dialect == .draft2019 ? "applicator" : "unevaluated"
  } else if name == "format" {
    return active.contains {
      $0.hasSuffix("/format") || $0.hasSuffix("/format-annotation")
        || $0.hasSuffix("/format-assertion")
    }
  } else if name.hasPrefix("content") {
    group = "content"
  } else if ["title", "description", "default", "examples", "deprecated", "readOnly", "writeOnly"]
    .contains(name)
  {
    group = "meta-data"
  } else {
    group = "applicator"
  }
  return active.contains { $0.hasSuffix("/vocab/" + group) }
}
