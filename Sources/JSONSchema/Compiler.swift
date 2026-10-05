// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2026 Xudong Xu

import Foundation
import JSONValue

struct SchemaNode: Sendable {
  let value: JSONValue
  let dialect: Dialect
  let base: String
  let resource: String
  let pointer: JSONPointer
  let physical: JSONPointer
  let document: String
  let active: Set<String>?
  var children: [JSONPointer: Int] = [:]
  var references: [String: Int] = [:]
  var patterns: [Data: ECMARegularExpression] = [:]
  var locations: [Data: String] = [:]
  var dynamicName: String?
}

/// Compiles all reachable schema resources into an immutable graph.
public struct SchemaCompiler: Sendable {
  public var dialect: Dialect
  public var registry: SchemaRegistry
  public var options: ValidationOptions
  public init(
    dialect: Dialect = .draft2020, registry: SchemaRegistry = .bundled,
    options: ValidationOptions = .init()
  ) {
    self.dialect = dialect
    self.registry = registry
    self.options = options
  }
  public func compile(_ schema: JSONValue, baseURI: String = "urn:json-schema:document") throws
    -> CompiledSchema
  {
    var compilation = Compilation(registry: registry, options: options)
    let root = try compilation.addDocument(schema, uri: baseURI, defaultDialect: dialect)
    try compilation.link()
    return CompiledSchema(
      schema: schema, nodes: compilation.nodes, root: root, anchors: compilation.dynamicAnchors,
      options: options, custom: registry.vocabularies, registry: registry)
  }
}

struct Compilation {
  let registry: SchemaRegistry
  let options: ValidationOptions
  var nodes: [SchemaNode] = []
  var addresses: [String: Int] = [:]
  var loaded: Set<String> = []
  var dynamicAnchors: [String: [String: Int]] = [:]

  mutating func addDocument(_ value: JSONValue, uri: String, defaultDialect: Dialect) throws -> Int
  {
    let canonical = URI.document(uri)
    if let old = addresses[canonical] { return old }
    loaded.insert(canonical)
    let start = nodes.count
    let root = try walk(
      value, document: canonical, physical: .init(), base: canonical, resource: canonical,
      pointer: .init(), dialect: defaultDialect, active: nil)
    addresses[canonical] = root
    for index in start..<nodes.count {
      addresses[URI.location(nodes[root].resource, nodes[index].physical)] = index
    }
    return root
  }

  mutating func walk(
    _ value: JSONValue, document: String, physical: JSONPointer, base: String, resource: String,
    pointer: JSONPointer, dialect inherited: Dialect, active inheritedActive: Set<String>?
  ) throws -> Int {
    let root = try indexNode(
      value, document: document, physical: physical, base: base, resource: resource,
      pointer: pointer, dialect: inherited, active: inheritedActive)
    var frames = [(index: root, children: successors(root), next: 0)]
    while let frame = frames.last {
      if frame.next == frame.children.count {
        frames.removeLast()
        let node = nodes[frame.index]
        for descendant in (frame.index + 1)..<nodes.count {
          let suffix = nodes[descendant].physical.tokens.dropFirst(node.physical.tokens.count)
          addresses[
            URI.location(node.resource, JSONPointer(tokens: node.pointer.tokens + suffix))] =
            descendant
        }
        continue
      }
      frames[frames.count - 1].next += 1
      let (tokens, child) = frame.children[frame.next]
      let node = nodes[frame.index]
      let index = try indexNode(
        child, document: document, physical: JSONPointer(tokens: node.physical.tokens + tokens),
        base: node.base, resource: node.resource,
        pointer: JSONPointer(tokens: node.pointer.tokens + tokens), dialect: node.dialect,
        active: node.active)
      nodes[frame.index].children[JSONPointer(tokens: tokens)] = index
      frames.append((index: index, children: successors(index), next: 0))
    }
    return root
  }

  private func successors(_ index: Int) -> [([String], JSONValue)] {
    let node = nodes[index]
    if !node.dialect.modern && node.value["$ref"] != nil { return [] }
    return (node.value.objectValue ?? JSONObject()).flatMap { keyword, value in
      if keyword == "$defs" || keyword == "definitions"
        || keywordEnabled(keyword, active: node.active, dialect: node.dialect)
      {
        return subschemas(keyword, value: value, dialect: node.dialect)
      }
      return []
    }
  }

  private mutating func indexNode(
    _ value: JSONValue, document: String, physical: JSONPointer, base: String, resource: String,
    pointer: JSONPointer, dialect inherited: Dialect, active inheritedActive: Set<String>?
  ) throws -> Int {
    guard value.objectValue != nil || value.boolValue != nil else {
      throw SchemaError.invalidSchema(physical.description + " must be an object or boolean")
    }
    var dialect = inherited
    var active = inheritedActive
    var effective = base
    var canonical = resource
    var relative = pointer
    if let declaration = value["$schema"]?.stringValue {
      if let recognized = Dialect(uri: declaration) {
        dialect = recognized
        active = nil
      } else if let meta = registry.documents[URI.document(declaration)] {
        if let standard = meta["$schema"]?.stringValue, let recognized = Dialect(uri: standard) {
          dialect = recognized
        }
        active = try vocabulary(meta["$vocabulary"], dialect: dialect)
      } else {
        throw SchemaError.unknownDialect(declaration)
      }
    }
    let legacyRef = !dialect.modern && value["$ref"] != nil
    let index = nodes.count
    if !legacyRef, let identifier = value[dialect.identifier]?.stringValue {
      effective = try URI.resolve(identifier, against: base)
      if URI.fragment(effective).isEmpty {
        canonical = URI.document(effective)
        relative = .init()
        if let existing = addresses[canonical], existing != index {
          throw SchemaError.duplicateIdentifier(canonical)
        }
        addresses[canonical] = index
      } else {
        addresses[effective] = index
      }
    }
    if dialect.modern, value["$vocabulary"] != nil {
      _ = try vocabulary(value["$vocabulary"], dialect: dialect)
    }
    var node = SchemaNode(
      value: value, dialect: dialect, base: effective, resource: canonical, pointer: relative,
      physical: physical, document: document, active: active)
    nodes.append(node)
    addresses[URI.location(document, physical)] = index
    addresses[URI.location(canonical, relative)] = index
    if physical.tokens.isEmpty { addresses[document] = index }
    if !legacyRef {
      for anchor in ["$anchor", "$dynamicAnchor"] where dialect.modern {
        if let name = value[anchor]?.stringValue {
          addresses[canonical + "#" + name] = index
          if anchor == "$dynamicAnchor" && dialect == .draft2020 {
            dynamicAnchors[canonical, default: [:]][name] = index
            node.dynamicName = name
          }
        }
      }
      if dialect == .draft2019 && value["$recursiveAnchor"]?.boolValue == true {
        dynamicAnchors[canonical, default: [:]][""] = index
        node.dynamicName = ""
      }
      if keywordEnabled("pattern", active: active, dialect: dialect),
        let pattern = value["pattern"]?.stringValue
      {
        node.patterns[Data("pattern".utf8)] = try ECMARegularExpression(pattern)
      }
      if keywordEnabled("patternProperties", active: active, dialect: dialect) {
        for (pattern, _) in value["patternProperties"]?.objectValue ?? JSONObject() {
          node.patterns[Data(pattern.utf8)] = try ECMARegularExpression(pattern)
        }
      }
    }
    node.locations[Data()] = URI.location(canonical, relative)
    for keyword in value.objectValue?.keys ?? [] {
      node.locations[Data(keyword.utf8)] = URI.location(canonical, relative.appending(keyword))
    }
    nodes[index] = node
    return index
  }

  func vocabulary(_ value: JSONValue?, dialect: Dialect) throws -> Set<String>? {
    guard let value else { return nil }
    guard let map = value.objectValue else {
      throw SchemaError.invalidSchema("$vocabulary must be an object")
    }
    var result = Set<String>()
    for (uri, required) in map {
      guard required.boolValue != nil else {
        throw SchemaError.invalidSchema("Vocabulary requirements must be boolean")
      }
      if registry.vocabularies[uri] != nil || builtinVocabulary(uri) {
        result.insert(uri)
      } else if required.boolValue == true {
        throw SchemaError.requiredVocabulary(uri)
      }
    }
    return result
  }

  mutating func link() throws {
    var referenceIndex = 0
    while referenceIndex < nodes.count {
      let node = nodes[referenceIndex]
      let keywords =
        ["$ref"]
        + (node.dialect == .draft2020
          ? ["$dynamicRef"] : node.dialect == .draft2019 ? ["$recursiveRef"] : [])
      for keyword in keywords {
        guard let ref = node.value[keyword]?.stringValue else { continue }
        let absolute = try URI.resolve(ref, against: node.base)
        let document = URI.document(absolute)
        let fragment = URI.fragment(absolute)
        if addresses[document] == nil, let remote = registry.documents[document] {
          _ = try addDocument(remote, uri: document, defaultDialect: node.dialect)
        }
        let key =
          fragment.isEmpty
          ? document
          : document + "#" + fragment.addingPercentEncoding(
            withAllowedCharacters: .urlFragmentAllowed)!
        var target = addresses[key] ?? addresses[absolute] ?? addresses[document + "#" + fragment]
        if target == nil, fragment.hasPrefix("/"), let root = addresses[document] {
          let pointer = try JSONPointer(fragment)
          let value = try pointer.resolve(in: nodes[root].value)
          target = try walk(
            value, document: nodes[root].document,
            physical: JSONPointer(tokens: nodes[root].physical.tokens + pointer.tokens),
            base: nodes[root].base, resource: nodes[root].resource, pointer: pointer,
            dialect: nodes[root].dialect, active: nodes[root].active)
        }
        guard let target else { throw SchemaError.unresolvedReference(absolute) }
        nodes[referenceIndex].references[keyword] = target
      }
      referenceIndex += 1
    }
  }
}

func builtinVocabulary(_ uri: String) -> Bool {
  let base = "https://json-schema.org/draft/"
  return ["2020-12", "2019-09"].contains { draft in
    [
      "core", "applicator", "unevaluated", "validation", "meta-data", "format", "format-annotation",
      "format-assertion", "content",
    ].contains { uri == base + draft + "/vocab/" + $0 }
  }
}

func subschemas(_ keyword: String, value: JSONValue, dialect: Dialect) -> [([String], JSONValue)] {
  let maps =
    ["properties", "patternProperties", "$defs", "definitions"]
    + (dialect.modern ? ["dependentSchemas"] : [])
  if maps.contains(keyword) {
    return (value.objectValue ?? JSONObject()).map { ([keyword, $0.0], $0.1) }
  }
  if ["allOf", "anyOf", "oneOf"].contains(keyword)
    || (keyword == "prefixItems" && dialect == .draft2020)
  {
    return (value.arrayValue ?? []).enumerated().map { ([keyword, String($0.offset)], $0.element) }
  }
  if keyword == "items", let list = value.arrayValue, dialect != .draft2020 {
    return list.enumerated().map { ([keyword, String($0.offset)], $0.element) }
  }
  if keyword == "dependencies" {
    return (value.objectValue ?? JSONObject()).compactMap {
      $0.1.arrayValue == nil ? ([keyword, $0.0], $0.1) : nil
    }
  }
  var singles = ["not", "items", "additionalProperties"]
  if dialect != .draft2020 { singles.append("additionalItems") }
  if dialect != .draft4 { singles += ["contains", "propertyNames"] }
  if [.draft2020, .draft2019, .draft7].contains(dialect) {
    singles += ["if", "then", "else", "contentSchema"]
  }
  if dialect.modern { singles += ["unevaluatedProperties", "unevaluatedItems"] }
  return singles.contains(keyword) ? [([keyword], value)] : []
}
