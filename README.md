# little-orbit

## Tooling

mise is the entry point for project tools. A machine with mise installs the same pinned versions on Linux and macOS. CI installs from this `mise.toml` and runs tasks with `mise run`.

Verified with mise 2026.10.14.

### Setup

Install [mise](https://mise.jdx.dev/installing-mise.html), then from the repository root:

```sh
mise trust
mise install
```

`mise install` installs every tool pinned in `mise.toml`. `mise.lock` records the download URLs for those pins, including SwiftLint checksums, for Linux and macOS.

| Tool | Pin | Where it runs |
| --- | --- | --- |
| Swift | 6.4.1 (swift.org) | Linux and macOS |
| swift-format | 6.4.1, the `swift-format` binary in that Swift toolchain | Linux and macOS |
| SwiftLint | 0.65.1 (`aqua:realm/SwiftLint`) | Linux and macOS |
| xcprojformatter | apple/xcode-project-format `0.1.0` (`c132630aabf40f6d6c3f7bb004595d2e5a28ea42`), built from source | Linux and macOS |

The first install builds `xcprojformatter` from that commit, so it needs network access to GitHub. Every pinned tool installs on Linux and macOS.

`xcodebuild` is macOS-only. It ships with Xcode 27.2 or newer and is selected with `xcode-select`. On macOS, `swift`, `swift test`, and `swift-format` come from the mise-pinned Swift 6.4.1 toolchain, and `xcodebuild` uses the selected Xcode.

### Tasks

`mise tasks` lists the tasks below. Run one with `mise run <task>`.

| Task | Platforms | What it runs |
| --- | --- | --- |
| `lint` | Linux and macOS | `swiftlint` when the tree contains Swift sources |
| `format` | Linux and macOS | `swift-format format --in-place --recursive .` |
| `format-check` | Linux and macOS | `swift-format lint --strict --recursive .` |
| `test` | Linux and macOS | `swift test --package-path` for each `Package.swift` |
| `build` | macOS only | `xcodebuild` for each shared scheme in `LittleOrbit.xcodeproj` |
| `validate-project` | Linux and macOS | `xcprojformatter` on each `project.xcproj` |

`lint` prints a note and succeeds when the tree has no Swift sources. `build` stops on Linux with a message that points at `swift build` for shared package code. `test` stops when the tree has no `Package.swift`. `validate-project` succeeds and prints a short note when no `project.xcproj` exists yet.

SwiftLint and swift-format read their config files from the tree when those files are added (`mise run lint`, `mise run format`, and `mise run format-check` stay the same commands).

### CI

CI runs `mise install` and `mise run` against this `mise.toml`. Tool versions stay in this file.

### Project format fallback

Validation uses `xcprojformatter` on JSON `project.xcproj` files. If that format cannot be used, add XcodeGen with mise in the change that switches formats and record why.
