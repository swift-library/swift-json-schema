// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2026 Xudong Xu

import Foundation

/// Selects the first or last value for an exact duplicate key, or rejects the document.
public enum DuplicateKeyPolicy: Sendable { case first, last, reject }

/// Byte column and offset refer to UTF-8; pointer identifies the value being read.
public struct JSONParseError: Error, Sendable, CustomStringConvertible {
  public let message: String
  public let offset: Int
  public let line: Int
  public let column: Int
  public let pointer: JSONPointer
  public var description: String { "\(message) at \(line):\(column) (\(pointer))" }
}

/// Parses one complete UTF-8 JSON value while retaining number tokens and object order.
public struct JSONParser: Sendable {
  public var duplicateKeys: DuplicateKeyPolicy
  /// Maximum nesting checked while reading child values; defaults to 256.
  public var maximumDepth: Int
  /// Defaults to the last duplicate value and a nesting limit of 256.
  public init(duplicateKeys: DuplicateKeyPolicy = .last, maximumDepth: Int = 256) {
    self.duplicateKeys = duplicateKeys
    self.maximumDepth = maximumDepth
  }
  /// Throws `JSONParseError` for invalid UTF-8, syntax, trailing input, or nesting overflow.
  public func parse(_ data: Data) throws -> JSONValue {
    var reader = UTF8Reader(bytes: Array(data), options: self)
    guard String(data: data, encoding: .utf8) != nil else { throw reader.failure("Invalid UTF-8") }
    let value = try reader.read()
    reader.space()
    guard reader.position == reader.bytes.count else { throw reader.failure("Trailing input") }
    return value
  }
  public func parse(_ text: String) throws -> JSONValue { try parse(Data(text.utf8)) }
}

extension JSONValue {
  /// Parses with `JSONParser` defaults: last duplicate value and a nesting limit of 256.
  public static func parse(_ text: String) throws -> Self { try JSONParser().parse(text) }
  /// Parses UTF-8 bytes using the default duplicate-key and nesting policies.
  public static func parse(_ bytes: Data) throws -> Self { try JSONParser().parse(bytes) }
}

private struct UTF8Reader {
  let bytes: [UInt8]
  let options: JSONParser
  var position = 0
  var path: [String] = []
  var next: UInt8? { position < bytes.count ? bytes[position] : nil }
  mutating func space() { while let c = next, [9, 10, 13, 32].contains(c) { position += 1 } }
  mutating func consume(_ c: UInt8) -> Bool {
    if next == c {
      position += 1
      return true
    }
    return false
  }
  mutating func demand(_ c: UInt8) throws {
    guard consume(c) else { throw failure("Expected '\(Character(UnicodeScalar(c)))'") }
  }
  func failure(_ message: String) -> JSONParseError {
    var row = 1
    var column = 1
    var previous: UInt8 = 0
    for b in bytes.prefix(position) {
      if b == 13 || (b == 10 && previous != 13) {
        row += 1
        column = 1
      } else if b != 10 {
        column += 1
      }
      previous = b
    }
    return JSONParseError(
      message: message, offset: position, line: row, column: column,
      pointer: JSONPointer(tokens: path))
  }
  mutating func read() throws -> JSONValue {
    var frames: [ParseFrame] = []
    var tokens: [String] = []
    var pending: JSONValue?
    while true {
      if pending == nil {
        path = tokens
        space()
        guard frames.count <= options.maximumDepth else { throw failure("Nesting limit exceeded") }
        switch next {
        case 123:
          position += 1
          space()
          if consume(125) {
            pending = .object(JSONObject())
          } else {
            let key = try string()
            space()
            try demand(58)
            frames.append(ParseFrame(tokens: tokens, key: key, object: JSONObject()))
            tokens.append(key)
            continue
          }
        case 91:
          position += 1
          space()
          if consume(93) {
            pending = .array([])
          } else {
            frames.append(ParseFrame(tokens: tokens, array: []))
            tokens.append("0")
            continue
          }
        case 34: pending = .string(try string())
        case 110:
          try literal("null")
          pending = .null
        case 116:
          try literal("true")
          pending = .bool(true)
        case 102:
          try literal("false")
          pending = .bool(false)
        case 45?, (48...57)?:
          let begin = position
          while let c = next, (48...57).contains(c) || [43, 45, 46, 69, 101].contains(c) {
            position += 1
          }
          do {
            pending = .number(
              try JSONNumber(String(decoding: bytes[begin..<position], as: UTF8.self)))
          } catch { throw failure("Invalid number") }
        default: throw failure("Expected a JSON value")
        }
      }
      guard var frame = frames.popLast() else { return pending! }
      if frame.object != nil {
        let key = frame.key!
        if frame.object![key] == nil {
          frame.object![key] = pending
        } else {
          switch options.duplicateKeys {
          case .first: break
          case .last:
            frame.object!.remove(key)
            frame.object![key] = pending
          case .reject: throw failure("Duplicate member '\(key)'")
          }
        }
        space()
        if consume(125) {
          pending = .object(frame.object!)
          continue
        }
        try demand(44)
        space()
        path = frame.tokens
        frame.key = try string()
        space()
        try demand(58)
        tokens = frame.tokens + [frame.key!]
      } else {
        frame.array!.append(pending!)
        space()
        if consume(93) {
          pending = .array(frame.array!)
          continue
        }
        try demand(44)
        tokens = frame.tokens + [String(frame.array!.count)]
      }
      frames.append(frame)
      pending = nil
    }
  }
  mutating func literal(_ word: String) throws {
    for c in word.utf8 { try demand(c) }
  }
  mutating func hex() throws -> UInt32 {
    var value: UInt32 = 0
    for _ in 0..<4 {
      guard let c = next else { throw failure("Incomplete Unicode escape") }
      let digit: UInt32
      switch c {
      case 48...57: digit = UInt32(c - 48)
      case 65...70: digit = UInt32(c - 55)
      case 97...102: digit = UInt32(c - 87)
      default: throw failure("Invalid Unicode escape")
      }
      value = value * 16 + digit
      position += 1
    }
    return value
  }
  mutating func string() throws -> String {
    try demand(34)
    var output: [UInt8] = []
    while let c = next {
      position += 1
      if c == 34 { return String(decoding: output, as: UTF8.self) }
      guard c >= 32 else { throw failure("Unescaped control character") }
      if c != 92 {
        output.append(c)
        continue
      }
      guard let escape = next else { throw failure("Incomplete escape") }
      position += 1
      switch escape {
      case 34, 47, 92: output.append(escape)
      case 98: output.append(8)
      case 102: output.append(12)
      case 110: output.append(10)
      case 114: output.append(13)
      case 116: output.append(9)
      case 117:
        var scalar = try hex()
        if (0xD800...0xDBFF).contains(scalar) {
          try demand(92)
          try demand(117)
          let low = try hex()
          guard (0xDC00...0xDFFF).contains(low) else { throw failure("Unpaired surrogate") }
          scalar = 0x10000 + (scalar - 0xD800) * 1024 + low - 0xDC00
        }
        guard let unicode = UnicodeScalar(scalar) else { throw failure("Invalid Unicode scalar") }
        output += String(unicode).utf8
      default: throw failure("Unknown escape")
      }
    }
    throw failure("Unterminated string")
  }
}

private struct ParseFrame {
  let tokens: [String]
  var key: String? = nil
  var object: JSONObject? = nil
  var array: [JSONValue]? = nil
}
