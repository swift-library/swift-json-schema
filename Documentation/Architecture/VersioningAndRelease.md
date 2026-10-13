# Versioning and Release

swift-json-schema follows the [shared release standard](https://github.com/swift-library/.github/blob/master/VERSIONING.md).
`VERSION` declares the products' version, `CHANGELOG.md` records release notes,
and `.github/release.json` selects validation, documentation targets and the
pinned Linux compiler image.

## Compatibility surface

Compatibility includes JSON value and number representations, schema compilation
and evaluation, typed builders and macros, Foundation conversions, Foundation
Models bridging, CLI options and outputs, and compiler/platform requirements.

## Requirements and validation

The package requires Swift 6.2, iOS 18 or macOS 15 and supports Linux.
The maintained Apple system window covers iOS 18/26/27 and macOS 15/26/27.
Foundation Models bridging requires iOS 26 or macOS 26 at runtime and a matching SDK.
CI tests Swift 6.2 on macOS 15 and Linux and Swift 6.3 on macOS 26, with
strict formatting checked separately.

`Scripts/check` checks declarations, formatting, consumer tooling, Swift tests,
release builds, CLI behavior, consumer examples and DocC on macOS. Compliance
reports use the fixture revision and archive checksum in `Tests/Fixtures.lock.json`.
The optional draft-04 integer mismatch remains visible in those reports.
Evidence belongs in `.build/release-validation`; raw compliance reports are
produced in `.build/compliance`.

README owns usage and conformance results. Module DocC catalogs are colocated
with their targets.
