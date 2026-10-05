// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2026 Xudong Xu

import Foundation
import JSONValue
import Testing

@Suite("RFC 8259 fixture conformance")
struct JSONConformance {
  @Test func officialDocuments() throws {
    let directory = Bundle.module.resourceURL!.appendingPathComponent("JSONTestSuite/test_parsing")
    let files = try FileManager.default.contentsOfDirectory(
      at: directory, includingPropertiesForKeys: nil
    ).filter { $0.pathExtension == "json" }
    #expect(files.count > 250)
    var accepted = 0
    var rejected = 0
    var defined = 0
    for file in files {
      let data = try Data(contentsOf: file)
      let value = try? JSONValue.parse(data)
      let name = file.lastPathComponent
      if name.hasPrefix("y_") {
        accepted += 1
        #expect(value != nil, Comment(rawValue: name))
        if let value {
          let emission = try value.serialized()
          #expect(try JSONValue.parse(emission).serialized() == emission)
        }
      } else if name.hasPrefix("n_") {
        rejected += 1
        #expect(value == nil, Comment(rawValue: name))
      } else {
        defined += 1
        let repeated = try? JSONValue.parse(data)
        #expect(value == repeated, Comment(rawValue: name))
      }
    }
    print(
      "JSONTestSuite: \(accepted) must accept, \(rejected) must reject, \(defined) implementation-defined"
    )
  }
}
