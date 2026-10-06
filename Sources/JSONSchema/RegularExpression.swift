// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2026 Xudong Xu

import Foundation

/// ECMA-262 pattern search over Unicode code points, without implicit anchoring.
public struct ECMARegularExpression: Sendable {
  private let expression: PatternExpression
  private let names: [Data: Int]
  /// Parses a pattern and checks capture references; throws for unsupported or malformed syntax.
  public init(_ pattern: String) throws {
    var grammar = PatternGrammar(input: Array(pattern.unicodeScalars))
    expression = try grammar.alternatives()
    guard grammar.position == grammar.input.count else {
      throw SchemaError.invalidSchema("Invalid regular expression")
    }
    try expression.checkReferences(count: grammar.captures, names: grammar.names)
    names = grammar.names
  }
  /// Searches for a match at any Unicode-scalar position, including the end of an empty string.
  public func matches(_ string: String) -> Bool {
    var machine = PatternMachine(input: Array(string.unicodeScalars), names: names)
    for start in 0...machine.input.count {
      if !machine.run(expression, state: PatternState(position: start)).isEmpty { return true }
    }
    return false
  }
}

private indirect enum PatternExpression: Sendable {
  case sequence([PatternExpression])
  case choice([PatternExpression])
  case scalar(UInt32)
  case characterClass([PatternClass], Bool)
  case dot
  case start, end
  case boundary(Bool)
  case group(PatternExpression, Int)
  case repeatPattern(PatternExpression, Int, Int?, Bool)
  case look(PatternExpression, Bool, Bool)
  case backreference(Int)
  case namedReference(Data)

  var captureIDs: Set<Int> {
    switch self {
    case .sequence(let elements), .choice(let elements):
      return elements.reduce(into: []) { $0.formUnion($1.captureIDs) }
    case .group(let body, let index): return body.captureIDs.union([index])
    case .repeatPattern(let body, _, _, _), .look(let body, _, _): return body.captureIDs
    default: return []
    }
  }

  func checkReferences(count: Int, names: [Data: Int]) throws {
    switch self {
    case .sequence(let elements), .choice(let elements):
      for element in elements { try element.checkReferences(count: count, names: names) }
    case .group(let body, _), .repeatPattern(let body, _, _, _), .look(let body, _, _):
      try body.checkReferences(count: count, names: names)
    case .backreference(let index) where index > count:
      throw SchemaError.invalidSchema("Backreference has no capturing group")
    case .namedReference(let name) where names[name] == nil:
      throw SchemaError.invalidSchema("Named backreference has no capturing group")
    default: break
    }
  }
}

private enum PatternClass: Sendable {
  case range(UInt32, UInt32)
  case digits(Bool)
  case word(Bool)
  case whitespace(Bool)
  case property(NSRegularExpression, Bool)
  func accepts(_ scalar: UnicodeScalar) -> Bool {
    let n = scalar.value
    switch self {
    case .range(let lo, let hi): return lo <= n && n <= hi
    case .digits(let positive): return (48...57).contains(n) == positive
    case .word(let positive):
      return ((48...57).contains(n) || (65...90).contains(n) || (97...122).contains(n) || n == 95)
        == positive
    case .whitespace(let positive):
      return
        ([9, 10, 11, 12, 13, 32, 160, 0x1680, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000, 0xFEFF]
        .contains(n) || (0x2000...0x200A).contains(n)) == positive
    case .property(let regex, let positive):
      let text = String(scalar)
      return (regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil)
        == positive
    }
  }
}

private struct PatternGrammar {
  let input: [UnicodeScalar]
  var position = 0
  var captures = 0
  var names: [Data: Int] = [:]
  var peek: UInt32? { position < input.count ? input[position].value : nil }
  mutating func eat(_ scalar: UInt32) -> Bool {
    if peek == scalar {
      position += 1
      return true
    }
    return false
  }
  mutating func require(_ scalar: UInt32) throws {
    if !eat(scalar) {
      throw SchemaError.invalidSchema("Invalid regular expression at scalar \(position)")
    }
  }
  mutating func alternatives() throws -> PatternExpression {
    var branches = [try sequence()]
    while eat(124) { branches.append(try sequence()) }
    return .choice(branches)
  }
  mutating func sequence() throws -> PatternExpression {
    var terms: [PatternExpression] = []
    while let c = peek, c != 41 && c != 124 {
      let item = try atom()
      var minimum: Int?
      var maximum: Int?
      if eat(42) {
        minimum = 0
      } else if eat(43) {
        minimum = 1
      } else if eat(63) {
        minimum = 0
        maximum = 1
      } else if eat(123) {
        let saved = position - 1
        let lo = digits()
        if let lo {
          minimum = lo
          maximum = lo
          if eat(44) { maximum = digits() }
          try require(125)
          if let hi = maximum, hi < lo {
            throw SchemaError.invalidSchema("Reversed quantifier range")
          }
        } else {
          position = saved
        }
      }
      if let minimum {
        switch item {
        case .start, .end, .boundary, .look:
          throw SchemaError.invalidSchema("An assertion cannot be quantified")
        default: break
        }
        terms.append(.repeatPattern(item, minimum, maximum, !eat(63)))
      } else {
        terms.append(item)
      }
    }
    return .sequence(terms)
  }
  mutating func digits() -> Int? {
    let start = position
    while let c = peek, (48...57).contains(c) { position += 1 }
    return start == position ? nil : Int(String(String.UnicodeScalarView(input[start..<position])))
  }
  mutating func atom() throws -> PatternExpression {
    guard let c = peek else { throw SchemaError.invalidSchema("Incomplete regular expression") }
    position += 1
    switch c {
    case 94: return .start
    case 36: return .end
    case 46: return .dot
    case 42, 43, 63: throw SchemaError.invalidSchema("Quantifier without an atom")
    case 93, 123, 125: throw SchemaError.invalidSchema("Unescaped regular expression syntax")
    case 92: return try escaped(inClass: false)
    case 91:
      let negative = eat(94)
      var classes: [PatternClass] = []
      while peek != 93 {
        guard peek != nil else { throw SchemaError.invalidSchema("Unclosed character class") }
        let first = try classAtom()
        if eat(45) {
          if peek == 93 {
            classes += first + [.range(45, 45)]
          } else {
            let last = try classAtom()
            guard first.count == 1, last.count == 1, case .range(let lo, _) = first[0],
              case .range(_, let hi) = last[0], lo <= hi
            else { throw SchemaError.invalidSchema("Invalid character range") }
            classes.append(.range(lo, hi))
          }
        } else {
          classes += first
        }
      }
      try require(93)
      return .characterClass(classes, negative)
    case 40:
      var capture: Int?
      var look: (Bool, Bool)?
      if eat(63) {
        if eat(58) {
        } else if eat(61) {
          look = (true, false)
        } else if eat(33) {
          look = (false, false)
        } else if eat(60) {
          if eat(61) {
            look = (true, true)
          } else if eat(33) {
            look = (false, true)
          } else {
            let name = Data(try captureName().utf8)
            captures += 1
            capture = captures
            guard names[name] == nil else {
              throw SchemaError.invalidSchema("Duplicate capture name")
            }
            names[name] = captures
          }
        } else {
          throw SchemaError.invalidSchema("Invalid group prefix")
        }
      } else {
        captures += 1
        capture = captures
      }
      let body = try alternatives()
      try require(41)
      if let look { return .look(body, look.0, look.1) }
      if let capture { return .group(body, capture) }
      return body
    default: return .scalar(c)
    }
  }
  mutating func nameUntil(_ terminator: UInt32) throws -> String {
    let start = position
    while let c = peek, c != terminator { position += 1 }
    let result = String(String.UnicodeScalarView(input[start..<position]))
    try require(terminator)
    guard !result.isEmpty else { throw SchemaError.invalidSchema("Empty capture/property name") }
    return result
  }
  mutating func captureName() throws -> String {
    var scalars: [UnicodeScalar] = []
    while let code = peek, code != 62 {
      if eat(92) {
        guard peek == 117, case .scalar(let value) = try escaped(inClass: false),
          let scalar = UnicodeScalar(value)
        else { throw SchemaError.invalidSchema("Invalid capture name escape") }
        scalars.append(scalar)
      } else {
        scalars.append(input[position])
        position += 1
      }
    }
    try require(62)
    guard let first = scalars.first, first.properties.isIDStart || first == "$" || first == "_",
      scalars.dropFirst().allSatisfy({
        $0.properties.isIDContinue || $0 == "$" || $0 == "_" || $0.value == 0x200C
          || $0.value == 0x200D
      })
    else { throw SchemaError.invalidSchema("Invalid capture name") }
    return String(String.UnicodeScalarView(scalars))
  }
  mutating func classAtom() throws -> [PatternClass] {
    if eat(92) {
      let escaped = try escaped(inClass: true)
      if case .characterClass(let list, false) = escaped { return list }
      if case .scalar(let scalar) = escaped { return [.range(scalar, scalar)] }
      throw SchemaError.invalidSchema("Invalid character class escape")
    }
    let c = peek!
    position += 1
    return [.range(c, c)]
  }
  mutating func hex(_ length: Int) throws -> UInt32 {
    var text = ""
    for _ in 0..<length {
      guard let c = peek, let scalar = UnicodeScalar(c) else {
        throw SchemaError.invalidSchema("Incomplete regex escape")
      }
      text.unicodeScalars.append(scalar)
      position += 1
    }
    guard let value = UInt32(text, radix: 16) else {
      throw SchemaError.invalidSchema("Invalid regex hexadecimal escape")
    }
    return value
  }
  mutating func escaped(inClass: Bool) throws -> PatternExpression {
    guard let c = peek else {
      throw SchemaError.invalidSchema("Trailing regular expression escape")
    }
    position += 1
    switch c {
    case 100, 68: return .characterClass([.digits(c == 100)], false)
    case 119, 87: return .characterClass([.word(c == 119)], false)
    case 115, 83: return .characterClass([.whitespace(c == 115)], false)
    case 98: return inClass ? .scalar(8) : .boundary(true)
    case 66:
      guard !inClass else { throw SchemaError.invalidSchema("Invalid character class escape") }
      return .boundary(false)
    case 116: return .scalar(9)
    case 110: return .scalar(10)
    case 114: return .scalar(13)
    case 102: return .scalar(12)
    case 118: return .scalar(11)
    case 99:
      guard let code = peek, (65...90).contains(code) || (97...122).contains(code) else {
        throw SchemaError.invalidSchema("Invalid control escape")
      }
      position += 1
      return .scalar(code % 32)
    case 120: return .scalar(try hex(2))
    case 117:
      var scalar: UInt32
      if eat(123) {
        let name = try nameUntil(125)
        guard let code = UInt32(name, radix: 16), code <= 0x10FFFF else {
          throw SchemaError.invalidSchema("Invalid code point escape")
        }
        scalar = code
      } else {
        scalar = try hex(4)
      }
      if (0xD800...0xDBFF).contains(scalar), peek == 92, position + 1 < input.count,
        input[position + 1].value == 117
      {
        position += 2
        let low = try hex(4)
        guard (0xDC00...0xDFFF).contains(low) else {
          throw SchemaError.invalidSchema("Invalid regex surrogate pair")
        }
        scalar = 0x10000 + (scalar - 0xD800) * 1024 + low - 0xDC00
      }
      return .scalar(scalar)
    case 112, 80:
      try require(123)
      let property = try nameUntil(125)
      let regex = try NSRegularExpression(pattern: "\\A\\p{" + property + "}\\z")
      return .characterClass([.property(regex, c == 112)], false)
    case 107 where !inClass:
      try require(60)
      return .namedReference(Data(try captureName().utf8))
    case 48:
      guard peek == nil || !(48...57).contains(peek!) else {
        throw SchemaError.invalidSchema("Invalid decimal escape")
      }
      return .scalar(0)
    case 49...57 where !inClass:
      position -= 1
      guard let number = digits() else {
        throw SchemaError.invalidSchema("Backreference is too large")
      }
      return .backreference(number)
    default:
      guard
        "^$\\.*+?()[]{}|/".unicodeScalars.contains(where: { $0.value == c }) || (inClass && c == 45)
      else { throw SchemaError.invalidSchema("Invalid identity escape") }
      return .scalar(c)
    }
  }
}

private struct PatternState {
  var position: Int
  var captures: [Int: Range<Int>] = [:]
}

private struct PatternMachine {
  let input: [UnicodeScalar]
  let names: [Data: Int]
  mutating func run(_ expression: PatternExpression, state: PatternState, direction: Int = 1)
    -> [PatternState]
  {
    let character = direction > 0 ? state.position : state.position - 1
    let inBounds = input.indices.contains(character)
    switch expression {
    case .sequence(let terms):
      var states = [state]
      for term in direction > 0 ? terms : Array(terms.reversed()) {
        var next: [PatternState] = []
        for s in states { next += run(term, state: s, direction: direction) }
        states = next
        if states.isEmpty { break }
      }
      return states
    case .choice(let choices):
      var matches: [PatternState] = []
      for choice in choices { matches += run(choice, state: state, direction: direction) }
      return matches
    case .scalar(let scalar):
      return consume(
        state, accepts: inBounds && input[character].value == scalar, direction: direction)
    case .characterClass(let classes, let negative):
      return consume(
        state, accepts: inBounds && classes.contains { $0.accepts(input[character]) } != negative,
        direction: direction)
    case .dot:
      return consume(
        state, accepts: inBounds && ![10, 13, 0x2028, 0x2029].contains(input[character].value),
        direction: direction)
    case .start: return state.position == 0 ? [state] : []
    case .end: return state.position == input.count ? [state] : []
    case .boundary(let positive):
      let previous =
        state.position > 0 && PatternClass.word(true).accepts(input[state.position - 1])
      let next =
        state.position < input.count && PatternClass.word(true).accepts(input[state.position])
      return (previous != next) == positive ? [state] : []
    case .group(let body, let capture):
      return run(body, state: state, direction: direction).map { result in
        var copy = result
        copy.captures[capture] =
          min(state.position, result.position)..<max(state.position, result.position)
        return copy
      }
    case .repeatPattern(let body, let minimum, let maximum, let greedy):
      let limit = maximum ?? max(input.count + 1, minimum)
      let cleared = body.captureIDs
      var pending: [(PatternState, Int, Bool)] = [(state, 0, false)]
      var matches: [PatternState] = []
      while let (current, count, accepting) = pending.popLast() {
        if accepting {
          matches.append(current)
          continue
        }
        if count >= minimum {
          if greedy { pending.append((current, count, true)) } else { matches.append(current) }
        }
        guard count < limit else { continue }
        var iteration = current
        for capture in cleared { iteration.captures.removeValue(forKey: capture) }
        let next = run(body, state: iteration, direction: direction)
        for result in next.reversed() where result.position != current.position || count < minimum {
          pending.append((result, count + 1, false))
        }
      }
      return matches
    case .look(let body, let positive, let behind):
      let results = run(body, state: state, direction: behind ? -1 : 1)
      if !positive { return results.isEmpty ? [state] : [] }
      guard var result = results.first else { return [] }
      result.position = state.position
      return [result]
    case .namedReference(let name):
      return backreference(names[name]!, state: state, direction: direction)
    case .backreference(let index): return backreference(index, state: state, direction: direction)
    }
  }
  func consume(_ state: PatternState, accepts: Bool, direction: Int) -> [PatternState] {
    guard accepts else { return [] }
    var next = state
    next.position += direction
    return [next]
  }
  func backreference(_ index: Int, state: PatternState, direction: Int) -> [PatternState] {
    guard let range = state.captures[index] else { return [state] }
    let end = state.position + direction * range.count
    guard end >= 0 && end <= input.count,
      input[range].elementsEqual(input[min(state.position, end)..<max(state.position, end)])
    else { return [] }
    var result = state
    result.position = end
    return [result]
  }
}
