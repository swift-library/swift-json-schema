// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2026 Xudong Xu

import JSONSchema
import JSONValue

func validationExample() throws {
  let definition: JSONValue = ["type": "integer", "minimum": 0]
  let validator = try SchemaCompiler().compile(definition)
  let result = validator.validate(42)
  precondition(result.valid)
  precondition(result.output(.flag) == ["valid": true])
}
