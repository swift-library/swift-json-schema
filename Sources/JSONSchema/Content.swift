// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2026 Xudong Xu

import Foundation

/// Content evaluation is opt-in; JSON Schema treats these keywords as annotations.
enum ContentDecoding {
  static func decode(_ text: String, encoding: String?) -> Data? {
    switch encoding?.lowercased() {
    case nil, "binary", "8bit": return Data(text.utf8)
    case "7bit": return text.utf8.allSatisfy { $0 < 128 } ? Data(text.utf8) : nil
    case "base64":
      let compact = text.filter { !" \t\r\n".contains($0) }
      return Data(base64Encoded: compact)
    case "quoted-printable":
      let bytes = Array(text.utf8)
      var output: [UInt8] = []
      var position = 0
      while position < bytes.count {
        let byte = bytes[position]
        position += 1
        if byte != 61 {
          output.append(byte)
          continue
        }
        guard position + 1 < bytes.count else { return nil }
        if bytes[position] == 13 && bytes[position + 1] == 10 {
          position += 2
          continue
        }
        guard
          let value = UInt8(
            String(decoding: bytes[position...(position + 1)], as: UTF8.self), radix: 16)
        else { return nil }
        output.append(value)
        position += 2
      }
      return Data(output)
    default: return Data(text.utf8)
    }
  }
}
