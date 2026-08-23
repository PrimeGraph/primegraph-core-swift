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

## Status

Scaffolding only. No shared declarations have been migrated yet;
`Sources/PrimeGraphCore/PrimeGraphCore.swift` holds a single placeholder so the build has something to
compile.

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
Package.swift                              manifest, swift-tools-version 5.9
Sources/PrimeGraphCore/PrimeGraphCore.swift  public surface
.githooks/                                 Conventional Commits hook, dependency-free POSIX shell
scripts/setup.sh                           one-time clone setup
scripts/release.sh                         the release procedure
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

## Build

```sh
swift build
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
