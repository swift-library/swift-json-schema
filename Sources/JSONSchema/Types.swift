// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2026 Xudong Xu

import Foundation
import JSONValue

public enum Dialect: String, Sendable, CaseIterable {
  case draft2020 = "https://json-schema.org/draft/2020-12/schema"
  case draft2019 = "https://json-schema.org/draft/2019-09/schema"
  case draft7 = "http://json-schema.org/draft-07/schema"
  case draft6 = "http://json-schema.org/draft-06/schema"
  case draft4 = "http://json-schema.org/draft-04/schema"
  public init?(uri: String) { self.init(rawValue: URI.document(uri)) }
  var modern: Bool { self == .draft2020 || self == .draft2019 }
  var identifier: String { self == .draft4 ? "id" : "$id" }
  public var testDirectory: String {
    switch self {
    case .draft2020: "draft2020-12"
    case .draft2019: "draft2019-09"
    case .draft7: "draft7"
    case .draft6: "draft6"
    case .draft4: "draft4"
    }
  }
}

public enum SchemaError: Error, Sendable, CustomStringConvertible {
  case invalidSchema(String)
  case unknownDialect(String)
  case requiredVocabulary(String)
  case unresolvedReference(String)
  case duplicateIdentifier(String)
  case resolverLimit
  public var description: String {
    switch self {
    case .invalidSchema(let s): "Invalid schema: \(s)"
    case .unknownDialect(let s): "Unknown dialect: \(s)"
    case .requiredVocabulary(let s): "Unsupported required vocabulary: \(s)"
    case .unresolvedReference(let s): "Unresolved reference: \(s)"
    case .duplicateIdentifier(let s): "Duplicate identifier: \(s)"
    case .resolverLimit: "Remote resolution limit exceeded"
    }
  }
}

public struct ValidationOptions: Sendable {
  public var assertFormats: Bool
  public var evaluateContent: Bool
  public var maximumDepth: Int
  public init(assertFormats: Bool = false, evaluateContent: Bool = false, maximumDepth: Int = 512) {
    self.assertFormats = assertFormats
    self.evaluateContent = evaluateContent
    self.maximumDepth = maximumDepth
  }
}

/// Results a custom keyword can contribute at its current instance location.
public struct KeywordResult: Sendable {
  public var valid: Bool
  public var annotation: JSONValue?
  public var evaluatedProperties: Set<String>
  public var evaluatedItems: Set<Int>
  public var message: String?
  public init(
    valid: Bool, annotation: JSONValue? = nil, evaluatedProperties: Set<String> = [],
    evaluatedItems: Set<Int> = [], message: String? = nil
  ) {
    self.valid = valid
    self.annotation = annotation
    self.evaluatedProperties = evaluatedProperties
    self.evaluatedItems = evaluatedItems
    self.message = message
  }
}

public struct SchemaKeyword: Sendable {
  public let name: String
  public let evaluate: @Sendable (JSONValue, JSONValue) -> KeywordResult
  public init(_ name: String, evaluate: @escaping @Sendable (JSONValue, JSONValue) -> KeywordResult)
  {
    self.name = name
    self.evaluate = evaluate
  }
}

public struct SchemaVocabulary: Sendable {
  public let uri: String
  public let keywords: [SchemaKeyword]
  public init(uri: String, keywords: [SchemaKeyword]) {
    self.uri = uri
    self.keywords = keywords
  }
}

/// A value snapshot. Registration never changes already compiled validators.
public struct SchemaRegistry: Sendable {
  public private(set) var documents: [String: JSONValue] = [:]
  public private(set) var vocabularies: [String: SchemaVocabulary] = [:]
  public init() {}
  public mutating func register(_ schema: JSONValue, at uri: String) {
    documents[URI.document(uri)] = schema
  }
  public mutating func register(_ vocabulary: SchemaVocabulary) {
    vocabularies[vocabulary.uri] = vocabulary
  }
  public static let bundled: Self = {
    var registry = Self()
    let directory = Bundle.module.resourceURL!.appendingPathComponent("Metaschemas")
    let manifest = try! JSONValue.parse(
      Data(contentsOf: directory.appendingPathComponent("manifest.json")))
    for (uri, entry) in manifest.objectValue! {
      let data = try! Data(
        contentsOf: directory.appendingPathComponent(entry["file"]!.stringValue!))
      registry.register(try! JSONValue.parse(data), at: uri)
    }
    return registry
  }()
}

enum URI {
  static func document(_ uri: String) -> String {
    String(uri.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)[0])
  }
  static func fragment(_ uri: String) -> String {
    let pieces = uri.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
    return pieces.count == 2 ? String(pieces[1]).removingPercentEncoding ?? String(pieces[1]) : ""
  }
  static func resolve(_ reference: String, against base: String) throws -> String {
    if reference.hasPrefix("#") { return document(base) + reference }
    guard let baseURL = URL(string: base),
      let result = URL(string: reference, relativeTo: baseURL)?.absoluteURL
    else { throw SchemaError.unresolvedReference(reference) }
    return result.standardized.absoluteString
  }
  static func location(_ base: String, _ pointer: JSONPointer) -> String {
    document(base) + pointer.fragment
  }
}
