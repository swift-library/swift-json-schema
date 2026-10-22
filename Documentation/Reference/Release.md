# Release

Release status: partly manual; validation runs through [Scripts/check](../../Scripts/check).

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
| Package products | Products' version | [VERSION](../../VERSION), selected by [.github/release.json](../../.github/release.json) | [CHANGELOG.md](../../CHANGELOG.md) records release notes. | `Scripts/check` checks declarations. |

## Compatibility Surface

Compatibility includes JSON value and number representations, schema compilation
and evaluation, typed builders and macros, Foundation conversions, Foundation
Models bridging, CLI options and outputs, and compiler/platform requirements.

## Dependencies and Verified Combinations

The package requires Swift 6.2, iOS 18 or macOS 15 and supports Linux.
The maintained Apple system window covers iOS 18/26/27 and macOS 15/26/27.
Foundation Models bridging requires iOS 26 or macOS 26 at runtime and a matching SDK.
CI tests Swift 6.2 on macOS 15 and Linux and Swift 6.3 on macOS 26, with
strict formatting checked separately. The committed dependency lock selects the
upper tested SwiftSyntax release. A separate Swift 6.2 lane runs
`Scripts/check-dependency-minimum swift-syntax`, resolving the manifest's lower
bound in an archived source tree and running its tests and release build. Both
lanes record the actual dependency revision; the package supports the manifest's
602.0.0..<605.0.0 range.

## Derived Metadata and Drift Checks

[.github/release.json](../../.github/release.json) selects validation,
documentation targets and the pinned Linux compiler image.

`Scripts/check` checks declarations, formatting, consumer tooling, Swift tests,
release builds, CLI behavior, consumer examples and DocC on macOS.

## Candidate, Acceptance and Publication

Run `Scripts/check` and retain native, platform and consumer evidence for the
accepted source under `.build/release-validation`.

## Evidence Reuse and Invalidation

Compliance reports use the fixture revision and archive checksum in
`Tests/Fixtures.lock.json`. The optional draft-04 integer mismatch remains
visible in those reports.

`Scripts/check` records the commit and tree, OS, Swift toolchain, dependency lock
digest and pins, validation script and formatting configuration digests, and
completed checks in `.build/release-validation/provenance.json`. On macOS it also
records Xcode and SDK versions.

## Entry Points and Artifact Retention

| Operation | Existing command or explicit manual procedure | Required access |
| --- | --- | --- |
| Version update and check | Not established. | Not established. |
| Candidate validation and build | `Scripts/check`; `Scripts/check-dependency-minimum swift-syntax` for the minimum dependency lane. | Not established. |
| Status and interrupted-run recovery | Not established. | Not established. |
| Acceptance and publication | Run [`Release`](../../.github/workflows/release.yml) with the accepted tag; it validates the tag and publishes the GitHub release. Retain native, platform and consumer evidence for the accepted source under `.build/release-validation`. | Repository write access to run workflows |
| Cleanup | Not established. | Not established. |

Evidence belongs in `.build/release-validation`; raw compliance reports are
produced in `.build/compliance`.
