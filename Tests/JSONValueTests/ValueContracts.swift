// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2026 Xudong Xu

import Foundation
import JSONValue
import Testing

@Suite struct ValueContracts {
  @Test func decimalArithmeticHasNoBinaryTolerance() throws {
    #expect(try JSONNumber("1e999999999999999999999") > JSONNumber("1e999999999999999999998"))
    #expect(try JSONNumber("0.3").isMultiple(of: JSONNumber("0.1")))
    #expect(try !JSONNumber("0.30000000000000001").isMultiple(of: JSONNumber("0.1")))
    #expect(try JSONNumber("100e-2") == JSONNumber("1.0"))
    #expect(try JSONNumber("-0") == JSONNumber("0"))
    #expect(try JSONNumber("1e100").isInteger)
    #expect(try !JSONNumber("1e-100").isInteger)
    #expect(
      try JSONValue.parse("123456789012345678901234567890").serialized()
        == "123456789012345678901234567890")
  }

  @Test func exactKeysAndDuplicatePolicy() throws {
    let text = #"{"é":1,"e\u0301":2,"0":3,"é":4}"#
    let value = try JSONParser().parse(text)
    #expect(value.objectValue?.count == 3)
    #expect(value["é"] == 4)
    #expect(value["e\u{301}"] == 2)
    #expect(
      value.objectValue?.keys.map { Array($0.utf8) } == [
        Array("e\u{301}".utf8), Array("0".utf8), Array("é".utf8),
      ])
    #expect(try JSONParser(duplicateKeys: .first).parse(text)["é"] == 1)
    #expect(throws: JSONParseError.self) { try JSONParser(duplicateKeys: .reject).parse(text) }
  }

  @Test func pointersResolveByContainerKind() throws {
    let document: JSONValue = ["01": "object key", "a/b": ["~": [10, 20, 30]]]
    #expect(try JSONPointer("/01").resolve(in: document) == "object key")
    #expect(try JSONPointer("#/a~1b/~0/1").resolve(in: document) == 20)
    #expect(throws: JSONError.self) { try JSONPointer("/a~1b/~0/01").resolve(in: document) }
    #expect(
      try RelativeJSONPointer("0+1").resolve(in: document, from: JSONPointer("/a~1b/~0/1")) == 30)
    #expect(
      try RelativeJSONPointer("0#").resolve(in: document, from: JSONPointer("/a~1b/~0/1")) == 1)
    #expect(throws: JSONError.self) { try JSONPointer("/bad~2") }
  }

  @Test func parserFailureLocatesNestedValue() {
    do {
      _ = try JSONValue.parse("{\n  \"a/b\": [true, nope]\n}")
      Issue.record("Invalid token was accepted")
    } catch let error as JSONParseError {
      #expect(error.pointer.description == "/a~1b/1")
      #expect(error.line == 2)
      #expect(error.column == 18)
    } catch { Issue.record("Unexpected error: \(error)") }
  }

  @Test func canonicalThresholdsAndUTF16Ordering() throws {
    let document = try JSONValue.parse(
      #"{"\ue000":1,"😀":2,"a":-0,"n":[1e-6,1e-7,1e20,1e21,333333333.33333329]}"#)
    #expect(
      try document.serialized(.canonical)
        == #"{"a":0,"n":[0.000001,1e-7,100000000000000000000,1e+21,333333333.3333333],"😀":2,"":1}"#
    )
    #expect(throws: JSONError.self) { try JSONValue.parse("1e400").serialized(.canonical) }
  }

  @Test func codablePreservesNumbersAndFoundationWireValues() throws {
    struct Payload: Codable {
      let integer: UInt64
      let number: JSONNumber
      let data: Data
      let date: Date
      let optional: String?
    }
    let original = Payload(
      integer: UInt64.max, number: try JSONNumber("1.23456789012345678901234567890"),
      data: Data([0, 1, 2]), date: Date(timeIntervalSince1970: 0), optional: nil)
    let value = try JSONValueEncoder().encode(original)
    #expect(value["integer"]?.numberValue?.text == String(UInt64.max))
    #expect(value["date"] == "1970-01-01T00:00:00.000Z")
    let decoded = try JSONValueDecoder().decode(Payload.self, from: value)
    #expect(decoded.integer == original.integer)
    #expect(decoded.number == original.number)
    #expect(decoded.data == original.data)
    #expect(decoded.date == original.date)
    #expect(throws: DecodingError.self) { try JSONValueDecoder().decode(Int8.self, from: 128) }
  }

  @Test func canonicalIEEE754Vectors() throws {
    // RFC 8785 Appendix B specifies the canonical spelling of these bit patterns.
    let vectors: [(UInt64, String)] = [
      (0x0000_0000_0000_0000, "0"), (0x8000_0000_0000_0000, "0"),
      (0x0000_0000_0000_0001, "5e-324"), (0x8000_0000_0000_0001, "-5e-324"),
      (0x7fef_ffff_ffff_ffff, "1.7976931348623157e+308"),
      (0xffef_ffff_ffff_ffff, "-1.7976931348623157e+308"),
      (0x4340_0000_0000_0000, "9007199254740992"),
      (0xc340_0000_0000_0000, "-9007199254740992"),
      (0x4430_0000_0000_0000, "295147905179352830000"),
      (0x44b5_2d02_c7e1_4af5, "9.999999999999997e+22"),
      (0x44b5_2d02_c7e1_4af6, "1e+23"),
      (0x44b5_2d02_c7e1_4af7, "1.0000000000000001e+23"),
      (0x444b_1ae4_d6e2_ef4e, "999999999999999700000"),
      (0x444b_1ae4_d6e2_ef4f, "999999999999999900000"),
      (0x444b_1ae4_d6e2_ef50, "1e+21"),
      (0x3eb0_c6f7_a0b5_ed8c, "9.999999999999997e-7"),
      (0x3eb0_c6f7_a0b5_ed8d, "0.000001"),
      (0x41b3_de43_5555_5553, "333333333.3333332"),
      (0x41b3_de43_5555_5554, "333333333.33333325"),
      (0x41b3_de43_5555_5555, "333333333.3333333"),
      (0x41b3_de43_5555_5556, "333333333.3333334"),
      (0x41b3_de43_5555_5557, "333333333.33333343"),
      (0xbecb_f647_612f_3696, "-0.0000033333333333333333"),
      (0x4314_3ff3_c1cb_0959, "1424953923781206.2"),
    ]
    for (bits, spelling) in vectors {
      let value = JSONValue.number(try JSONNumber(Double(bitPattern: bits)))
      #expect(try value.serialized(.canonical) == spelling)
    }
    #expect(throws: JSONError.self) { try JSONNumber(Double.infinity) }
    #expect(throws: JSONError.self) { try JSONNumber(Double.nan) }
  }
}
