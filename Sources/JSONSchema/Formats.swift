// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2026 Xudong Xu

import Foundation
import JSONValue

#if canImport(Darwin)
  import Darwin
#else
  import Glibc
#endif

/// Standard format assertions. Unrecognized formats remain annotations.
public enum FormatValidation {
  public static func matches(_ text: String, format: String, dialect: Dialect = .draft2020) -> Bool
  {
    switch format {
    case "date": return date(text)
    case "time": return time(text) != nil
    case "date-time":
      let pieces = text.split(whereSeparator: { $0 == "T" || $0 == "t" })
      guard pieces.count == 2, date(String(pieces[0])), let parsed = time(String(pieces[1])) else {
        return false
      }
      if parsed.leap {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = String(pieces[0]).split(separator: "-").compactMap { Int($0) }
        let day = calendar.date(
          from: DateComponents(year: components[0], month: components[1], day: components[2]))!
        let utcDay = calendar.date(byAdding: .day, value: parsed.dayOffset, to: day)!
        let fields = calendar.dateComponents([.month, .day], from: utcDay)
        return (fields.month == 6 && fields.day == 30) || (fields.month == 12 && fields.day == 31)
      }
      return true
    case "duration":
      let integer = "[0-9]+"
      let clock =
        "(?:" + integer + "H(?:" + integer + "M(?:" + integer + "S)?)?|" + integer + "M(?:"
        + integer + "S)?|" + integer + "S)"
      let days =
        "(?:" + integer + "Y(?:" + integer + "M(?:" + integer + "D)?)?|" + integer + "M(?:"
        + integer + "D)?|" + integer + "D)"
      return match(text, "P(?:" + integer + "W|" + days + "(?:T" + clock + ")?|T" + clock + ")")
    case "email": return email(text, international: false)
    case "idn-email": return email(text, international: true)
    case "hostname":
      return hostname(text)
        && ([Dialect.draft4, .draft6].contains(dialect) || internationalHostname(text))
    case "idn-hostname": return internationalHostname(text)
    case "ipv4": return ipv4(text)
    case "ipv6": return ip(text, family: AF_INET6)
    case "uuid":
      return match(
        text, "[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}")
    case "uri": return uri(text, relative: false, international: false)
    case "uri-reference": return uri(text, relative: true, international: false)
    case "iri": return uri(text, relative: false, international: true)
    case "iri-reference": return uri(text, relative: true, international: true)
    case "uri-template": return template(text)
    case "json-pointer": return !text.hasPrefix("#") && (try? JSONPointer(text)) != nil
    case "relative-json-pointer": return (try? RelativeJSONPointer(text)) != nil
    case "regex": return (try? ECMARegularExpression(text)) != nil
    default: return true
    }
  }
  private static func match(_ text: String, _ pattern: String) -> Bool {
    let expression = try! NSRegularExpression(pattern: "\\A(?:" + pattern + ")\\z")
    return expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
  }
  private static func date(_ text: String) -> Bool {
    guard match(text, "[0-9]{4}-[0-9]{2}-[0-9]{2}") else { return false }
    let fields = text.split(separator: "-").map { Int($0)! }
    let year = fields[0]
    let month = fields[1]
    let day = fields[2]
    guard (1...12).contains(month) else { return false }
    let leap = year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
    return day >= 1
      && day <= [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][month - 1]
  }
  private static func time(_ text: String) -> (leap: Bool, dayOffset: Int)? {
    guard match(text, "[0-9]{2}:[0-9]{2}:[0-9]{2}(?:\\.[0-9]+)?(?:[Zz]|[+-][0-9]{2}:[0-9]{2})")
    else { return nil }
    let characters = Array(text)
    let hour = Int(String(characters[0..<2]))!
    let minute = Int(String(characters[3..<5]))!
    let second = Int(String(characters[6..<8]))!
    guard hour <= 23, minute <= 59, second <= 60 else { return nil }
    var offset = 0
    if characters.last != "Z" && characters.last != "z" {
      let zone = Array(characters.suffix(6))
      let h = Int(String(zone[1..<3]))!
      let m = Int(String(zone[4..<6]))!
      guard h < 24, m < 60 else { return nil }
      offset = (zone[0] == "-" ? -1 : 1) * (h * 60 + m)
    }
    let utc = hour * 60 + minute - offset
    if second == 60 && (utc % 1440 + 1440) % 1440 != 1439 { return nil }
    return (second == 60, utc < 0 ? -1 : utc >= 1440 ? 1 : 0)
  }
  private static func ip(_ text: String, family: Int32) -> Bool {
    guard !text.contains("%") else { return false }
    if family == AF_INET6, text.contains(".") {
      guard let tail = text.split(separator: ":").last, ipv4(String(tail)) else { return false }
    }
    var storage = [UInt8](repeating: 0, count: 16)
    return text.withCString { inet_pton(family, $0, &storage) } == 1
  }
  private static func ipv4(_ text: String) -> Bool {
    let parts = text.split(separator: ".", omittingEmptySubsequences: false)
    return parts.count == 4
      && parts.allSatisfy { part in
        guard let value = Int(part), (0...255).contains(value), String(value) == part else {
          return false
        }
        return part.utf8.allSatisfy { (48...57).contains($0) }
      }
  }
  private static func hostname(_ text: String) -> Bool {
    guard !text.isEmpty, text.utf8.count <= 253, !text.hasSuffix(".") else { return false }
    return text.split(separator: ".", omittingEmptySubsequences: false).allSatisfy { label in
      label.utf8.count <= 63 && match(String(label), "[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?")
    }
  }
  private static func email(_ text: String, international: Bool) -> Bool {
    guard text.utf8.count <= 254, let delimiter = text.lastIndex(of: "@") else { return false }
    let local = String(text[..<delimiter])
    let domain = String(text[text.index(after: delimiter)...])
    guard !local.isEmpty, local.utf8.count <= 64 else { return false }
    let atom = "!#$%&'*+-/=?^_`{|}~"
    if local.first == "\"" && local.last == "\"" {
      var escaped = false
      for scalar in local.dropFirst().dropLast().unicodeScalars {
        if escaped {
          guard scalar.value >= 32 && scalar.value != 127 && (international || scalar.value <= 126)
          else { return false }
          escaped = false
        } else if scalar == "\\" {
          escaped = true
        } else if scalar == "\"" || scalar.value < 32 || scalar.value == 127
          || (!international && scalar.value > 126)
        {
          return false
        }
      }
      if escaped { return false }
    } else {
      let dots = local.split(separator: ".", omittingEmptySubsequences: false)
      guard dots.allSatisfy({ !$0.isEmpty }) else { return false }
      for part in dots {
        for c in part.unicodeScalars {
          if (48...57).contains(c.value) || (65...90).contains(c.value)
            || (97...122).contains(c.value) || atom.unicodeScalars.contains(c)
          {
            continue
          }
          if !international || c.value < 128 { return false }
        }
      }
    }
    if domain.hasPrefix("[") && domain.hasSuffix("]") {
      let address = String(domain.dropFirst().dropLast())
      if address.lowercased().hasPrefix("ipv6:") {
        return ip(String(address.dropFirst(5)), family: AF_INET6)
      }
      return ipv4(address)
    }
    return international ? internationalHostname(domain) : hostname(domain)
  }
  private static func percentValid(_ text: String) -> Bool {
    let bytes = Array(text.utf8)
    var i = 0
    while i < bytes.count {
      if bytes[i] == 37 {
        guard i + 2 < bytes.count,
          bytes[(i + 1)...(i + 2)].allSatisfy({
            (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0)
          })
        else { return false }
        i += 3
      } else {
        i += 1
      }
    }
    return true
  }
  private static func uri(_ text: String, relative: Bool, international: Bool) -> Bool {
    guard percentValid(text), text.filter({ $0 == "#" }).count <= 1 else { return false }
    let allowed =
      "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~:/?#[]@!$&'()*+,;=%"
    for scalar in text.unicodeScalars {
      if allowed.unicodeScalars.contains(scalar) { continue }
      guard international, scalar.value >= 0xA0, scalar.value != 0xFFFE, scalar.value != 0xFFFF,
        scalar.properties.generalCategory != .control, !scalar.properties.isWhitespace
      else { return false }
    }
    let schemePattern = try! NSRegularExpression(pattern: "\\A[A-Za-z][A-Za-z0-9+.-]*:")
    let scheme = schemePattern.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
    if !relative && scheme == nil { return false }
    var rest = text
    if let scheme {
      rest = String((text as NSString).substring(from: scheme.range.length))
    } else if text.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false).first?
      .contains(":") == true
    {
      return false
    }
    if rest.hasPrefix("//") {
      let authority = String(rest.dropFirst(2).prefix(while: { !"/?#".contains($0) }))
      if let delimiter = authority.firstIndex(of: "@") {
        let userInfo = authority[..<delimiter]
        let allowedUserInfo =
          "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~!$&'()*+,;=:%"
        if userInfo.unicodeScalars.contains(where: {
          $0.value < 128 && !allowedUserInfo.unicodeScalars.contains($0)
        }) {
          return false
        }
      }
      let hostPort = String(authority.split(separator: "@", omittingEmptySubsequences: false).last!)
      if authority.filter({ $0 == "@" }).count > 1 { return false }
      if hostPort.hasPrefix("[") {
        guard let close = hostPort.firstIndex(of: "]") else { return false }
        let host = String(hostPort[hostPort.index(after: hostPort.startIndex)..<close])
        guard
          ip(host, family: AF_INET6)
            || match(host, "[Vv][0-9A-Fa-f]+\\.[A-Za-z0-9._~!$&'()*+,;=:-]+")
        else { return false }
        let port = String(hostPort[hostPort.index(after: close)...])
        if !port.isEmpty && !match(port, ":[0-9]*") { return false }
      } else {
        if hostPort.contains("[") || hostPort.contains("]") { return false }
        let parts = hostPort.split(separator: ":", omittingEmptySubsequences: false)
        if parts.count > 2
          || (parts.count == 2 && !parts[1].utf8.allSatisfy({ (48...57).contains($0) }))
        {
          return false
        }
      }
      rest = String(rest.dropFirst(2 + authority.count))
    }
    return !rest.contains("[") && !rest.contains("]")
  }
  private static func template(_ text: String) -> Bool {
    let input = Array(text.unicodeScalars)
    var i = 0
    while i < input.count {
      if input[i] == "{" {
        i += 1
        let begin = i
        while i < input.count && input[i] != "}" { i += 1 }
        guard i < input.count else { return false }
        var expression = String(String.UnicodeScalarView(input[begin..<i]))
        i += 1
        if let c = expression.first, "+#./;?&".contains(c) { expression.removeFirst() }
        let vars = expression.split(separator: ",", omittingEmptySubsequences: false)
        for variable in vars {
          guard
            match(
              String(variable),
              "(?:[A-Za-z0-9_]|%[0-9A-Fa-f]{2})+(?:\\.(?:[A-Za-z0-9_]|%[0-9A-Fa-f]{2})+)*(?:\\*|:[1-9][0-9]{0,3})?"
            )
          else { return false }
        }
      } else {
        let begin = i
        while i < input.count && input[i] != "{" {
          guard input[i] != "}", input[i].value > 32, input[i].value != 127 else { return false }
          i += 1
        }
        if !percentValid(String(String.UnicodeScalarView(input[begin..<i]))) { return false }
      }
    }
    return true
  }

  private static func internationalHostname(_ text: String) -> Bool {
    let mapped = text.precomposedStringWithCompatibilityMapping.lowercased().replacingOccurrences(
      of: "\u{200B}", with: ""
    )
    .replacingOccurrences(of: "。", with: ".").replacingOccurrences(of: "．", with: ".")
    .replacingOccurrences(of: "｡", with: ".")
    guard !mapped.isEmpty else { return false }
    let labels = mapped.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
    var unicode: [String] = []
    var encoded: [String] = []
    for label in labels {
      guard !label.isEmpty else { return false }
      let decoded: String
      if label.hasPrefix("xn--") {
        guard let u = Punycode.decode(String(label.dropFirst(4))),
          !u.unicodeScalars.allSatisfy({ $0.value < 128 }),
          Punycode.encode(u) == String(label.dropFirst(4))
        else { return false }
        decoded = u
      } else {
        decoded = label
      }
      guard validIDNALabel(decoded) else { return false }
      let ascii =
        decoded.unicodeScalars.allSatisfy { $0.value < 128 }
        ? decoded : "xn--" + (Punycode.encode(decoded) ?? "")
      guard ascii.utf8.count <= 63 else { return false }
      unicode.append(decoded)
      encoded.append(ascii)
    }
    guard encoded.joined(separator: ".").utf8.count <= 253 else { return false }
    let bidi = unicode.contains {
      $0.unicodeScalars.contains {
        (0x590...0x8FF).contains($0.value) && !(0x6F0...0x6F9).contains($0.value)
      }
    }
    if bidi {
      for label in unicode {
        let chars = Array(label.unicodeScalars)
        let first = chars.first!
        let rtl = (0x590...0x8FF).contains(first.value)
        if first.properties.generalCategory == .decimalNumber { return false }
        if !rtl && chars.contains(where: { (0x590...0x8FF).contains($0.value) }) { return false }
        if rtl {
          if chars.contains(where: { (65...90).contains($0.value) || (97...122).contains($0.value) }
          ) {
            return false
          }
          if chars.contains(where: { (48...57).contains($0.value) })
            && chars.contains(where: { (0x660...0x669).contains($0.value) })
          {
            return false
          }
        }
      }
    }
    return true
  }
  private static func validIDNALabel(_ text: String) -> Bool {
    let chars = Array(text.unicodeScalars)
    guard let first = chars.first, chars.last != "-", first != "-" else { return false }
    if [.nonspacingMark, .spacingMark, .enclosingMark].contains(first.properties.generalCategory) {
      return false
    }
    if chars.count >= 4 && chars[2] == "-" && chars[3] == "-" { return false }
    if chars.contains(where: { (0x660...0x669).contains($0.value) })
      && chars.contains(where: { (0x6F0...0x6F9).contains($0.value) })
    {
      return false
    }
    for (i, c) in chars.enumerated() {
      let n = c.value
      if [0x640, 0x7FA, 0x302E, 0x302F, 0x303B].contains(n) || (0x3031...0x3035).contains(n) {
        return false
      }
      if [0xDF, 0x3C2, 0xF0B, 0x3007, 0x6FD, 0x6FE].contains(n) { continue }
      if n == 0xB7 {
        if i == 0 || i + 1 == chars.count || chars[i - 1] != "l" || chars[i + 1] != "l" {
          return false
        }
        continue
      }
      if n == 0x375 {
        if i + 1 == chars.count || !(0x370...0x3FF).contains(chars[i + 1].value) { return false }
        continue
      }
      if n == 0x5F3 || n == 0x5F4 {
        if i == 0 || !(0x590...0x5FF).contains(chars[i - 1].value) { return false }
        continue
      }
      if n == 0x30FB {
        if !chars.contains(where: {
          (0x3040...0x30FA).contains($0.value) || (0x4E00...0x9FFF).contains($0.value)
        }) {
          return false
        }
        continue
      }
      if n == 0x200C || n == 0x200D {
        let virama = i > 0 && chars[i - 1].properties.canonicalCombiningClass.rawValue == 9
        let joining =
          n == 0x200C && i > 0 && i + 1 < chars.count
          && (0x600...0x6FF).contains(chars[i - 1].value)
          && (0x600...0x6FF).contains(chars[i + 1].value)
        if !virama && !joining { return false }
        continue
      }
      if n == 45 { continue }
      if ![
        .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter,
        .decimalNumber, .nonspacingMark, .spacingMark,
      ].contains(c.properties.generalCategory) {
        return false
      }
    }
    return true
  }
}

private enum Punycode {
  static func adapt(_ delta: Int, _ count: Int, first: Bool) -> Int {
    var d = first ? delta / 700 : delta / 2
    d += d / count
    var k = 0
    while d > 455 {
      d /= 35
      k += 36
    }
    return k + 36 * d / (d + 38)
  }
  static func digit(_ c: UInt32) -> Int? {
    if (97...122).contains(c) { return Int(c - 97) }
    if (48...57).contains(c) { return Int(c - 22) }
    return nil
  }
  static func character(_ d: Int) -> String { String(UnicodeScalar(d < 26 ? d + 97 : d + 22)!) }
  static func decode(_ text: String) -> String? {
    let input = Array(text.lowercased().unicodeScalars)
    var output: [UInt32] = []
    var position = 0
    if let delimiter = input.lastIndex(of: "-") {
      output = input[..<delimiter].map(\.value)
      position = delimiter + 1
    }
    var n = 128
    var i = 0
    var bias = 72
    while position < input.count {
      let old = i
      var weight = 1
      var k = 36
      repeat {
        guard position < input.count, let d = digit(input[position].value) else { return nil }
        position += 1
        let (increment, overflow) = d.multipliedReportingOverflow(by: weight)
        let (sum, sumOverflow) = i.addingReportingOverflow(increment)
        guard !overflow && !sumOverflow else { return nil }
        i = sum
        let threshold = k <= bias ? 1 : k >= bias + 26 ? 26 : k - bias
        if d < threshold { break }
        let (next, weightOverflow) = weight.multipliedReportingOverflow(by: 36 - threshold)
        guard !weightOverflow else { return nil }
        weight = next
        k += 36
      } while true
      let size = output.count + 1
      bias = adapt(i - old, size, first: old == 0)
      n += i / size
      i %= size
      guard n <= 0x10FFFF, UnicodeScalar(n) != nil else { return nil }
      output.insert(UInt32(n), at: i)
      i += 1
    }
    return String(String.UnicodeScalarView(output.compactMap(UnicodeScalar.init)))
  }
  static func encode(_ text: String) -> String? {
    let input = text.unicodeScalars.map { Int($0.value) }
    var result = input.filter { $0 < 128 }.map { String(UnicodeScalar($0)!) }.joined()
    let basic = result.count
    var handled = basic
    var n = 128
    var delta = 0
    var bias = 72
    if basic > 0 { result += "-" }
    while handled < input.count {
      let m = input.filter { $0 >= n }.min()!
      delta += (m - n) * (handled + 1)
      n = m
      for c in input {
        if c < n { delta += 1 }
        if c == n {
          var q = delta
          var k = 36
          repeat {
            let threshold = k <= bias ? 1 : k >= bias + 26 ? 26 : k - bias
            if q < threshold { break }
            result += character(threshold + (q - threshold) % (36 - threshold))
            q = (q - threshold) / (36 - threshold)
            k += 36
          } while true
          result += character(q)
          bias = adapt(delta, handled + 1, first: handled == basic)
          delta = 0
          handled += 1
        }
      }
      delta += 1
      n += 1
    }
    return result
  }
}
