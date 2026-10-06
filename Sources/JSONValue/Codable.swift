// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2026 Xudong Xu

import Foundation

/// Encodes directly into ordered values. Order follows the Encodable container calls.
public struct JSONValueEncoder {
  public var keyStrategy: JSONKeyStrategy
  public init(keyStrategy: JSONKeyStrategy = .identity) { self.keyStrategy = keyStrategy }
  /// Uses the value's Encodable implementation and propagates its encoding failures.
  public func encode<T: Encodable>(_ value: T) throws -> JSONValue {
    let encoder = ValueEncoding(path: [], strategy: keyStrategy)
    try encoder.put(value)
    return encoder.storage.materialize()
  }
}

/// Decodes from values without a serialization round trip.
public struct JSONValueDecoder {
  public var keyStrategy: JSONKeyStrategy
  public init(keyStrategy: JSONKeyStrategy = .identity) { self.keyStrategy = keyStrategy }
  /// Decodes directly; mismatched types and numbers outside the destination range throw.
  public func decode<T: Decodable>(_ type: T.Type, from value: JSONValue) throws -> T {
    try ValueDecoding(value: value, path: [], strategy: keyStrategy).get(type)
  }
}

extension JSONNumber: Codable {
  public func encode(to encoder: any Encoder) throws {
    if let direct = encoder as? ValueEncoding {
      direct.storage.leaf = .number(self)
      return
    }
    var single = encoder.singleValueContainer()
    if let integer = intValue {
      try single.encode(integer)
    } else if let double = doubleValue {
      try single.encode(double)
    } else {
      throw EncodingError.invalidValue(
        self,
        .init(codingPath: encoder.codingPath, debugDescription: "Number exceeds encoder precision"))
    }
  }
  public init(from decoder: any Decoder) throws {
    if let direct = decoder as? ValueDecoding, let n = direct.value.numberValue {
      self = n
      return
    }
    let single = try decoder.singleValueContainer()
    if let n = try? single.decode(Int64.self) {
      self.init(n)
    } else {
      try self.init(single.decode(Double.self))
    }
  }
}

extension JSONValue: Codable {
  public func encode(to encoder: any Encoder) throws {
    if let direct = encoder as? ValueEncoding {
      direct.storage.leaf = self
      return
    }
    switch self {
    case .object(let members):
      var keys = encoder.container(keyedBy: ValueKey.self)
      for pair in members { try keys.encode(pair.1, forKey: ValueKey(pair.0)) }
    case .array(let elements):
      var list = encoder.unkeyedContainer()
      for element in elements { try list.encode(element) }
    default:
      var single = encoder.singleValueContainer()
      switch self {
      case .null: try single.encodeNil()
      case .bool(let yes): try single.encode(yes)
      case .string(let text): try single.encode(text)
      case .number(let n): try n.encode(to: encoder)
      default: break
      }
    }
  }
  public init(from decoder: any Decoder) throws {
    if let direct = decoder as? ValueDecoding {
      self = direct.value
      return
    }
    if let keys = try? decoder.container(keyedBy: ValueKey.self) {
      var object = JSONObject()
      for key in keys.allKeys { object[key.stringValue] = try keys.decode(Self.self, forKey: key) }
      self = .object(object)
      return
    }
    if var list = try? decoder.unkeyedContainer() {
      var elements: [Self] = []
      while !list.isAtEnd { elements.append(try list.decode(Self.self)) }
      self = .array(elements)
      return
    }
    let single = try decoder.singleValueContainer()
    if single.decodeNil() {
      self = .null
    } else if let flag = try? single.decode(Bool.self) {
      self = .bool(flag)
    } else if let text = try? single.decode(String.self) {
      self = .string(text)
    } else {
      self = .number(try JSONNumber(from: decoder))
    }
  }
}

private struct ValueKey: CodingKey {
  let stringValue: String
  let intValue: Int?
  init(_ name: String) {
    stringValue = name
    intValue = nil
  }
  init(_ index: Int) {
    stringValue = String(index)
    intValue = index
  }
  init?(stringValue: String) { self.init(stringValue) }
  init?(intValue: Int) { self.init(intValue) }
}

private final class EncodingStorage {
  var leaf: JSONValue?
  var members: [(String, EncodingStorage)]?
  var elements: [EncodingStorage]?
  func member(_ key: String) -> EncodingStorage {
    if let old = members?.first(where: { $0.0.utf8.elementsEqual(key.utf8) }) { return old.1 }
    let storage = EncodingStorage()
    if members == nil { members = [] }
    members!.append((key, storage))
    return storage
  }
  func materialize() -> JSONValue {
    if let members { return .object(JSONObject(members.map { ($0.0, $0.1.materialize()) })) }
    if let elements { return .array(elements.map { $0.materialize() }) }
    return leaf ?? .null
  }
}

private final class ValueEncoding: Encoder {
  let storage: EncodingStorage
  let strategy: JSONKeyStrategy
  let codingPath: [any CodingKey]
  var userInfo: [CodingUserInfoKey: Any] { [:] }
  init(
    path: [any CodingKey], storage: EncodingStorage = EncodingStorage(), strategy: JSONKeyStrategy
  ) {
    codingPath = path
    self.storage = storage
    self.strategy = strategy
  }
  func container<Key: CodingKey>(keyedBy type: Key.Type) -> KeyedEncodingContainer<Key> {
    if storage.members == nil { storage.members = [] }
    return KeyedEncodingContainer(EncodingKeys<Key>(encoder: self))
  }
  func unkeyedContainer() -> any UnkeyedEncodingContainer {
    if storage.elements == nil { storage.elements = [] }
    return EncodingList(encoder: self)
  }
  func singleValueContainer() -> any SingleValueEncodingContainer { EncodingSingle(encoder: self) }
  func child(_ key: any CodingKey, storage: EncodingStorage) -> ValueEncoding {
    ValueEncoding(path: codingPath + [key], storage: storage, strategy: strategy)
  }
  func put<T: Encodable>(_ value: T) throws {
    if let json = value as? JSONValue {
      storage.leaf = json
    } else if let number = value as? JSONNumber {
      storage.leaf = .number(number)
    } else if let url = value as? URL {
      storage.leaf = .string(url.absoluteString)
    } else if let bytes = value as? Data {
      storage.leaf = .string(bytes.base64EncodedString())
    } else if let date = value as? Date {
      let formatter = ISO8601DateFormatter()
      formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
      storage.leaf = .string(formatter.string(from: date))
    } else if let decimal = value as? Decimal {
      storage.leaf = .number(try JSONNumber(NSDecimalNumber(decimal: decimal).stringValue))
    } else {
      try value.encode(to: self)
    }
  }
}

private struct EncodingKeys<Key: CodingKey>: KeyedEncodingContainerProtocol {
  let encoder: ValueEncoding
  var codingPath: [any CodingKey] { encoder.codingPath }
  func slot(_ key: Key) -> ValueEncoding {
    encoder.child(key, storage: encoder.storage.member(encoder.strategy.key(key.stringValue)))
  }
  mutating func encodeNil(forKey key: Key) throws { slot(key).storage.leaf = .null }
  mutating func encode<T: Encodable>(_ value: T, forKey key: Key) throws {
    try slot(key).put(value)
  }
  mutating func nestedContainer<N: CodingKey>(keyedBy type: N.Type, forKey key: Key)
    -> KeyedEncodingContainer<N>
  { slot(key).container(keyedBy: type) }
  mutating func nestedUnkeyedContainer(forKey key: Key) -> any UnkeyedEncodingContainer {
    slot(key).unkeyedContainer()
  }
  mutating func superEncoder() -> any Encoder {
    ValueEncoding(
      path: codingPath, storage: encoder.storage.member("super"), strategy: encoder.strategy)
  }
  mutating func superEncoder(forKey key: Key) -> any Encoder { slot(key) }
}

private struct EncodingList: UnkeyedEncodingContainer {
  let encoder: ValueEncoding
  var codingPath: [any CodingKey] { encoder.codingPath }
  var count: Int { encoder.storage.elements!.count }
  mutating func slot() -> ValueEncoding {
    let storage = EncodingStorage()
    let key = ValueKey(count)
    encoder.storage.elements!.append(storage)
    return encoder.child(key, storage: storage)
  }
  mutating func encodeNil() throws { slot().storage.leaf = .null }
  mutating func encode<T: Encodable>(_ value: T) throws { try slot().put(value) }
  mutating func nestedContainer<N: CodingKey>(keyedBy type: N.Type) -> KeyedEncodingContainer<N> {
    slot().container(keyedBy: type)
  }
  mutating func nestedUnkeyedContainer() -> any UnkeyedEncodingContainer {
    slot().unkeyedContainer()
  }
  mutating func superEncoder() -> any Encoder { slot() }
}

private struct EncodingSingle: SingleValueEncodingContainer {
  let encoder: ValueEncoding
  var codingPath: [any CodingKey] { encoder.codingPath }
  mutating func encodeNil() throws { encoder.storage.leaf = .null }
  mutating func encode(_ value: Bool) throws { encoder.storage.leaf = .bool(value) }
  mutating func encode(_ value: String) throws { encoder.storage.leaf = .string(value) }
  mutating func encode(_ value: Double) throws {
    encoder.storage.leaf = .number(try JSONNumber(value))
  }
  mutating func encode(_ value: Float) throws { try encode(Double(value)) }
  mutating func encode(_ value: Int) throws { encoder.storage.leaf = .number(JSONNumber(value)) }
  mutating func encode(_ value: Int8) throws { encoder.storage.leaf = .number(JSONNumber(value)) }
  mutating func encode(_ value: Int16) throws { encoder.storage.leaf = .number(JSONNumber(value)) }
  mutating func encode(_ value: Int32) throws { encoder.storage.leaf = .number(JSONNumber(value)) }
  mutating func encode(_ value: Int64) throws { encoder.storage.leaf = .number(JSONNumber(value)) }
  mutating func encode(_ value: UInt) throws { encoder.storage.leaf = .number(JSONNumber(value)) }
  mutating func encode(_ value: UInt8) throws { encoder.storage.leaf = .number(JSONNumber(value)) }
  mutating func encode(_ value: UInt16) throws { encoder.storage.leaf = .number(JSONNumber(value)) }
  mutating func encode(_ value: UInt32) throws { encoder.storage.leaf = .number(JSONNumber(value)) }
  mutating func encode(_ value: UInt64) throws { encoder.storage.leaf = .number(JSONNumber(value)) }
  mutating func encode<T: Encodable>(_ value: T) throws { try encoder.put(value) }
}

private struct ValueDecoding: Decoder {
  let value: JSONValue
  let strategy: JSONKeyStrategy
  let codingPath: [any CodingKey]
  var userInfo: [CodingUserInfoKey: Any] { [:] }
  init(value: JSONValue, path: [any CodingKey], strategy: JSONKeyStrategy) {
    self.value = value
    codingPath = path
    self.strategy = strategy
  }
  func mismatch(_ type: Any.Type) -> DecodingError {
    .typeMismatch(
      type,
      .init(codingPath: codingPath, debugDescription: "Expected \(type), found \(value.typeName)"))
  }
  func container<Key: CodingKey>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> {
    guard let map = value.objectValue else { throw mismatch(JSONObject.self) }
    return KeyedDecodingContainer(DecodingKeys<Key>(decoder: self, map: map))
  }
  func unkeyedContainer() throws -> any UnkeyedDecodingContainer {
    guard let list = value.arrayValue else { throw mismatch([JSONValue].self) }
    return DecodingList(decoder: self, elements: list)
  }
  func singleValueContainer() throws -> any SingleValueDecodingContainer {
    DecodingSingle(decoder: self)
  }
  func child(_ value: JSONValue, _ key: any CodingKey) -> Self {
    Self(value: value, path: codingPath + [key], strategy: strategy)
  }
  func get<T: Decodable>(_ type: T.Type) throws -> T {
    if type == JSONValue.self { return value as! T }
    if type == JSONNumber.self, let n = value.numberValue { return n as! T }
    if type == URL.self, let text = value.stringValue, let url = URL(string: text) {
      return url as! T
    }
    if type == Data.self, let text = value.stringValue, let bytes = Data(base64Encoded: text) {
      return bytes as! T
    }
    if type == Date.self {
      if let text = value.stringValue {
        for fractional in [true, false] {
          let formatter = ISO8601DateFormatter()
          formatter.formatOptions =
            fractional ? [.withInternetDateTime, .withFractionalSeconds] : [.withInternetDateTime]
          if let date = formatter.date(from: text) { return date as! T }
        }
      }
      throw mismatch(type)
    }
    if type == Decimal.self {
      guard let number = value.numberValue,
        let decimal = Decimal(string: number.text, locale: Locale(identifier: "en_US_POSIX")),
        !decimal.isNaN,
        (try? JSONNumber(NSDecimalNumber(decimal: decimal).stringValue)) == number
      else { throw mismatch(type) }
      return decimal as! T
    }
    return try T(from: self)
  }
}

private struct DecodingKeys<Key: CodingKey>: KeyedDecodingContainerProtocol {
  let decoder: ValueDecoding
  let map: JSONObject
  var codingPath: [any CodingKey] { decoder.codingPath }
  var allKeys: [Key] {
    map.keys.compactMap { Key(stringValue: $0) ?? Key(stringValue: decoder.strategy.sourceKey($0)) }
  }
  func contains(_ key: Key) -> Bool { map[decoder.strategy.key(key.stringValue)] != nil }
  func slot(_ key: Key) throws -> ValueDecoding {
    guard let value = map[decoder.strategy.key(key.stringValue)] else {
      throw DecodingError.keyNotFound(
        key, .init(codingPath: codingPath, debugDescription: "Missing member"))
    }
    return decoder.child(value, key)
  }
  func decodeNil(forKey key: Key) throws -> Bool { try slot(key).value == .null }
  func decode<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> T { try slot(key).get(type) }
  func nestedContainer<N: CodingKey>(keyedBy type: N.Type, forKey key: Key) throws
    -> KeyedDecodingContainer<N>
  { try slot(key).container(keyedBy: type) }
  func nestedUnkeyedContainer(forKey key: Key) throws -> any UnkeyedDecodingContainer {
    try slot(key).unkeyedContainer()
  }
  func superDecoder() throws -> any Decoder {
    decoder.child(map["super"] ?? .object(JSONObject()), ValueKey("super"))
  }
  func superDecoder(forKey key: Key) throws -> any Decoder { try slot(key) }
}

private struct DecodingList: UnkeyedDecodingContainer {
  let decoder: ValueDecoding
  let elements: [JSONValue]
  var currentIndex = 0
  var count: Int? { elements.count }
  var isAtEnd: Bool { currentIndex >= elements.count }
  var codingPath: [any CodingKey] { decoder.codingPath }
  mutating func slot() throws -> ValueDecoding {
    guard !isAtEnd else {
      throw DecodingError.valueNotFound(
        JSONValue.self, .init(codingPath: codingPath, debugDescription: "End of array"))
    }
    defer { currentIndex += 1 }
    return decoder.child(elements[currentIndex], ValueKey(currentIndex))
  }
  mutating func decodeNil() throws -> Bool {
    if isAtEnd { _ = try slot() }
    if elements[currentIndex] == .null {
      currentIndex += 1
      return true
    }
    return false
  }
  mutating func decode<T: Decodable>(_ type: T.Type) throws -> T { try slot().get(type) }
  mutating func nestedContainer<N: CodingKey>(keyedBy type: N.Type) throws
    -> KeyedDecodingContainer<N>
  { try slot().container(keyedBy: type) }
  mutating func nestedUnkeyedContainer() throws -> any UnkeyedDecodingContainer {
    try slot().unkeyedContainer()
  }
  mutating func superDecoder() throws -> any Decoder { try slot() }
}

private struct DecodingSingle: SingleValueDecodingContainer {
  let decoder: ValueDecoding
  var codingPath: [any CodingKey] { decoder.codingPath }
  func decodeNil() -> Bool { decoder.value == .null }
  func decode(_ type: Bool.Type) throws -> Bool {
    guard let b = decoder.value.boolValue else { throw decoder.mismatch(type) }
    return b
  }
  func decode(_ type: String.Type) throws -> String {
    guard let s = decoder.value.stringValue else { throw decoder.mismatch(type) }
    return s
  }
  func decode(_ type: Double.Type) throws -> Double {
    guard let n = decoder.value.numberValue?.doubleValue else { throw decoder.mismatch(type) }
    return n
  }
  func decode(_ type: Float.Type) throws -> Float {
    let n = Float(try decode(Double.self))
    guard n.isFinite else { throw decoder.mismatch(type) }
    return n
  }
  func decode(_ type: Int.Type) throws -> Int {
    guard let text = decoder.value.numberValue?.integerText, let n = Int(text) else {
      throw decoder.mismatch(type)
    }
    return n
  }
  func decode(_ type: Int8.Type) throws -> Int8 {
    guard let text = decoder.value.numberValue?.integerText, let n = Int8(text) else {
      throw decoder.mismatch(type)
    }
    return n
  }
  func decode(_ type: Int16.Type) throws -> Int16 {
    guard let text = decoder.value.numberValue?.integerText, let n = Int16(text) else {
      throw decoder.mismatch(type)
    }
    return n
  }
  func decode(_ type: Int32.Type) throws -> Int32 {
    guard let text = decoder.value.numberValue?.integerText, let n = Int32(text) else {
      throw decoder.mismatch(type)
    }
    return n
  }
  func decode(_ type: Int64.Type) throws -> Int64 {
    guard let text = decoder.value.numberValue?.integerText, let n = Int64(text) else {
      throw decoder.mismatch(type)
    }
    return n
  }
  func decode(_ type: UInt.Type) throws -> UInt {
    guard let text = decoder.value.numberValue?.integerText, let n = UInt(text) else {
      throw decoder.mismatch(type)
    }
    return n
  }
  func decode(_ type: UInt8.Type) throws -> UInt8 {
    guard let text = decoder.value.numberValue?.integerText, let n = UInt8(text) else {
      throw decoder.mismatch(type)
    }
    return n
  }
  func decode(_ type: UInt16.Type) throws -> UInt16 {
    guard let text = decoder.value.numberValue?.integerText, let n = UInt16(text) else {
      throw decoder.mismatch(type)
    }
    return n
  }
  func decode(_ type: UInt32.Type) throws -> UInt32 {
    guard let text = decoder.value.numberValue?.integerText, let n = UInt32(text) else {
      throw decoder.mismatch(type)
    }
    return n
  }
  func decode(_ type: UInt64.Type) throws -> UInt64 {
    guard let text = decoder.value.numberValue?.integerText, let n = UInt64(text) else {
      throw decoder.mismatch(type)
    }
    return n
  }
  func decode<T: Decodable>(_ type: T.Type) throws -> T { try decoder.get(type) }
}
