// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2026 Xudong Xu

import Foundation
import JSONSchema
import JSONSchemaBuilder
import JSONValue

public enum FoundationSchema {
  public static var url: SchemaComponent<URL> {
    Schema.string().format("uri").map { text in
      guard FormatValidation.matches(text, format: "uri"), let url = URL(string: text) else {
        throw SchemaDecodingError.extraction("Invalid absolute URL")
      }
      return url
    }
  }
  public static var uuid: SchemaComponent<UUID> {
    Schema.string().format("uuid").map { text in
      guard FormatValidation.matches(text, format: "uuid"), let uuid = UUID(uuidString: text) else {
        throw SchemaDecodingError.extraction("Invalid UUID")
      }
      return uuid
    }
  }
  public static var date: SchemaComponent<Date> {
    Schema.string().format("date-time").map { text in
      guard FormatValidation.matches(text, format: "date-time") else {
        throw SchemaDecodingError.extraction("Invalid RFC 3339 timestamp")
      }
      for fractional in [true, false] {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions =
          fractional ? [.withInternetDateTime, .withFractionalSeconds] : [.withInternetDateTime]
        if let date = formatter.date(from: text) { return date }
      }
      throw SchemaDecodingError.extraction("Timestamp cannot be represented by Date")
    }
  }
  public static var decimal: SchemaComponent<Decimal> {
    Schema.number().map { number in
      guard let value = Decimal(string: number.text, locale: Locale(identifier: "en_US_POSIX")),
        !value.isNaN,
        (try? JSONNumber(NSDecimalNumber(decimal: value).stringValue)) == number
      else { throw SchemaDecodingError.extraction("Number exceeds Decimal precision") }
      return value
    }
  }
  public static var data: SchemaComponent<Data> {
    Schema.string().keyword("contentEncoding", "base64").map { text in
      guard let data = Data(base64Encoded: text), data.base64EncodedString() == text else {
        throw SchemaDecodingError.extraction("Invalid canonical base64")
      }
      return data
    }
  }
}
extension URL: Schemable {
  public static func schemaDefinition(in context: inout SchemaContext) -> JSONValue {
    FoundationSchema.url.schema
  }
}
extension UUID: Schemable {
  public static func schemaDefinition(in context: inout SchemaContext) -> JSONValue {
    FoundationSchema.uuid.schema
  }
}
extension Date: Schemable {
  public static func schemaDefinition(in context: inout SchemaContext) -> JSONValue {
    FoundationSchema.date.schema
  }
}
extension Decimal: Schemable {
  public static func schemaDefinition(in context: inout SchemaContext) -> JSONValue {
    FoundationSchema.decimal.schema
  }
}
extension Data: Schemable {
  public static func schemaDefinition(in context: inout SchemaContext) -> JSONValue {
    FoundationSchema.data.schema
  }
}
