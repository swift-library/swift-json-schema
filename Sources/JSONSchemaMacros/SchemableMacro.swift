// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2026 Xudong Xu

import Foundation
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

private struct SchemaDiagnostic: DiagnosticMessage, FixItMessage {
  let message: String
  var diagnosticID: MessageID { MessageID(domain: "Schema", id: "declaration") }
  var fixItID: MessageID { MessageID(domain: "Schema", id: "annotation") }
  var severity: DiagnosticSeverity { .error }
}

public struct ConstraintMacro: PeerMacro {
  public static func expansion(
    of node: AttributeSyntax, providingPeersOf declaration: some DeclSyntaxProtocol,
    in context: some MacroExpansionContext
  ) throws -> [DeclSyntax] {
    guard let arguments = node.arguments?.as(LabeledExprListSyntax.self) else { return [] }
    for argument in arguments {
      guard let label = argument.label?.text,
        ["minLength", "maxLength", "minItems", "maxItems", "minProperties", "maxProperties"]
          .contains(label),
        let value = Int(
          argument.expression.trimmedDescription.replacingOccurrences(of: "_", with: "")), value < 0
      else { continue }
      let replacement = ExprSyntax(stringLiteral: "0")
      let fix = FixIt(
        message: SchemaDiagnostic(message: "Use a nonnegative count"),
        changes: [.replace(oldNode: Syntax(argument.expression), newNode: Syntax(replacement))])
      context.diagnose(
        Diagnostic(
          node: argument.expression,
          message: SchemaDiagnostic(message: label + " must be nonnegative"), fixIts: [fix]))
    }
    return []
  }
}

public struct SchemableMacro: MemberMacro, ExtensionMacro {
  public static func expansion(
    of node: AttributeSyntax, providingMembersOf declaration: some DeclGroupSyntax,
    conformingTo protocols: [TypeSyntax], in context: some MacroExpansionContext
  ) throws -> [DeclSyntax] {
    let access =
      declaration.modifiers.contains { $0.name.text == "public" || $0.name.text == "open" }
      ? "public " : declaration.modifiers.contains { $0.name.text == "package" } ? "package " : ""
    let generics = genericNames(declaration)
    let conditions =
      generics.isEmpty
      ? "" : " where " + generics.map { $0 + ": Schemable" }.joined(separator: ", ")
    let strategy =
      node.arguments?.as(LabeledExprListSyntax.self)?.first(where: {
        $0.label?.text == "keyStrategy"
      })?.expression.trimmedDescription ?? ".identity"
    var statements: [String] = []
    if let structure = declaration.as(StructDeclSyntax.self) {
      let keys = codingKeys(structure.memberBlock.members)
      statements = ["var properties = JSONObject()", "var required: [JSONValue] = []"]
      var ordinal = 0
      for member in structure.memberBlock.members {
        guard let variable = member.decl.as(VariableDeclSyntax.self),
          !variable.modifiers.contains(where: { ["static", "class"].contains($0.name.text) })
        else { continue }
        for binding in variable.bindings {
          if let accessor = binding.accessorBlock {
            switch accessor.accessors {
            case .getter: continue
            case .accessors(let list):
              if list.contains(where: {
                !["willSet", "didSet"].contains($0.accessorSpecifier.text)
              }) {
                continue
              }
            @unknown default: continue
            }
          }
          guard let identifier = binding.pattern.as(IdentifierPatternSyntax.self) else { continue }
          let name = identifier.identifier.text.replacingOccurrences(of: "`", with: "")
          if let keys, !keys.contains(name) { continue }
          guard let type = binding.typeAnnotation?.type else {
            var replacement = binding
            replacement.typeAnnotation = TypeAnnotationSyntax(
              type: IdentifierTypeSyntax(name: .identifier("<#Type#>")))
            let fix = FixIt(
              message: SchemaDiagnostic(message: "Add the property's wire type"),
              changes: [.replace(oldNode: Syntax(binding), newNode: Syntax(replacement))])
            context.diagnose(
              Diagnostic(
                node: binding,
                message: SchemaDiagnostic(message: "A schema property requires an explicit type"),
                fixIts: [fix]))
            continue
          }
          if type.is(FunctionTypeSyntax.self) || type.is(TupleTypeSyntax.self)
            || type.trimmedDescription.contains(".Type")
            || type.trimmedDescription.hasPrefix("any ")
          {
            context.diagnose(
              Diagnostic(
                node: type,
                message: SchemaDiagnostic(message: "Use a Schemable value type for this property"),
                fixIts: [
                  FixIt(
                    message: SchemaDiagnostic(message: "Replace with a wire value type"),
                    changes: [
                      .replace(
                        oldNode: Syntax(type),
                        newNode: Syntax(
                          IdentifierTypeSyntax(name: .identifier("<#SchemableType#>"))))
                    ])
                ]))
            continue
          }
          let temporary = "field\(ordinal)"
          ordinal += 1
          let typeText = type.trimmedDescription
          let metadata = annotations(variable.attributes, trivia: variable.leadingTrivia)
          statements.append(
            "\(metadata.isEmpty && binding.initializer == nil ? "let" : "var") \(temporary) = context.reference(\(typeText).self)"
          )
          for (keyword, expression) in metadata {
            statements.append("\(temporary)[\(literal(keyword))] = \(expression)")
          }
          if let initializer = binding.initializer {
            statements.append(
              "\(temporary)[\"default\"] = SchemaMetadata.defaultValue(\(initializer.value.trimmedDescription) as \(typeText), keyStrategy: context.keyStrategy)"
            )
          }
          let wireName =
            keys == nil ? literal(name) : "CodingKeys.\(identifier.identifier.text).stringValue"
          let key = "SchemaMetadata.key(\(wireName), strategy: context.keyStrategy)"
          statements.append("properties[\(key)] = \(temporary)")
          if !isOptional(type) { statements.append("required.append(.string(\(key)))") }
        }
      }
      statements.append(
        "var definition: JSONValue = [\"type\": \"object\", \"properties\": .object(properties), \"required\": .array(required)]"
      )
    } else if let enumeration = declaration.as(EnumDeclSyntax.self) {
      let raw = enumeration.inheritanceClause?.inheritedTypes.first(where: {
        ["String", "Int"].contains($0.type.trimmedDescription)
      })?.type.trimmedDescription
      if let raw {
        var values: [String] = []
        var nextInteger = 0
        for member in enumeration.memberBlock.members {
          guard let cases = member.decl.as(EnumCaseDeclSyntax.self) else { continue }
          for element in cases.elements {
            if raw == "String" {
              values.append(
                ".string(\(element.rawValue?.value.trimmedDescription ?? literal(element.name.text.replacingOccurrences(of: "`", with: ""))))"
              )
            } else {
              if let rawValue = element.rawValue?.value.trimmedDescription, let n = Int(rawValue) {
                nextInteger = n
              }
              values.append(".number(JSONNumber(\(nextInteger)))")
              nextInteger += 1
            }
          }
        }
        statements = [
          "var definition: JSONValue = [\"type\": \(literal(raw == "String" ? "string" : "integer")), \"enum\": .array([\(values.joined(separator: ", "))])]"
        ]
      } else {
        statements = ["var alternatives: [JSONValue] = []"]
        var ordinal = 0
        let keys = codingKeys(enumeration.memberBlock.members)
        for member in enumeration.memberBlock.members {
          guard let cases = member.decl.as(EnumCaseDeclSyntax.self) else { continue }
          for element in cases.elements {
            let caseName = element.name.text.replacingOccurrences(of: "`", with: "")
            if let keys, !keys.contains(caseName) { continue }
            let temporary = "case\(ordinal)"
            ordinal += 1
            let parameters = element.parameterClause?.parameters
            let payloadKeysName =
              caseName.prefix(1).uppercased() + caseName.dropFirst() + "CodingKeys"
            let payloadKeys = codingKeys(enumeration.memberBlock.members, named: payloadKeysName)
            let hasRequired =
              parameters?.enumerated().contains { i, parameter in
                let label = parameter.firstName?.text
                let name = label == nil || label == "_" ? "_\(i)" : label!
                return !isOptional(parameter.type)
                  && (payloadKeys == nil || payloadKeys!.contains(name))
              } == true
            statements += [
              "\(parameters?.isEmpty == false ? "var" : "let") \(temporary)Properties = JSONObject()",
              "\(hasRequired ? "var" : "let") \(temporary)Required: [JSONValue] = []",
            ]
            if let parameters {
              for (i, parameter) in parameters.enumerated() {
                let label = parameter.firstName?.text
                let name = label == nil || label == "_" ? "_\(i)" : label!
                if let payloadKeys, !payloadKeys.contains(name) { continue }
                let wireName =
                  payloadKeys == nil ? literal(name) : "\(payloadKeysName).\(name).stringValue"
                let key = "SchemaMetadata.key(\(wireName), strategy: context.keyStrategy)"
                statements.append(
                  "\(temporary)Properties[\(key)] = context.reference(\(parameter.type.trimmedDescription).self)"
                )
                if !isOptional(parameter.type) {
                  statements.append("\(temporary)Required.append(.string(\(key)))")
                }
              }
            }
            statements.append(
              "let \(temporary)Payload: JSONValue = [\"type\": \"object\", \"properties\": .object(\(temporary)Properties), \"required\": .array(\(temporary)Required), \"additionalProperties\": false]"
            )
            let wireName =
              keys == nil ? literal(caseName) : "CodingKeys.\(element.name.text).stringValue"
            let name = "SchemaMetadata.key(\(wireName), strategy: context.keyStrategy)"
            let caseAnnotations = annotations(cases.attributes, trivia: cases.leadingTrivia)
            statements.append(
              "\(caseAnnotations.isEmpty ? "let" : "var") \(temporary)Definition: JSONValue = [\"type\": \"object\", \"properties\": .object(JSONObject([(\(name), \(temporary)Payload)])), \"required\": .array([.string(\(name))]), \"additionalProperties\": false]"
            )
            for (keyword, expression) in caseAnnotations {
              statements.append("\(temporary)Definition[\(literal(keyword))] = \(expression)")
            }
            statements.append("alternatives.append(\(temporary)Definition)")
          }
        }
        statements.append("var definition: JSONValue = [\"oneOf\": .array(alternatives)]")
      }
    } else {
      context.diagnose(
        Diagnostic(
          node: declaration,
          message: SchemaDiagnostic(message: "@Schemable requires a struct or enum")))
      return []
    }
    for (keyword, expression) in annotations(
      declaration.attributes, trivia: declaration.leadingTrivia)
    { statements.append("definition[\(literal(keyword))] = \(expression)") }
    if annotations(declaration.attributes, trivia: declaration.leadingTrivia).isEmpty {
      statements = statements.map {
        $0.hasPrefix("var definition:")
          ? $0.replacingOccurrences(of: "var definition:", with: "let definition:") : $0
      }
    }
    statements.append("return definition")
    return [
      DeclSyntax(
        stringLiteral: access + "static var schemaKeyStrategy: JSONKeyStrategy { " + strategy + " }"
      ),
      DeclSyntax(
        stringLiteral: access
          + "static func schemaDefinition(in context: inout SchemaContext) -> JSONValue"
          + conditions + " {\n" + statements.joined(separator: "\n") + "\n}"),
    ]
  }

  public static func expansion(
    of node: AttributeSyntax, attachedTo declaration: some DeclGroupSyntax,
    providingExtensionsOf type: some TypeSyntaxProtocol, conformingTo protocols: [TypeSyntax],
    in context: some MacroExpansionContext
  ) throws -> [ExtensionDeclSyntax] {
    guard declaration.is(StructDeclSyntax.self) || declaration.is(EnumDeclSyntax.self) else {
      return []
    }
    let names = genericNames(declaration)
    let conditions =
      names.isEmpty ? "" : " where " + names.map { $0 + ": Schemable" }.joined(separator: ", ")
    return [try ExtensionDeclSyntax("extension \(type.trimmed): Schemable\(raw: conditions) {}")]
  }
  private static func literal(_ text: String) -> String {
    StringLiteralExprSyntax(content: text).description
  }
  private static func genericNames(_ declaration: some DeclGroupSyntax) -> [String] {
    let clause =
      declaration.as(StructDeclSyntax.self)?.genericParameterClause
      ?? declaration.as(EnumDeclSyntax.self)?.genericParameterClause
    return clause?.parameters.map { $0.name.text } ?? []
  }
  private static func isOptional(_ type: TypeSyntax) -> Bool {
    type.is(OptionalTypeSyntax.self) || type.trimmedDescription.hasPrefix("Optional<")
      || type.trimmedDescription.hasPrefix("Swift.Optional<")
  }
  private static func codingKeys(
    _ members: MemberBlockItemListSyntax, named name: String = "CodingKeys"
  ) -> Set<String>? {
    for member in members {
      guard let keys = member.decl.as(EnumDeclSyntax.self), keys.name.text == name else { continue }
      var result: Set<String> = []
      for entry in keys.memberBlock.members {
        if let cases = entry.decl.as(EnumCaseDeclSyntax.self) {
          for c in cases.elements {
            let name = c.name.text.replacingOccurrences(of: "`", with: "")
            result.insert(name)
          }
        }
      }
      return result
    }
    return nil
  }
  private static func annotations(_ attributes: AttributeListSyntax, trivia: Trivia) -> [(
    String, String
  )] {
    var result: [(String, String)] = []
    let docs = trivia.compactMap { piece -> String? in
      switch piece {
      case .docLineComment(let text):
        return String(text.dropFirst(3)).trimmingCharacters(in: .whitespaces)
      case .docBlockComment(let text):
        return text.dropFirst(3).dropLast(2).components(separatedBy: .newlines).map { line in
          let trimmed = line.trimmingCharacters(in: .whitespaces)
          return trimmed.hasPrefix("*")
            ? String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces) : trimmed
        }.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
      default: return nil
      }
    }.joined(separator: "\n")
    if !docs.isEmpty { result.append(("description", ".string(\(literal(docs)))")) }
    for item in attributes {
      guard let attr = item.as(AttributeSyntax.self) else { continue }
      if attr.attributeName.trimmedDescription == "available"
        && attr.trimmedDescription.contains("deprecated")
      {
        result.append(("deprecated", ".bool(true)"))
      }
      if attr.attributeName.trimmedDescription == "SchemaConstraint",
        let arguments = attr.arguments?.as(LabeledExprListSyntax.self)
      {
        for argument in arguments {
          guard let name = argument.label?.text else { continue }
          let expression = argument.expression.trimmedDescription
          if ["description", "format", "pattern"].contains(name) {
            result.append((name, "SchemaMetadata.text(\(expression))"))
          } else if ["minimum", "maximum"].contains(name) {
            result.append((name, "SchemaMetadata.number(\(expression))"))
          } else {
            result.append((name, "SchemaMetadata.integer(\(expression))"))
          }
        }
      }
    }
    return result
  }
}
