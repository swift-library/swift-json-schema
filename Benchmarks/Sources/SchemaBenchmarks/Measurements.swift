// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2026 Xudong Xu

import Benchmark
import Foundation
import JSONSchema
import JSONValue

@main enum Measurements {
  static func main() async throws {
    let values = JSONValue.array(
      (0..<1_000).map {
        [
          "id": .number(JSONNumber($0)), "name": .string("item-\($0)"),
          "active": .bool($0 % 2 == 0),
        ]
      })
    let text = try values.serialized()
    let definition: JSONValue = [
      "type": "array",
      "items": [
        "type": "object",
        "properties": [
          "id": ["type": "integer", "minimum": 0], "name": ["type": "string", "minLength": 1],
          "active": ["type": "boolean"],
        ], "required": ["id", "name", "active"], "additionalProperties": false,
      ],
    ]
    let validator = try SchemaCompiler().compile(definition)
    let suite = BenchmarkSuite(
      "JSON workloads", configuration: .init(warmup: .iterations(10), iterations: .iterations(100))
    ) {
      Benchmark("parse-1000-records") { try blackHole(JSONValue.parse(text)) }
      Benchmark("canonicalize-1000-records") { try blackHole(values.serialized(.canonical)) }
      Benchmark("compile-array-schema") { try blackHole(SchemaCompiler().compile(definition)) }
      Benchmark("validate-1000-records") { blackHole(validator.validate(values)) }
    }
    let measurements = try await BenchmarkRunner().run(suite)
    var rows: [JSONValue] = []
    for result in measurements {
      let samples = result.measurement.samples.map(\.durationNanoseconds).sorted()
      let mean = Double(samples.reduce(0, +)) / Double(samples.count)
      rows.append([
        "name": .string(result.caseName), "iterations": .number(JSONNumber(samples.count)),
        "mean_ns": .number(try JSONNumber(mean)),
        "median_ns": .number(JSONNumber(samples[samples.count / 2])),
        "p95_ns": .number(JSONNumber(samples[Int(ceil(Double(samples.count) * 0.95)) - 1])),
      ])
    }
    let report: JSONValue = [
      "records": 1000, "input_bytes": .number(JSONNumber(text.utf8.count)), "warmup": 10,
      "measurements": .array(rows),
    ]
    print(try report.serialized(.pretty))
  }
}
