# Contributing

By submitting a contribution, you confirm your right to license it under
[the package license](LICENSE.txt).

External contributions are welcome. Use a Conventional Commit PR title and
follow `.swift-format`. Maintainers follow the shared
[signing instructions](https://github.com/swift-library/.github/blob/master/MAINTENANCE.md#signing). Review the
[release facts and mechanics](Documentation/Reference/Release.md)
and the [swift-library versioning standard](https://github.com/swift-library/.github/blob/master/VERSIONING.md)
when changing compatibility, requirements or release inputs.

## Local validation

Run these checks before opening a pull request:

```sh
swift build
swift test
swift build -c release
xcrun swift-format lint --strict --configuration .swift-format --recursive \
  Package.swift Sources Tests Plugins Benchmarks/Package.swift Benchmarks/Sources
JSON_SCHEMA_CLI="$(swift build -c release --show-bin-path)/json-schema" \
  python3 -B -m unittest discover -s Tests/CLITests
swift test --filter OfficialSuite
```

The official suite writes per-draft compliance reports to `.build/compliance/`.
The build plugin invokes `scripts/generate-version` to derive the CLI version
from `VERSION`.

CI reads [.github/swift-package.json](.github/swift-package.json) for compiler,
formatting, Linux, DocC and repository command checks. The required checks are
`policy / policy` and `validate / result`.
