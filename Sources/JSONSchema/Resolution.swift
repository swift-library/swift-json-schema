// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2026 Xudong Xu

import Foundation
import JSONValue

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

public enum ResolverPolicy: Sendable {
  case offline
  case https(hosts: Set<String>, maximumDocuments: Int = 32)
}
public struct SchemaResolver: Sendable {
  public let resolve: @Sendable (String) async throws -> JSONValue
  public init(resolve: @escaping @Sendable (String) async throws -> JSONValue) {
    self.resolve = resolve
  }
  public static let urlSession = Self { uri in
    guard let url = URL(string: uri), url.scheme == "https", let host = url.host else {
      throw SchemaError.unresolvedReference(uri)
    }
    let session = URLSession(
      configuration: .ephemeral, delegate: HTTPSRedirectGuard(host: host), delegateQueue: nil)
    defer { session.invalidateAndCancel() }
    let (data, response) = try await session.data(from: url)
    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
      data.count <= 8_388_608
    else { throw SchemaError.unresolvedReference(uri) }
    return try JSONValue.parse(data)
  }
}
extension SchemaCompiler {
  public func compile(
    _ schema: JSONValue, baseURI: String = "urn:json-schema:document", policy: ResolverPolicy,
    resolver: SchemaResolver = .urlSession
  ) async throws -> CompiledSchema {
    var candidate = self
    var fetched: Set<String> = []
    while true {
      try Task.checkCancellation()
      do {
        return try candidate.compile(schema, baseURI: baseURI)
      } catch SchemaError.unresolvedReference(let reference) {
        guard case .https(let hosts, let limit) = policy else {
          throw SchemaError.unresolvedReference(reference)
        }
        let document = URI.document(reference)
        guard let url = URL(string: document), url.scheme == "https", let host = url.host,
          hosts.contains(host)
        else { throw SchemaError.unresolvedReference(reference) }
        guard fetched.count < limit, !fetched.contains(document) else {
          throw SchemaError.resolverLimit
        }
        fetched.insert(document)
        candidate.registry.register(try await resolver.resolve(document), at: document)
      }
    }
  }
  public func bundle(_ schema: JSONValue, baseURI: String = "urn:json-schema:document") throws
    -> JSONValue
  {
    try compile(schema, baseURI: baseURI).bundle()
  }
}

private final class HTTPSRedirectGuard: NSObject, URLSessionTaskDelegate, Sendable {
  let host: String
  init(host: String) { self.host = host }
  func urlSession(
    _ session: URLSession, task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
    completionHandler: @escaping @Sendable (URLRequest?) -> Void
  ) {
    completionHandler(request.url?.scheme == "https" && request.url?.host == host ? request : nil)
  }
}
extension CompiledSchema {
  /// Embed referenced documents and use canonical targets for retrieval aliases.
  public func bundle() throws -> JSONValue {
    guard dialect == .draft2020 else {
      throw SchemaError.invalidSchema("Compound bundling requires draft 2020-12")
    }
    var document = rewrittenDocument(root)
    if document.objectValue == nil { document = ["allOf": .array([document])] }
    if document["$id"] == nil { document["$id"] = .string(nodes[root].resource) }
    var definitions = document["$defs"]?.objectValue ?? JSONObject()
    var documents: Set<String> = [nodes[root].document]
    var count = 0
    for (index, node) in nodes.enumerated()
    where node.physical.tokens.isEmpty && !documents.contains(node.document) {
      documents.insert(node.document)
      var value = rewrittenDocument(index)
      if value.objectValue == nil { value = ["allOf": .array([value])] }
      value[node.dialect.identifier] = .string(node.resource)
      value["$schema"] = .string(node.dialect.rawValue)
      var name = "resource-\(count)"
      while definitions[name] != nil {
        count += 1
        name = "resource-\(count)"
      }
      definitions[name] = value
      count += 1
    }
    document["$defs"] = .object(definitions)
    return document
  }
  private func rewrittenDocument(_ index: Int) -> JSONValue {
    var document = nodes[index].value
    for node in nodes where node.document == nodes[index].document {
      for (keyword, target) in node.references {
        let destination = nodes[target]
        let uri: String
        if keyword == "$dynamicRef", let anchor = destination.dynamicName {
          uri = destination.resource + "#" + anchor
        } else {
          uri = URI.location(destination.resource, destination.pointer)
        }
        document = replacing(
          document, at: (node.physical.tokens + [keyword])[...], with: .string(uri))
      }
    }
    return document
  }
}

private func replacing(
  _ value: JSONValue, at tokens: ArraySlice<String>, with replacement: JSONValue
) -> JSONValue {
  guard let token = tokens.first else { return replacement }
  var result = value
  if var array = value.arrayValue, let index = Int(token), array.indices.contains(index) {
    array[index] = replacing(array[index], at: tokens.dropFirst(), with: replacement)
    result = .array(array)
  } else if let member = value[token] {
    result[token] = replacing(member, at: tokens.dropFirst(), with: replacement)
  }
  return result
}
