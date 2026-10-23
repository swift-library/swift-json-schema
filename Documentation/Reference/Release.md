# Release

Validation runs through the [CI](../../.github/workflows/ci.yml) workflow.
Pushing a signed version tag starts the [Release](../../.github/workflows/release.yml)
workflow, which validates the tagged commit and publishes its changelog notes.

Version rules for swift-json-schema, covering tags, release timing, choosing the
next version and the changelog, are in
[VERSIONING](https://github.com/swift-library/.github/blob/master/VERSIONING.md).
This document records the repository's release facts and mechanics and does not
restate those rules.

README owns usage and conformance results. Module DocC catalogs are colocated
with their targets.

## Components and Version Sources

| Shipped component | Version meaning | Version source | Mirrors and derived fields | Update and read-only check |
| --- | --- | --- | --- | --- |
| Package products | Products' version | [VERSION](../../VERSION), selected by [.github/release.json](../../.github/release.json) | [CHANGELOG.md](../../CHANGELOG.md) records release notes; [scripts/generate-version](../../scripts/generate-version) supplies the CLI's generated constant. | Shared policy checks declarations; CLI tests check `--version`. |

## Compatibility Surface

Compatibility includes JSON value and number representations, schema compilation
and evaluation, typed builders and macros, Foundation conversions, Foundation
Models bridging, CLI options and outputs, and compiler/platform requirements.

## Dependencies and Verified Combinations

The package requires Swift 6.3, iOS 18 or macOS 15 and supports Linux.
The maintained Apple system window covers iOS 18/26/27 and macOS 15/26/27.
Foundation Models bridging requires iOS 26 or macOS 26 at runtime and a matching SDK.
Shared Apple CI compiles and tests with Xcode 26.6 (Swift 6.3) on macOS 26
through one compiler entry. Release builds, strict formatting and DocC builds
use that compiler. The latest SDK checks API availability for the declared
deployment floors; the command-line product follows the same floors.
The SwiftSyntax requirement is 602.0.0..<605.0.0; [Package.resolved](../../Package.resolved) records the dependency
versions selected for validation.

## Derived Metadata and Drift Checks

[.github/swift-package.json](../../.github/swift-package.json) selects compilers,
format paths, the pinned Linux image, DocC targets and repository commands.
[.github/release.json](../../.github/release.json) declares the repository,
version source, changelog, minimum Swift version and platform support window.

The required checks are `policy / policy` and `validate / result`. Policy checks
signatures, commit and pull-request titles, source rules and version declarations.
Validation aggregates formatting, tests, release builds, Linux tests, DocC,
Python CLI tests and compliance reports.

## Candidate, Acceptance and Publication

Run the [local validation commands](../../CONTRIBUTING.md#local-validation) and
require both CI checks on the accepted commit. The release workflow validates
the tagged commit again, verifies its signed annotated tag and version
declaration, then publishes the matching changelog entry as GitHub release notes.

## Compliance Reports

Compliance reports use the fixture revision and archive checksum in
`Tests/Fixtures.lock.json`. The optional draft-04 integer mismatch remains
visible in those reports.

`swift test --filter OfficialSuite` regenerates per-draft reports in
`.build/compliance/`.

## Entry Points and Artifact Retention

| Operation | Existing command or explicit manual procedure | Required access |
| --- | --- | --- |
| Version update and check | Update `VERSION` and `CHANGELOG.md` under VERSIONING; shared policy validates their declarations. | Repository write access |
| Candidate validation and build | Run the [local validation commands](../../CONTRIBUTING.md#local-validation); CI runs the declared matrix. | Swift, Xcode and Python 3 locally |
| Status and interrupted-run recovery | Inspect GitHub Actions results; retry a failed release with the same accepted tag. | Repository write access to rerun workflows |
| Acceptance and publication | Push the signed accepted version tag; [`Release`](../../.github/workflows/release.yml) validates it and publishes its notes. | Tag signing key and repository write access |
| Cleanup | Remove local `.build/` outputs when no longer needed. | Local filesystem access |

Builds, DocC archives and compliance reports live under ignored `.build/`.
