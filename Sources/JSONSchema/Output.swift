// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2026 Xudong Xu

import Foundation
import JSONValue

/// The amount and structure of detail included in serialized validation results.
public enum OutputFormat: String, Sendable, CaseIterable { case flag, basic, detailed, verbose }

/// One evaluation node with schema and instance locations, optional diagnostics, and child evaluations.
public struct ValidationUnit: Sendable {
  /// Whether this evaluation node succeeded.
  public let valid: Bool
  /// The keyword location relative to the validation output's schema path.
  public let keywordLocation: JSONPointer
  /// The canonical schema resource URI and keyword fragment.
  public let absoluteKeywordLocation: String
  /// The JSON Pointer locating the evaluated value within the instance.
  public let instanceLocation: JSONPointer
  /// A diagnostic message for a failed evaluation, when supplied.
  public let error: String?
  /// An annotation produced at this location, when supplied.
  public let annotation: JSONValue?
  /// Nested evaluation results in evaluation order.
  public let children: [ValidationUnit]

  func rendered(children selected: [ValidationUnit] = []) -> JSONValue {
    var pending = [(unit: self, children: selected, next: 0, values: [JSONValue]())]
    while let frame = pending.last {
      if frame.next < frame.children.count {
        pending[pending.count - 1].next += 1
        let child = frame.children[frame.next]
        pending.append((unit: child, children: child.children, next: 0, values: []))
        continue
      }
      var value: JSONValue = [
        "valid": .bool(frame.unit.valid),
        "keywordLocation": .string(frame.unit.keywordLocation.description),
        "absoluteKeywordLocation": .string(frame.unit.absoluteKeywordLocation),
        "instanceLocation": .string(frame.unit.instanceLocation.description),
      ]
      if let error = frame.unit.error { value["error"] = .string(error) }
      if let annotation = frame.unit.annotation { value["annotation"] = annotation }
      if !frame.values.isEmpty {
        value[frame.unit.valid ? "annotations" : "errors"] = .array(frame.values)
      }
      pending.removeLast()
      if pending.isEmpty { return value }
      pending[pending.count - 1].values.append(value)
    }
    preconditionFailure("An output traversal always has a root")
  }
  func leaves(validity: Bool) -> [ValidationUnit] {
    var result: [ValidationUnit] = []
    var pending = [self]
    while let unit = pending.popLast() {
      if unit.valid != validity { continue }
      if unit.error != nil || unit.annotation != nil { result.append(unit) }
      pending.append(contentsOf: unit.children.reversed())
    }
    return result
  }
  func condensed() -> ValidationUnit? {
    var pending = [(unit: self, next: 0, children: [ValidationUnit]())]
    while let frame = pending.last {
      if frame.next < frame.unit.children.count {
        pending[pending.count - 1].next += 1
        let child = frame.unit.children[frame.next]
        if child.valid == frame.unit.valid { pending.append((unit: child, next: 0, children: [])) }
        continue
      }
      let condensed: ValidationUnit?
      if frame.unit.error == nil && frame.unit.annotation == nil && frame.children.isEmpty {
        condensed = nil
      } else if frame.unit.error == nil && frame.unit.annotation == nil && frame.children.count == 1
      {
        condensed = frame.children[0]
      } else {
        condensed = ValidationUnit(
          valid: frame.unit.valid, keywordLocation: frame.unit.keywordLocation,
          absoluteKeywordLocation: frame.unit.absoluteKeywordLocation,
          instanceLocation: frame.unit.instanceLocation, error: frame.unit.error,
          annotation: frame.unit.annotation, children: frame.children)
      }
      pending.removeLast()
      if pending.isEmpty { return condensed }
      if let condensed { pending[pending.count - 1].children.append(condensed) }
    }
    return nil
  }
}

/// The evaluation tree and its standard JSON and human-readable projections.
public struct ValidationResult: Sendable {
  /// The complete root evaluation, including successful and failed branches.
  public let tree: ValidationUnit
  /// Whether the root evaluation accepted the instance.
  public var valid: Bool { tree.valid }
  /// Diagnostic units reached through failed branches, in evaluation order.
  public var errors: [ValidationUnit] { tree.leaves(validity: false) }
  /// Annotation-bearing units reached through successful branches.
  public var annotations: [ValidationUnit] {
    tree.leaves(validity: true).filter { $0.annotation != nil }
  }
  /// Serializes a flag, flat basic results, condensed detailed results, or the full verbose tree.
  /// The default is `basic`; `flag` contains only the root validity.
  public func output(_ format: OutputFormat = .basic) -> JSONValue {
    if format == .flag { return ["valid": .bool(valid)] }
    if format == .verbose { return tree.rendered(children: tree.children) }
    if format == .detailed {
      let children = tree.children.filter { $0.valid == valid }.compactMap { $0.condensed() }
      return tree.rendered(children: children)
    }
    let leaves = valid ? annotations : errors
    return tree.rendered(
      children: leaves.map {
        ValidationUnit(
          valid: $0.valid, keywordLocation: $0.keywordLocation,
          absoluteKeywordLocation: $0.absoluteKeywordLocation,
          instanceLocation: $0.instanceLocation, error: $0.error, annotation: $0.annotation,
          children: [])
      })
  }
  /// Returns `Valid` on success or one line per error with instance and keyword locations.
  public var humanReadable: String {
    if valid { return "Valid" }
    return errors.map {
      ($0.instanceLocation.description.isEmpty ? "/" : $0.instanceLocation.description) + ": "
        + ($0.error ?? "Invalid value") + " [" + $0.keywordLocation.description + "]"
    }.joined(separator: "\n")
  }
}

struct Evaluation {
  var properties: Set<Data> = []
  var items: Set<Int> = []
  let unit: ValidationUnit
  var valid: Bool { unit.valid }
}
