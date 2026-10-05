// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2026 Xudong Xu

import JSONSchemaMacros
import SwiftParser
import SwiftSyntax
import SwiftSyntaxMacroExpansion
import Testing

@Suite struct MacroDiagnostics {
  @Test func missingTypeOffersRepair() throws {
    let file = Parser.parse(source: "@Schemable struct Record { var value = 3 }")
    let declaration = try #require(file.statements.first?.item.as(StructDeclSyntax.self))
    let attribute = try #require(declaration.attributes.first?.as(AttributeSyntax.self))
    let context = BasicMacroExpansionContext()
    _ = try SchemableMacro.expansion(
      of: attribute, providingMembersOf: declaration, conformingTo: [], in: context)
    #expect(context.diagnostics.count == 1)
    #expect(context.diagnostics[0].message == "A schema property requires an explicit type")
    #expect(context.diagnostics[0].fixIts.count == 1)
  }

  @Test func unsupportedWireTypeOffersRepair() throws {
    let file = Parser.parse(source: "@Schemable struct Record { var callback: () -> Void }")
    let declaration = try #require(file.statements.first?.item.as(StructDeclSyntax.self))
    let attribute = try #require(declaration.attributes.first?.as(AttributeSyntax.self))
    let context = BasicMacroExpansionContext()
    _ = try SchemableMacro.expansion(
      of: attribute, providingMembersOf: declaration, conformingTo: [], in: context)
    #expect(context.diagnostics.count == 1)
    #expect(!context.diagnostics[0].fixIts.isEmpty)
  }

  @Test func negativeConstraintOffersRepair() throws {
    let file = Parser.parse(
      source: "struct Record { @SchemaConstraint(minLength: -1) var value: String }")
    let structure = try #require(file.statements.first?.item.as(StructDeclSyntax.self))
    let property = try #require(
      structure.memberBlock.members.first?.decl.as(VariableDeclSyntax.self))
    let attribute = try #require(property.attributes.first?.as(AttributeSyntax.self))
    let context = BasicMacroExpansionContext()
    _ = try ConstraintMacro.expansion(of: attribute, providingPeersOf: property, in: context)
    #expect(context.diagnostics.count == 1)
    #expect(context.diagnostics[0].message == "minLength must be nonnegative")
    #expect(context.diagnostics[0].fixIts.count == 1)
  }

  @Test func blockDocumentationAndDeprecationBecomeAnnotations() throws {
    let file = Parser.parse(
      source:
        "/** A documented record. */\n@Schemable struct Record { @available(*, deprecated) var value: String }"
    )
    let structure = try #require(file.statements.first?.item.as(StructDeclSyntax.self))
    let attribute = try #require(structure.attributes.first?.as(AttributeSyntax.self))
    let context = BasicMacroExpansionContext()
    let members = try SchemableMacro.expansion(
      of: attribute, providingMembersOf: structure, conformingTo: [], in: context)
    let source = members.map(\.description).joined()
    #expect(context.diagnostics.isEmpty)
    #expect(source.contains("A documented record."))
    #expect(source.contains("[\"deprecated\"] = .bool(true)"))
  }
}
