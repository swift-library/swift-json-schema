// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2026 Xudong Xu

import Foundation
import JSONValue

/// Supported JSON Schema drafts, identified by their canonical metaschema URIs.
public enum Dialect: String, Sendable, CaseIterable {
  case draft2020 = "https://json-schema.org/draft/2020-12/schema"
  case draft2019 = "https://json-schema.org/draft/2019-09/schema"
  case draft7 = "http://json-schema.org/draft-07/schema"
  case draft6 = "http://json-schema.org/draft-06/schema"
  case draft4 = "http://json-schema.org/draft-04/schema"
  /// Recognizes a metaschema URI after removing its fragment; returns `nil` for unknown URIs.
  public init?(uri: String) { self.init(rawValue: URI.document(uri)) }
  var modern: Bool { self == .draft2020 || self == .draft2019 }
  var identifier: String { self == .draft4 ? "id" : "$id" }
  /// The corresponding draft directory name in the JSON Schema Test Suite.
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

/// Compilation and reference-resolution failures; instance validation failures are returned as results.
public enum SchemaError: Error, Sendable, CustomStringConvertible {
  /// The schema structure or a compiled keyword is invalid, with an explanatory message.
  case invalidSchema(String)
  /// A `$schema` URI identifies neither a built-in dialect nor a registered metaschema.
  case unknownDialect(String)
  /// A required vocabulary URI is unsupported and has no registered implementation.
  case requiredVocabulary(String)
  /// The reference cannot be resolved from the registry or allowed resolver.
  case unresolvedReference(String)
  /// Distinct schema resources declare the same identifier.
  case duplicateIdentifier(String)
  /// Remote resolution reaches the document limit or retries an already fetched document.
  case resolverLimit
  /// A human-readable explanation containing the relevant schema message or URI.
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

/// Options captured at compilation and applied independently to each validation call.
public struct ValidationOptions: Sendable {
  /// Whether supported `format` values are asserted; defaults to `false`.
  public var assertFormats: Bool
  /// Whether content keywords are evaluated; defaults to `false`.
  public var evaluateContent: Bool
  /// The maximum active evaluation depth; reaching the limit produces an invalid result.
  /// The default is 512; nonpositive values reject evaluation at the root.
  public var maximumDepth: Int
  /// Stores format, content and depth options without clamping the supplied depth.
  public init(assertFormats: Bool = false, evaluateContent: Bool = false, maximumDepth: Int = 512) {
    self.assertFormats = assertFormats
    self.evaluateContent = evaluateContent
    self.maximumDepth = maximumDepth
  }
}

/// Results a custom keyword can contribute at its current instance location.
public struct KeywordResult: Sendable {
  /// Whether the custom keyword accepts this instance.
  public var valid: Bool
  /// An optional annotation contributed at the keyword location.
  public var annotation: JSONValue?
  /// Object property names accounted for by this keyword when it succeeds.
  public var evaluatedProperties: Set<String>
  /// Zero-based array indexes accounted for by this keyword when it succeeds.
  public var evaluatedItems: Set<Int>
  /// An optional failure explanation used when the keyword rejects the instance.
  public var message: String?
  /// Creates a keyword result; annotations and evaluated locations default to empty.
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

/// A custom vocabulary keyword evaluated synchronously at an instance location.
public struct SchemaKeyword: Sendable {
  /// The schema object member that activates this keyword.
  public let name: String
  /// Receives the keyword schema value first and the current instance second.
  /// The sendable closure can run concurrently in independent validations.
  public let evaluate: @Sendable (JSONValue, JSONValue) -> KeywordResult
  /// Associates a keyword name with its synchronous evaluation closure.
  public init(_ name: String, evaluate: @escaping @Sendable (JSONValue, JSONValue) -> KeywordResult)
  {
    self.name = name
    self.evaluate = evaluate
  }
}

/// A URI-identified collection of custom keywords for registry-backed compilation.
public struct SchemaVocabulary: Sendable {
  /// The vocabulary identifier used in `$vocabulary` declarations.
  public let uri: String
  /// The custom keyword implementations supplied by this vocabulary.
  public let keywords: [SchemaKeyword]
  /// Stores a vocabulary identifier and its keyword implementations.
  public init(uri: String, keywords: [SchemaKeyword]) {
    self.uri = uri
    self.keywords = keywords
  }
}

/// A value snapshot. Registration never changes already compiled validators.
public struct SchemaRegistry: Sendable {
  /// Registered schema documents keyed by URI without fragments.
  public private(set) var documents: [String: JSONValue] = [:]
  /// Registered custom vocabularies keyed by their declared URI.
  public private(set) var vocabularies: [String: SchemaVocabulary] = [:]
  /// Creates an empty registry; use `bundled` to include standard metaschemas.
  public init() {}
  /// Registers or replaces a document after removing the URI fragment.
  public mutating func register(_ schema: JSONValue, at uri: String) {
    documents[URI.document(uri)] = schema
  }
  /// Registers or replaces a custom vocabulary under its exact URI.
  public mutating func register(_ vocabulary: SchemaVocabulary) {
    vocabularies[vocabulary.uri] = vocabulary
  }
  /// A registry containing the package's bundled standard metaschemas.
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
