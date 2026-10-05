// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2026 Xudong Xu

import Foundation

/// RFC 6901 tokens retain their spelling until resolved against a value.
public struct JSONPointer: Sendable, Hashable, CustomStringConvertible {
  public let tokens: [String]
  public init(tokens: [String] = []) { self.tokens = tokens }
  public init(_ text: String) throws {
    var value = text
    if value.hasPrefix("#") {
      guard let decoded = String(value.dropFirst()).removingPercentEncoding else {
        throw JSONError.invalidPointer(text)
      }
      value = decoded
    }
    if value.isEmpty {
      tokens = []
      return
    }
    guard value.first == "/" else { throw JSONError.invalidPointer(text) }
    tokens = try value.dropFirst().split(separator: "/", omittingEmptySubsequences: false).map {
      part in
      var result = ""
      var escape = false
      for c in part {
        if escape {
          guard c == "0" || c == "1" else { throw JSONError.invalidPointer(text) }
          result.append(c == "0" ? "~" : "/")
          escape = false
        } else if c == "~" {
          escape = true
        } else {
          result.append(c)
        }
      }
      guard !escape else { throw JSONError.invalidPointer(text) }
      return result
    }
  }
  public var description: String {
    tokens.map {
      "/" + $0.replacingOccurrences(of: "~", with: "~0").replacingOccurrences(of: "/", with: "~1")
    }.joined()
  }
  public var fragment: String {
    "#" + description.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed)!
  }
  public func appending(_ token: String) -> Self { Self(tokens: tokens + [token]) }
  public static func == (a: Self, b: Self) -> Bool {
    a.tokens.count == b.tokens.count
      && zip(a.tokens, b.tokens).allSatisfy { $0.utf8.elementsEqual($1.utf8) }
  }
  public func hash(into hasher: inout Hasher) {
    for token in tokens { hasher.combine(Array(token.utf8)) }
  }
  public func resolve(in document: JSONValue) throws -> JSONValue {
    var current = document
    for token in tokens {
      if let map = current.objectValue, let value = map[token] {
        current = value
      } else if let list = current.arrayValue, let i = Int(token), i >= 0,
        String(i) == token, list.indices.contains(i)
      {
        current = list[i]
      } else {
        throw JSONError.missingValue(description)
      }
    }
    return current
  }
}

/// A Relative JSON Pointer, including parent-index adjustment and the key query.
public struct RelativeJSONPointer: Sendable {
  public let levels: Int
  public let indexOffset: Int
  public let keyQuery: Bool
  public let tail: JSONPointer
  public init(_ text: String) throws {
    let prefix = text.prefix(while: { $0.isNumber && $0.isASCII })
    guard let n = Int(prefix), String(n) == prefix else { throw JSONError.invalidPointer(text) }
    levels = n
    var rest = String(text.dropFirst(prefix.count))
    var offset = 0
    if rest.first == "+" || rest.first == "-" {
      let negative = rest.removeFirst() == "-"
      let digits = rest.prefix(while: { $0.isNumber && $0.isASCII })
      guard let delta = Int(digits), String(delta) == digits else {
        throw JSONError.invalidPointer(text)
      }
      offset = negative ? -delta : delta
      rest.removeFirst(digits.count)
    }
    indexOffset = offset
    keyQuery = rest == "#"
    guard rest.isEmpty || rest == "#" || rest.hasPrefix("/") else {
      throw JSONError.invalidPointer(text)
    }
    tail = try JSONPointer(keyQuery ? "" : rest)
  }
  public func resolve(in document: JSONValue, from location: JSONPointer) throws -> JSONValue {
    guard levels <= location.tokens.count else {
      throw JSONError.missingValue(location.description)
    }
    var base = Array(location.tokens.dropLast(levels))
    if indexOffset != 0 {
      guard let token = base.last, let i = Int(token), String(i) == token else {
        throw JSONError.invalidPointer(location.description)
      }
      let parent = try JSONPointer(tokens: Array(base.dropLast())).resolve(in: document)
      let (shifted, overflow) = i.addingReportingOverflow(indexOffset)
      guard !overflow, let array = parent.arrayValue, array.indices.contains(shifted) else {
        throw JSONError.missingValue(location.description)
      }
      base[base.count - 1] = String(shifted)
    }
    if keyQuery {
      _ = try JSONPointer(tokens: base).resolve(in: document)
      guard let key = base.last else { throw JSONError.missingValue("") }
      let parent = try JSONPointer(tokens: Array(base.dropLast())).resolve(in: document)
      return parent.arrayValue == nil ? .string(key) : .number(JSONNumber(Int(key)!))
    }
    return try JSONPointer(tokens: base + tail.tokens).resolve(in: document)
  }
}
