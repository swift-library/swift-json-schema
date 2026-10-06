// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2026 Xudong Xu

/// Transforms Codable property keys using identity, snake case, or kebab case.
public enum JSONKeyStrategy: Sendable {
  case identity
  case snakeCase
  case kebabCase

  /// Converts a property key for encoding, splitting uppercase word boundaries.
  public func key(_ text: String) -> String {
    if self == .identity { return text }
    let characters = Array(text)
    var result = ""
    let separator = self == .snakeCase ? "_" : "-"
    for i in characters.indices {
      let character = characters[i]
      if i > 0, character.isUppercase,
        characters[i - 1].isLowercase
          || (i + 1 < characters.count && characters[i + 1].isLowercase
            && characters[i - 1].isUppercase)
      {
        result += separator
      }
      result += String(character).lowercased()
    }
    return result
  }
  func sourceKey(_ text: String) -> String {
    if self == .identity { return text }
    let separator: Character = self == .snakeCase ? "_" : "-"
    let words = text.split(separator: separator, omittingEmptySubsequences: false)
    guard let first = words.first else { return text }
    return String(first)
      + words.dropFirst().map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined()
  }
}
