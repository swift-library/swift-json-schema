// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2026 Xudong Xu

import Foundation

/// Compact and pretty preserve number tokens; canonical uses RFC 8785 binary64 semantics.
public enum JSONSerializationStyle: Sendable { case compact, pretty, canonical }

private enum JSONEmission {
  case value(JSONValue, Int)
  case text(String)
}

extension JSONValue {
  /// Emits JSON, using two-space indentation for pretty output.
  /// Canonical output sorts keys by UTF-16 and may round numbers to binary64;
  /// it throws `JSONError.canonicalNumberOutOfRange` when no finite Double exists.
  public func serialized(_ style: JSONSerializationStyle = .compact) throws -> String {
    let pretty = style == .pretty
    var pending: [JSONEmission] = [.value(self, 0)]
    var output = ""
    while let emission = pending.popLast() {
      switch emission {
      case .text(let text): output += text
      case .value(let value, let level):
        switch value {
        case .null: output += "null"
        case .bool(let flag): output += flag ? "true" : "false"
        case .string(let text): output += quote(text)
        case .number(let number):
          output += style == .canonical ? try canonical(number) : number.text
        case .array(let values):
          if values.isEmpty {
            output += "[]"
            continue
          }
          let indent = String(repeating: "  ", count: level + 1)
          output += "[" + (pretty ? "\n" + indent : "")
          pending.append(.text((pretty ? "\n" + String(repeating: "  ", count: level) : "") + "]"))
          for index in values.indices.reversed() {
            pending.append(.value(values[index], level + 1))
            if index > 0 { pending.append(.text("," + (pretty ? "\n" + indent : ""))) }
          }
        case .object(let object):
          var pairs = Array(object)
          if pairs.isEmpty {
            output += "{}"
            continue
          }
          if style == .canonical { pairs.sort { $0.0.utf16.lexicographicallyPrecedes($1.0.utf16) } }
          let indent = String(repeating: "  ", count: level + 1)
          output += "{" + (pretty ? "\n" + indent : "")
          pending.append(.text((pretty ? "\n" + String(repeating: "  ", count: level) : "") + "}"))
          for index in pairs.indices.reversed() {
            pending.append(.value(pairs[index].1, level + 1))
            pending.append(.text(quote(pairs[index].0) + (pretty ? ": " : ":")))
            if index > 0 { pending.append(.text("," + (pretty ? "\n" + indent : ""))) }
          }
        }
      }
    }
    return output
  }
  /// Returns the UTF-8 bytes of `serialized(_:)`, with the same numeric limits.
  public func serializedData(_ style: JSONSerializationStyle = .compact) throws -> Data {
    Data(try serialized(style).utf8)
  }
}

private func quote(_ text: String) -> String {
  var result = "\""
  for scalar in text.unicodeScalars {
    switch scalar.value {
    case 34: result += "\\\""
    case 92: result += "\\\\"
    case 8: result += "\\b"
    case 9: result += "\\t"
    case 10: result += "\\n"
    case 12: result += "\\f"
    case 13: result += "\\r"
    case 0...31:
      let hex = String(scalar.value, radix: 16)
      result += "\\u" + String(repeating: "0", count: 4 - hex.count) + hex
    default: result.unicodeScalars.append(scalar)
    }
  }
  return result + "\""
}

private func canonical(_ number: JSONNumber) throws -> String {
  guard let binary = number.doubleValue else {
    throw JSONError.canonicalNumberOutOfRange(number.text)
  }
  if binary == 0 { return "0" }
  var text = String(abs(binary)).lowercased()
  let parts = text.split(separator: "e")
  let power = parts.count == 2 ? Int(parts[1])! : 0
  text = String(parts[0])
  let before = text.split(separator: ".")[0].count
  var digits = text.replacingOccurrences(of: ".", with: "")
  let leading = digits.prefix(while: { $0 == "0" }).count
  digits.removeFirst(leading)
  var point = before + power - leading
  while digits.last == "0" { digits.removeLast() }
  let sign = binary < 0 ? "-" : ""
  if point > 0 && point <= 21 {
    if digits.count <= point {
      return sign + digits + String(repeating: "0", count: point - digits.count)
    }
    let cut = digits.index(digits.startIndex, offsetBy: point)
    return sign + digits[..<cut] + "." + digits[cut...]
  }
  if point <= 0 && point > -6 {
    return sign + "0." + String(repeating: "0", count: -point) + digits
  }
  point -= 1
  let mantissa = String(digits.prefix(1)) + (digits.count > 1 ? "." + digits.dropFirst() : "")
  return sign + mantissa + "e" + (point >= 0 ? "+" : "") + String(point)
}
