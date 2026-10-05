// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2026 Xudong Xu

import Foundation

/// A finite decimal token with exact comparison and divisibility semantics.
public struct JSONNumber: Sendable, Equatable, Comparable, Hashable {
  public let text: String
  private let negative: Bool
  private let coefficient: String
  private let scale: DecimalPower

  public init(_ text: String) throws {
    let bytes = Array(text.utf8)
    var i = 0
    func digit(_ p: Int) -> Bool { p < bytes.count && (48...57).contains(bytes[p]) }
    let minus = bytes.first == 45
    if minus { i += 1 }
    let start = i
    guard digit(i) else { throw JSONError.invalidNumber(text) }
    if bytes[i] == 48 { i += 1 } else { while digit(i) { i += 1 } }
    let whole = String(decoding: bytes[start..<i], as: UTF8.self)
    var fraction = ""
    if i < bytes.count && bytes[i] == 46 {
      i += 1
      let f = i
      while digit(i) { i += 1 }
      guard i > f else { throw JSONError.invalidNumber(text) }
      fraction = String(decoding: bytes[f..<i], as: UTF8.self)
    }
    var exponent = DecimalPower(0)
    if i < bytes.count && (bytes[i] == 101 || bytes[i] == 69) {
      i += 1
      var sign = false
      if i < bytes.count && (bytes[i] == 45 || bytes[i] == 43) {
        sign = bytes[i] == 45
        i += 1
      }
      let e = i
      while digit(i) { i += 1 }
      guard i > e else { throw JSONError.invalidNumber(text) }
      exponent = DecimalPower(negative: sign, digits: String(decoding: bytes[e..<i], as: UTF8.self))
    }
    guard i == bytes.count else { throw JSONError.invalidNumber(text) }
    var significant = String((whole + fraction).drop(while: { $0 == "0" }))
    var trailing = 0
    while significant.last == "0" {
      significant.removeLast()
      trailing += 1
    }
    self.text = text
    coefficient = significant.isEmpty ? "0" : significant
    negative = minus && coefficient != "0"
    scale = coefficient == "0" ? DecimalPower(0) : exponent.adding(trailing - fraction.count)
  }

  public init<T: BinaryInteger>(_ integer: T) { self = try! Self(String(integer)) }
  public init(_ value: Double) throws {
    guard value.isFinite else { throw JSONError.invalidNumber(String(value)) }
    try self.init(String(value))
  }
  public var isInteger: Bool { coefficient == "0" || scale >= DecimalPower(0) }
  public var doubleValue: Double? { Double(text).flatMap { $0.isFinite ? $0 : nil } }
  public var intValue: Int? {
    integerText.flatMap(Int.init)
  }
  public var integerText: String? {
    guard isInteger, let shift = scale.smallValue, shift >= 0, shift < 20 else { return nil }
    return (negative ? "-" : "") + coefficient + String(repeating: "0", count: shift)
  }
  public static func == (a: Self, b: Self) -> Bool {
    a.negative == b.negative && a.coefficient == b.coefficient && a.scale == b.scale
  }
  public func hash(into hasher: inout Hasher) {
    hasher.combine(negative)
    hasher.combine(coefficient)
    hasher.combine(scale)
  }
  public static func < (a: Self, b: Self) -> Bool {
    if a == b { return false }
    if a.negative != b.negative { return a.negative }
    let less: Bool
    if a.coefficient == "0" {
      less = true
    } else if b.coefficient == "0" {
      less = false
    } else {
      let ap = a.scale.adding(a.coefficient.count)
      let bp = b.scale.adding(b.coefficient.count)
      if ap != bp {
        less = ap < bp
      } else {
        let size = max(a.coefficient.count, b.coefficient.count)
        let x = a.coefficient + String(repeating: "0", count: size - a.coefficient.count)
        let y = b.coefficient + String(repeating: "0", count: size - b.coefficient.count)
        less = x < y
      }
    }
    return a.negative ? !less : less
  }

  /// Uses integer coefficient division; no binary floating-point tolerance is applied.
  public func isMultiple(of divisor: Self) -> Bool {
    if divisor.coefficient == "0" { return false }
    if coefficient == "0" { return true }
    if scale < divisor.scale { return false }
    var denominator = DecimalDigits(divisor.coefficient)
    var numerator = DecimalDigits(coefficient)
    var twos = 0
    var fives = 0
    while denominator.remainder(2) == 0 {
      denominator.divide(2)
      twos += 1
    }
    while denominator.remainder(5) == 0 {
      denominator.divide(5)
      fives += 1
    }
    while numerator.remainder(2) == 0 {
      numerator.divide(2)
      twos -= 1
    }
    while numerator.remainder(5) == 0 {
      numerator.divide(5)
      fives -= 1
    }
    let needed = max(0, twos, fives)
    guard scale >= divisor.scale.adding(needed) else { return false }
    return numerator.modulo(denominator).isZero
  }
}

private struct DecimalPower: Sendable, Hashable, Comparable {
  let negative: Bool
  let digits: String
  init(_ value: Int) { self.init(negative: value < 0, digits: String(value.magnitude)) }
  init(negative: Bool, digits: String) {
    let stripped = String(digits.drop(while: { $0 == "0" }))
    self.digits = stripped.isEmpty ? "0" : stripped
    self.negative = negative && self.digits != "0"
  }
  var smallValue: Int? { Int((negative ? "-" : "") + digits) }
  static func < (a: Self, b: Self) -> Bool {
    if a.negative != b.negative { return a.negative }
    let less =
      a.digits.count == b.digits.count ? a.digits < b.digits : a.digits.count < b.digits.count
    return a.negative ? (a != b && !less) : less
  }
  func adding(_ offset: Int) -> Self {
    let other = Self(offset)
    let a = DecimalDigits(digits)
    let b = DecimalDigits(other.digits)
    if negative == other.negative { return Self(negative: negative, digits: a.adding(b).text) }
    if a >= b { return Self(negative: negative, digits: a.subtracting(b).text) }
    return Self(negative: other.negative, digits: b.subtracting(a).text)
  }
}

private struct DecimalDigits: Comparable {
  var digits: [Int]
  init(_ text: String) {
    digits = text.utf8.map { Int($0) - 48 }
    trim()
  }
  var text: String { digits.map(String.init).joined() }
  var isZero: Bool { digits == [0] }
  mutating func trim() { while digits.count > 1 && digits.first == 0 { digits.removeFirst() } }
  static func < (a: Self, b: Self) -> Bool {
    a.digits.count == b.digits.count
      ? a.digits.lexicographicallyPrecedes(b.digits) : a.digits.count < b.digits.count
  }
  func remainder(_ divisor: Int) -> Int { digits.reduce(0) { ($0 * 10 + $1) % divisor } }
  mutating func divide(_ divisor: Int) {
    var carry = 0
    for i in digits.indices {
      let n = carry * 10 + digits[i]
      digits[i] = n / divisor
      carry = n % divisor
    }
    trim()
  }
  func adding(_ other: Self) -> Self {
    var a = Array(digits.reversed())
    var b = Array(other.digits.reversed())
    let length = max(a.count, b.count)
    a += Array(repeating: 0, count: length - a.count)
    b += Array(repeating: 0, count: length - b.count)
    var carry = 0
    var out: [Int] = []
    for i in 0..<length {
      let n = a[i] + b[i] + carry
      out.append(n % 10)
      carry = n / 10
    }
    if carry > 0 { out.append(carry) }
    return Self(out.reversed().map(String.init).joined())
  }
  func subtracting(_ other: Self) -> Self {
    let a = Array(digits.reversed())
    let b = Array(other.digits.reversed())
    var borrow = 0
    var out: [Int] = []
    for i in a.indices {
      var n = a[i] - (i < b.count ? b[i] : 0) - borrow
      borrow = n < 0 ? 1 : 0
      if n < 0 { n += 10 }
      out.append(n)
    }
    return Self(out.reversed().map(String.init).joined())
  }
  func modulo(_ divisor: Self) -> Self {
    var rest = Self("0")
    for d in digits {
      rest.digits.append(d)
      rest.trim()
      while rest >= divisor { rest = rest.subtracting(divisor) }
    }
    return rest
  }
}
