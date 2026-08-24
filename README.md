# primegraph-core-swift

`PrimeGraphCore` — the shared cross-package vocabulary for PrimeGraph generated Swift packages.

## Why this package exists

The PrimeGraph compiler generates one package per graph bucket. Each generated package used to carry
its own private copy of a runtime, so a type declared in that runtime existed once per package. When
one generated package handed a value to another — a model field, a thrown error — the two copies were
different nominal types and the code broke: it failed to compile in Go and Swift, and in Kotlin a
`catch` silently failed to match.

This package holds the vocabulary that crosses package boundaries, so a graph has exactly one nominal
type per concept no matter how many generated packages it spans.

Per-bundle machinery — Firebase, HTTP transport, server helpers — stays inside the generated packages
and does **not** belong here.

There are five of these, one per target language:
`primegraph-core-ts`, `primegraph-core-go`, `primegraph-core-swift`, `primegraph-core-py`,
`primegraph-core-kt`.

## What is in here

Everything that crosses a package boundary, and nothing else.

| Declaration | Why it is shared |
| ----------- | ---------------- |
| `AnyCodable` and its nested `JSONValue` | An untyped model field built in one package is read in another. Two copies are two nominal types and neither cast nor conversion between them can be written. |
| `Runtime.File`, `Runtime.FormPart`, `Runtime.formField` | `File` is the carrier a `binary` model field materializes as, so it travels with the model. |
| `Runtime.ValidationIssue`, `Runtime.validationError` | The issue type is the payload inside the `DslError` a model package's validator raises. |
| `AnyDslError`, `DslError`, `DslErrorView`, `DslJsonObjectConvertible` | A protocol declared in two modules is two protocols, so `e as? AnyDslError` fails across a boundary. |
| `dslErrorMessages`, `defaultErrorMessage`, `dslJsonWire`, `dslArrivedJson`, `dslArrivedCode`, `dslDecodedPayload` | The catch-side reading of a raised error, and what `DslError.payloadJson` is built with. |
| `Runtime.jsonEncoder`, `Runtime.jsonDecoder`, `Runtime.parseInstant` | Pulled in by the above: the error carrier renders and reads its payload through the one configured encoder and decoder, and the decoder reads an instant through the one tolerant reader. |
| `Runtime.HttpAuth`, `Runtime.HttpRequest`, `Runtime.HttpResponse`, `Runtime.HttpValidationFailure` | A type nested in the shared `Runtime` namespace must be declared once. Two generated packages that both declare `Runtime.HttpRequest` make the initializer ambiguous the moment one build sees both. |
| `Runtime.SharedBox`, `Runtime.Semaphore` | Same rule. Emitted code writes `Runtime.SharedBox<Int64>(...)` at a call site, so two packages that both use a bounded or shared-variable `parallel` collide exactly the same way. |

The rule those last two rows share is worth stating on its own: **every type nested in `Runtime`
belongs here**, because the namespace is shared and a nested type declared twice is ambiguous at any
call site that spells it. Adding a nested type to `Runtime` from a generated package is never correct.

## What is deliberately not in here

The HTTP transport itself (`Runtime.fetch`, `parseResponse`, `parseAnyBody`) — only its value types
are shared. Also everything Firebase, the JSON-shape primitives the generated validators call, and the
pure expression helpers. Those are functions rather than nested types: each is looked up through the
importing file's own module, so a copy per package costs nothing and keeps this package free of SDK
dependencies.

## `Runtime` is a namespace, not the module

Emitted code writes `Runtime.File`, `Runtime.jsonEncoder()` and `Runtime.validationError(...)`
literally, so `Runtime` stays a namespace enum declared here rather than becoming the module itself —
a rename would have to be made in every emitter at once and would buy nothing.

A generated package adds its own private members to that same namespace with an extension, so both
halves answer to the one spelling:

```swift
import PrimeGraphCore

extension Runtime {
    public static func fetch(_ req: HttpRequest) async throws -> HttpResponse { /* ... */ }
}
```

What a generated package must not do is declare `public enum Runtime` of its own: the local
declaration would shadow this one, and `Runtime.File` would then name nothing.

## Dependencies

Zero. Foundation only, and that is a constraint, not a coincidence — every generated Swift package
depends on this one, so anything pulled in here is pulled in everywhere.

## Platforms

Every Apple platform is declared, at the lowest floor the code allows:

| Platform    | Floor |
| ----------- | ----- |
| macOS       | 12    |
| iOS         | 15    |
| tvOS        | 15    |
| watchOS     | 8     |
| macCatalyst | 15    |
| visionOS    | 1     |

This package has no Firebase or transport dependency, which is why watchOS can be declared here even
though the generated packages that pull in `firebase-ios-sdk` cannot. Consumers raise their own floors
as their SDK dependencies require; this one stays as low as possible so it never becomes the reason a
platform is unavailable.

## Layout

```
Package.swift                            manifest, swift-tools-version 5.9
Sources/PrimeGraphCore/AnyCodable.swift  the type-erased JSON carrier
Sources/PrimeGraphCore/DslError.swift    the error carrier and the catch-side readers
Sources/PrimeGraphCore/Runtime.swift     the Runtime namespace and its shared members
Tests/PrimeGraphCoreTests/               XCTest suites, one per source file
.githooks/                               Conventional Commits hook, dependency-free POSIX shell
scripts/setup.sh                         one-time clone setup
scripts/release.sh                       the release procedure
```

## Setup

A fresh clone has to be pointed at the repository's own hooks once:

```sh
git config core.hooksPath .githooks
```

`sh scripts/setup.sh` does that for you.

The hook rejects any commit message that is not a Conventional Commit: `type(scope)!: subject`, one of
`build chore ci docs feat fix perf refactor revert style test`, header at most 100 characters, no
trailing period.

## Build and test

```sh
swift build
swift test
```

A non-macOS platform is checked without an Xcode project:

```sh
xcodebuild -scheme PrimeGraphCore -destination 'generic/platform=iOS' build
```

`xcodebuild` needs the platform's runtime installed, which a given machine may not have for watchOS,
tvOS or visionOS. Compiling the module against the SDK alone needs only the SDK, so it covers all six:

```sh
out=$(mktemp -d)
for t in arm64-apple-macos12.0:macosx arm64-apple-ios15.0:iphoneos \
         arm64-apple-ios15.0-macabi:macosx arm64-apple-tvos15.0:appletvos \
         arm64_32-apple-watchos8.0:watchos arm64-apple-xros1.0:xros; do
  xcrun swiftc -emit-module -module-name PrimeGraphCore \
    -sdk "$(xcrun --sdk "${t#*:}" --show-sdk-path)" -target "${t%:*}" \
    -emit-module-path "$out/${t%:*}.swiftmodule" Sources/PrimeGraphCore/*.swift \
    || echo "FAILED ${t%:*}"
done
```

## Releasing

```sh
sh scripts/release.sh 1.4.0
```

The argument is a bare semver — no leading `v`; the tag gets one. The script refuses to run on a dirty
tree, off the default branch, or when the tag already exists, and it does all of those checks before it
changes anything. `Package.swift` records no version and there is no registry to publish to, so the
release is tag-only: it builds, tags and pushes the tag.

Consumers then pin it exactly:

```swift
.package(url: "https://github.com/PrimeGraph/primegraph-core-swift.git", exact: "1.4.0")
```
