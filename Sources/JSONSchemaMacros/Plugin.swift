// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2026 Xudong Xu

import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct SchemaPlugin: CompilerPlugin {
  let providingMacros: [any Macro.Type] = [SchemableMacro.self, ConstraintMacro.self]
}
