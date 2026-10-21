# little-orbit

SwiftUI app shell for iOS, macOS, and watchOS. The Xcode project stays thin: shared code lives in the local Swift package `Packages/LittleOrbitKit`.

Open `LittleOrbit.xcodeproj` in Xcode 27.2 or later. The project file is `project.xcproj` (JSON). There is no `project.pbxproj`.

## Layout

- `LittleOrbit.xcodeproj` — iOS, macOS, and watchOS app targets, plus shared schemes
- `Apps/` — SwiftUI app entry points and the placeholder root view
- `Packages/LittleOrbitKit` — `LittleOrbitCore`, `LittleOrbitDomain`, `LittleOrbitPersistence`, and `LittleOrbitTheme`, each with a test target
- `Config/` — bundle IDs, deployment targets, and signing

## Platforms

| Target | Scheme | Deployment | Bundle ID | Product |
| --- | --- | --- | --- | --- |
| LittleOrbit iOS | LittleOrbit iOS | iOS 27.0 | `app.littleorbit.ios` | `LittleOrbit.app` |
| LittleOrbit macOS | LittleOrbit macOS | macOS 27.0 | `app.littleorbit.macos` | `LittleOrbitMac.app` |
| LittleOrbit watchOS | LittleOrbit watchOS | watchOS 27.0 | `app.littleorbit.watchos` | `LittleOrbitWatch.app` |

The on-screen name is **Little Orbit** on every platform. The watchOS app is standalone (it is not embedded in the iOS app) and runs in the watchOS simulator. Its generated Info.plist sets `WKWatchOnly` (it has no iOS companion), not `WKRunsIndependentlyOfCompanionApp`. Values live in `Config/`.

`Packages/LittleOrbitKit` declares the same iOS 27, macOS 27, and watchOS 27 floors (`// swift-tools-version: 6.4`).

## Signing

Signing is automatic (`CODE_SIGN_STYLE = Automatic`). `Config/Signing.xcconfig` leaves `LITTLEORBIT_DEVELOPMENT_TEAM` empty and sets `DEVELOPMENT_TEAM` from that variable for the iOS, macOS, and watchOS targets. No Team ID, certificate, or profile is committed.

Simulator builds skip signing. Mac builds stay ad-hoc if you copy the example as-is. After `LITTLEORBIT_DEVELOPMENT_TEAM` is a real team, uncomment `CODE_SIGN_IDENTITY[sdk=macosx*] = Apple Development` in the local file so the Mac build uses that team. A device build uses your own team. Xcode creates the development provisioning profile on your Mac.

**Option A.** Open the target's Signing & Capabilities tab, set the team to your free personal team or the paid team, and do not commit the project or xcconfig change.

**Option B.** Copy the example and edit the copy only:

```sh
cp Config/Signing.local.xcconfig.example Config/Signing.local.xcconfig
```

Set `LITTLEORBIT_DEVELOPMENT_TEAM` to your 10-character Team ID. The Apple Development line in the example is commented out, so a copy with an empty team still ad-hoc signs the Mac app. Uncomment that line only after the team is set. Then, from the repo root:

```sh
xcodebuild -scheme 'LittleOrbit iOS' -destination 'generic/platform=iOS' -allowProvisioningUpdates build
xcodebuild -scheme 'LittleOrbit watchOS' -destination 'generic/platform=watchOS' -allowProvisioningUpdates build
xcodebuild -scheme 'LittleOrbit macOS' -destination 'generic/platform=macOS' -allowProvisioningUpdates build
```

`Config/Signing.local.xcconfig` is gitignored. If `app.littleorbit.*` is already registered, set `LITTLEORBIT_BUNDLE_ID_SUFFIX` to a unique suffix that includes the leading dot, such as `.yourname`. A free personal team's profiles expire after 7 days.

## Package on Linux

From `Packages/LittleOrbitKit`, with Swift 6.4 or later:

```sh
swift build
swift test
```

The package builds on Linux. Domain rules and the in-memory repository are platform-independent, so `swift test` covers them here. The SwiftData store is compiled only for iOS, macOS, and watchOS (`#if canImport(SwiftData)`). How a later schema version migrates existing data is documented in [docs/persistence-migration.md](docs/persistence-migration.md). The apps themselves build in Xcode on macOS. On a Mac, run package tests with `mise run test` from the repository root so they use Xcode's Swift. On Linux, that task also writes JUnit XML under `test-results/`. See [Tooling](#tooling).

## Tooling

mise is the entry point for project tools. CI installs from this `mise.toml` and runs tasks with `mise run`.

Linux and macOS use different Swift toolchains. Linux installs the pinned swift.org Swift 6.4.1. macOS uses the Swift and swift-format shipped with Xcode 27.2 or newer (`xcrun swift`, `xcrun swift-format`), selected with `xcode-select`. The swift.org macOS toolchain cannot build `Packages/LittleOrbitKit` for Apple platforms (`Could not choose a single platform for target 'LittleOrbitCore'`).

Verified with mise 2026.10.14.

### Setup

Install [mise](https://mise.jdx.dev/installing-mise.html), then from the repository root:

```sh
mise trust
mise install
```

`mise install` installs the tools in `mise.toml` that apply to the current operating system. `mise.lock` records the download URLs for those pins, including SwiftLint checksums, for Linux and macOS. Swift's lock entries are the ones `mise lock` writes: Linux uses `swift_platform = "ubuntu24.04"`, and the file also records the swift.org macOS package URLs. `os = ["linux"]` filters which host installs Swift, so on macOS `mise install` skips that tool.

| Tool | Pin | Where it runs |
| --- | --- | --- |
| Swift | 6.4.1 (swift.org) | Linux |
| swift-format | 6.4.1, the `swift-format` binary in that Swift toolchain | Linux |
| Swift | Xcode 27.2 or newer, `xcrun swift` | macOS |
| swift-format | the `swift-format` binary in that Xcode, `xcrun swift-format` | macOS |
| SwiftLint | 0.65.1 (`aqua:realm/SwiftLint`) | Linux and macOS |
| xcprojformatter | apple/xcode-project-format `0.1.0` (`c132630aabf40f6d6c3f7bb004595d2e5a28ea42`), built from source | Linux and macOS |

The first install builds `xcprojformatter` from that commit, so it needs network access to GitHub. On Linux that build uses the pinned Swift toolchain. On macOS the Swift tool is skipped, and the build uses Xcode's `swift`.

`xcodebuild` is macOS-only. It ships with Xcode 27.2 or newer and is selected with `xcode-select`.

### Tasks

`mise tasks` lists the tasks below. Run one with `mise run <task>`.

| Task | Platforms | What it runs |
| --- | --- | --- |
| `lint` | Linux and macOS | `swiftlint` when the tree contains Swift sources |
| `format` | Linux and macOS | Linux: `swift-format format --in-place --recursive .`. macOS: `xcrun swift-format format --in-place --recursive .` |
| `format-check` | Linux and macOS | Linux: `swift-format lint --strict --recursive .`. macOS: `xcrun swift-format lint --strict --recursive .` |
| `test` | Linux and macOS | Linux: `swift test --package-path --parallel --xunit-output test-results/<package>.xml` for each `Package.swift`, using Swift 6.4.1. macOS: `xcrun swift test --package-path` for each `Package.swift` |
| `build` | macOS only | `xcodebuild -version`, then `xcodebuild` for each shared scheme in `LittleOrbit.xcodeproj` |
| `validate-project` | Linux and macOS | `xcprojformatter` on each `project.xcproj` |

`lint` prints a note and succeeds when the tree has no Swift sources. `build` runs `xcodebuild -version` first and stops unless it reports Xcode 27.2 or newer. On Linux that check fails and the message points at `swift build` for shared package code. `test` stops when the tree has no `Package.swift`. On macOS, `test`, `format`, and `format-check` stop if `xcrun` cannot find the tool. `validate-project` succeeds and prints a short note when no `project.xcproj` exists yet.

On Linux, `test` passes `--parallel` because Swift 6.4.1 writes XCTest cases into `--xunit-output` only for that runner. A serial run leaves an empty `*-swift-testing.xml` file ([swift-package-manager#9961](https://github.com/swiftlang/swift-package-manager/issues/9961)). The task fails if `test-results/<package>.xml` has no `<testcase>`. macOS stays serial: `swift test` there does not produce an xcresult, and the CI macOS job records one with `xcodebuild test` instead. `test-results/` is gitignored.

SwiftLint reads `.swiftlint.yml` and swift-format reads `.swift-format`. The task names stay `mise run lint`, `mise run format`, and `mise run format-check`.

### CI

`.github/workflows/ci.yml` runs on pull requests and on pushes to `main`. Linux jobs install the tools in this `mise.toml` with mise. The macOS job selects Xcode 27.2 first, so `mise install` and `mise run test` use that Xcode (`xcrun swift`). Tool versions stay in this file.

The workflow uses the standard `ubuntu-latest` and `xcode-27` runners. It does not set branch protection. On a pull request the checks are `CI / <job name>`. The status-check name to require later is the job name.

| Job name | Runner | What it runs |
| --- | --- | --- |
| `lint` | `ubuntu-latest` | `mise run lint` |
| `format-check` | `ubuntu-latest` | `mise run format-check` |
| `Linux tests` | `ubuntu-latest` | `mise run test` for each Swift package |
| `validate-project` | `ubuntu-latest` | `mise run validate-project` |
| `macOS build and test` | `xcode-27` | `xcodebuild build` for the three schemes, `mise run test`, `xcodebuild test` on each Swift package, then install and launch the watchOS and iOS apps on simulators |

The shared app schemes have no test action, so the macOS job does not run `xcodebuild test` on them. It builds `LittleOrbit iOS`, `LittleOrbit macOS`, and `LittleOrbit watchOS`, runs the package tests with Xcode's Swift, then runs `xcodebuild test` on each package's aggregate scheme (`LittleOrbitKit-Package`, because the package has several products) with `-resultBundlePath test-results/<package>.xcresult`. It then installs and launches the watchOS and iOS simulator builds, so an app that builds but can't install fails the job. Simulators are picked by UDID from `xcrun simctl list devices available -j` (27.2 runtime preferred), never by name, because a Mac can have two simulators with the same name.

`Linux tests` succeeds without running `swift test` when the tree has no `Package.swift`. `macOS build and test` succeeds without building when `LittleOrbit.xcodeproj` or a `Package.swift` is missing. A failing lint, format check, package test, project check, or Apple build fails the corresponding job. Apple builds and the package `xcodebuild test` set `CODE_SIGNING_ALLOWED=NO`. When packages are present, both test jobs append a summary to the check's step summary and upload `test-results/` for 7 days. The summary step fails if those reports contain no test cases. A failing test fails the test step, and the summary and upload still run.

### Project format fallback

Validation uses `xcprojformatter` on JSON `project.xcproj` files. If that format cannot be used, add XcodeGen with mise in the change that switches formats and record why.
