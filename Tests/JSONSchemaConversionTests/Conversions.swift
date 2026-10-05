// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2026 Xudong Xu

import Foundation
import JSONSchemaBuilder
import JSONSchemaConversion
import Testing

@Suite struct Conversions {
  @Test func preciseFoundationValues() throws {
    #expect(
      try FoundationSchema.url.decode(from: JSONValue.string("https://example.test/a")).host
        == "example.test")
    #expect(
      try FoundationSchema.uuid.decode(
        from: JSONValue.string("123e4567-e89b-12d3-a456-426614174000")
      ).uuidString.lowercased() == "123e4567-e89b-12d3-a456-426614174000")
    #expect(
      try FoundationSchema.date.decode(from: JSONValue.string("1970-01-01T00:00:00Z"))
        .timeIntervalSince1970 == 0)
    #expect(
      try FoundationSchema.decimal.decode(from: JSONValue.parse("0.1234567890123456789"))
        == Decimal(string: "0.1234567890123456789"))
    #expect(throws: SchemaDecodingError.self) {
      try FoundationSchema.decimal.decode(
        from: JSONValue.parse("0.123456789012345678901234567890123456789012345678901"))
    }
    #expect(try FoundationSchema.data.decode(from: JSONValue.string("AQID")) == Data([1, 2, 3]))
    #expect(throws: SchemaDecodingError.self) {
      try FoundationSchema.data.decode(from: JSONValue.string("AR=="))
    }
  }
}
