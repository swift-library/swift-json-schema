// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2026 Xudong Xu

import Foundation
import OrderedCollections

/// Swift's canonical String equality is not JSON key equality.
struct MemberKey: Hashable, Sendable {
  let text: String
  static func == (a: Self, b: Self) -> Bool { a.text.utf8.elementsEqual(b.text.utf8) }
  func hash(into hasher: inout Hasher) { hasher.combine(Array(text.utf8)) }
}

/// Object members in insertion order, with exact Unicode identity.
public struct JSONObject: Sendable, Equatable, Sequence, ExpressibleByDictionaryLiteral {
  private var members: OrderedDictionary<MemberKey, JSONValue> = [:]
  public init() {}
  public init(dictionaryLiteral elements: (String, JSONValue)...) {
    for pair in elements { self[pair.0] = pair.1 }
  }
  public init(_ elements: [(String, JSONValue)]) {
    for pair in elements { self[pair.0] = pair.1 }
  }
  public var count: Int { members.count }
  public var keys: [String] { members.keys.map(\.text) }
  public subscript(_ name: String) -> JSONValue? {
    get { members[MemberKey(text: name)] }
    set { members[MemberKey(text: name)] = newValue }
  }
  public mutating func remove(_ name: String) { members.removeValue(forKey: MemberKey(text: name)) }
  public func makeIterator() -> IndexingIterator<[(String, JSONValue)]> {
    members.map { ($0.key.text, $0.value) }.makeIterator()
  }
  public static func == (a: Self, b: Self) -> Bool {
    a.count == b.count && a.allSatisfy { b[$0.0] == $0.1 }
  }
}

/// An RFC 8259 value. Object order and number spelling survive parsing and emission.
public indirect enum JSONValue: Sendable, Equatable {
  case null
  case bool(Bool)
  case string(String)
  case number(JSONNumber)
  case array([JSONValue])
  case object(JSONObject)

  public var stringValue: String? {
    if case .string(let text) = self { return text }
    return nil
  }
  public var numberValue: JSONNumber? {
    if case .number(let n) = self { return n }
    return nil
  }
  public var arrayValue: [Self]? {
    if case .array(let list) = self { return list }
    return nil
  }
  public var objectValue: JSONObject? {
    if case .object(let map) = self { return map }
    return nil
  }
  public var boolValue: Bool? {
    if case .bool(let flag) = self { return flag }
    return nil
  }
  public var typeName: String {
    switch self {
    case .null: "null"
    case .bool: "boolean"
    case .string: "string"
    case .number: "number"
    case .array: "array"
    case .object: "object"
    }
  }
  public subscript(_ key: String) -> Self? {
    get { objectValue?[key] }
    set {
      guard case .object(var map) = self else { return }
      map[key] = newValue
      self = .object(map)
    }
  }
  public static func == (a: Self, b: Self) -> Bool {
    switch (a, b) {
    case (.null, .null): true
    case (.bool(let x), .bool(let y)): x == y
    case (.string(let x), .string(let y)): x.utf8.elementsEqual(y.utf8)
    case (.number(let x), .number(let y)): x == y
    case (.array(let x), .array(let y)): x == y
    case (.object(let x), .object(let y)): x == y
    default: false
    }
  }
}

extension JSONValue: ExpressibleByNilLiteral, ExpressibleByBooleanLiteral,
  ExpressibleByStringLiteral, ExpressibleByIntegerLiteral, ExpressibleByArrayLiteral,
  ExpressibleByDictionaryLiteral
{
  public init(nilLiteral: ()) { self = .null }
  public init(booleanLiteral: Bool) { self = .bool(booleanLiteral) }
  public init(stringLiteral: String) { self = .string(stringLiteral) }
  public init(integerLiteral: Int64) { self = .number(JSONNumber(integerLiteral)) }
  public init(arrayLiteral: JSONValue...) { self = .array(arrayLiteral) }
  public init(dictionaryLiteral: (String, JSONValue)...) {
    self = .object(JSONObject(dictionaryLiteral))
  }
}

/// Failures at JSON representation boundaries.
public enum JSONError: Error, Sendable, Equatable {
  case invalidNumber(String)
  case invalidPointer(String)
  case missingValue(String)
  case canonicalNumberOutOfRange(String)
}
