# little-orbit

Little Orbit is a personal finance app for macOS, iOS, and watchOS, built with SwiftUI and inspired by [Debit & Credit](https://debitandcredit.app). It tracks accounts, transactions, and categories, with data stored on the device.

The project is early: the app targets, the shared domain model, the local SwiftData store, and the CI pipeline are in place, and the first screens are being built from the Figma designs. Work is tracked on the [project board](https://github.com/users/neo-the-on3/projects/1).

SwiftUI app shell for iOS, macOS, and watchOS. The Xcode project stays thin: shared code lives in the local Swift package `Packages/LittleOrbitKit`.

Open `LittleOrbit.xcodeproj` in Xcode 27.2 or later. The project file is `project.xcproj` (JSON). There is no `project.pbxproj`.

## Links

- Designs: UI work is built from the team's Figma design files (private; ask the maintainer for access).
- Project board: [little-orbit](https://github.com/users/neo-the-on3/projects/1)
- How to contribute: [CONTRIBUTING.md](CONTRIBUTING.md) (added in #80, the PR for #7)

## Requirements

| To | You need |
| --- | --- |
| Build and run the apps | A Mac with Xcode 27.2 or later. The JSON `project.xcproj` format needs Xcode 27.2. Install the iOS 27.2 and watchOS 27.2 simulator runtimes in Xcode > Settings > Components. |
| Build and test the shared package, lint, and format | [mise](https://mise.jdx.dev/installing-mise.html) on macOS or Linux. mise installs SwiftLint, xcprojformatter, and (on Linux) Swift 6.4.1 from the pins in `mise.toml`. |
| Sign anything | Nothing. Testing is simulator-only, so no Apple ID, team, certificate, or profile is needed. See [Signing](#signing) for optional device builds. |

On Linux, install the system packages that swift.org's Swift toolchain needs before `mise install`. CI installs them in [`.github/actions/setup-mise/action.yml`](.github/actions/setup-mise/action.yml); install the same packages with your package manager, adjusting names for your distribution as that action does.

## Quick start

From a fresh clone:

```sh
# 1. Install mise (https://mise.jdx.dev/installing-mise.html), then:
mise trust
mise install

# 2. Run the checks CI runs
mise run lint
mise run format-check
mise run validate-project
mise run test             # builds and tests Packages/LittleOrbitKit
```

That builds and tests the shared package on macOS or Linux. On a Mac, select Xcode 27.2 first (`sudo xcode-select -s /Applications/Xcode.app`), because `mise run test` uses Xcode's Swift there. To build the apps, see [Build and run the apps](#build-and-run-the-apps). Each task is described under [Tasks](#tasks).

## Layout

- `LittleOrbit.xcodeproj` — iOS, macOS, and watchOS app targets, plus shared schemes
- `Apps/` — SwiftUI app entry points and the composition root, which opens the store once and wires the use cases into the features
- `Packages/LittleOrbitKit` — `LittleOrbitCore`, `LittleOrbitDomain`, `LittleOrbitPersistence`, `LittleOrbitFeatures`, and `LittleOrbitTheme`, each with a test target
- `Config/` — bundle IDs, deployment targets, and signing
- `docs/` — design notes, such as [persistence-migration.md](docs/persistence-migration.md). The design token guide, `docs/design-tokens.md`, arrives once #79 merges.
- `.github/` — the CI workflow and its setup action
- `mise.toml`, `mise.lock` — tool pins and tasks
- `.swiftlint.yml`, `.swift-format` — lint and format rules

The packages follow MVVM with Clean layering. Dependencies point inward: Domain (plain Swift entities, rules, the repository protocol, and the use cases) depends only on Core; Persistence (SwiftData) implements the repository for Domain; Features (view models and SwiftUI views) depends on Domain and Theme, never on Persistence; Theme (design tokens) depends only on Core. View models talk to use-case protocols that the App target injects. See [CONTRIBUTING.md](CONTRIBUTING.md#architecture-mvvm-with-clean-layering).

## Platforms

| Target | Scheme | Deployment | Bundle ID | Product |
| --- | --- | --- | --- | --- |
| LittleOrbit iOS | LittleOrbit iOS | iOS 27.0 | `app.littleorbit.ios` | `LittleOrbit.app` |
| LittleOrbit macOS | LittleOrbit macOS | macOS 27.0 | `app.littleorbit.macos` | `LittleOrbitMac.app` |
| LittleOrbit watchOS | LittleOrbit watchOS | watchOS 27.0 | `app.littleorbit.ios.watchkitapp` | `LittleOrbitWatch.app` |

The on-screen name is **Little Orbit** on every platform. The watchOS app is embedded in the iOS app (#17): running the iOS scheme on an iPhone simulator paired with an Apple Watch simulator installs both. Its generated Info.plist names `app.littleorbit.ios` as its companion and sets `WKRunsIndependentlyOfCompanionApp`, not `WKWatchOnly`, so it still launches and works when the iPhone app isn't running. The watch has no ledger of its own and no App Group: it reads the iPhone's data over WatchConnectivity (#48, D345). Values live in `Config/`.

`Packages/LittleOrbitKit` declares the same iOS 27, macOS 27, and watchOS 27 floors (`// swift-tools-version: 6.4`).

## Build and run the apps

On a Mac with Xcode 27.2:

1. Open `LittleOrbit.xcodeproj`.
2. Choose a scheme: `LittleOrbit iOS`, `LittleOrbit macOS`, or `LittleOrbit watchOS`.
3. Choose a destination: an iPhone or iPad simulator on iOS 27.2, an Apple Watch simulator on watchOS 27.2, or My Mac.
4. Run (⌘R). Simulator builds don't sign and Mac builds are ad-hoc signed, so no team is needed.

From the command line, find a simulator's UDID and build for it. Use the UDID rather than the name, because a Mac can have two simulators with the same name.

```sh
xcrun simctl list devices available
xcodebuild -project LittleOrbit.xcodeproj -scheme 'LittleOrbit iOS' \
  -destination 'platform=iOS Simulator,id=<udid>' \
  -derivedDataPath derived-data build CODE_SIGNING_ALLOWED=NO
xcrun simctl boot <udid>
xcrun simctl install <udid> derived-data/Build/Products/Debug-iphonesimulator/LittleOrbit.app
xcrun simctl launch <udid> app.littleorbit.ios
```

For the watch app, use `-scheme 'LittleOrbit watchOS'`, `platform=watchOS Simulator,id=<udid>`, `Debug-watchsimulator/LittleOrbitWatch.app`, and `app.littleorbit.ios.watchkitapp`. For the Mac app, use `-scheme 'LittleOrbit macOS' -destination 'platform=macOS'`. `mise run build` builds every shared scheme with its default destination.

## Signing

Device builds are optional; project testing uses simulators and macOS only.

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

The package builds on Linux. Domain rules, the use cases, the view models and the in-memory repository are platform-independent, so `swift test` covers them here. The SwiftData store is compiled only for iOS, macOS, and watchOS (`#if canImport(SwiftData)`). How a later schema version migrates existing data is documented in [docs/persistence-migration.md](docs/persistence-migration.md). Design tokens from Figma live in `LittleOrbitTheme`; see [docs/design-tokens.md](docs/design-tokens.md). The apps themselves build in Xcode on macOS. On a Mac, run package tests with `mise run test` from the repository root so they use Xcode's Swift. On Linux, that task also writes JUnit XML under `test-results/`. See [Tooling](#tooling).

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

`.github/workflows/ci.yml` runs on pushes to `main`, on pull requests once they're ready for review (draft pull requests skip every job), and by hand: Actions › CI › Run workflow on a branch, or `gh workflow run ci.yml --ref <branch>`. The mise tool cache is saved only from `main`; other runs restore it. Linux jobs install the tools in this `mise.toml` with mise. The macOS job selects Xcode 27.2 first, so `mise install` and `mise run test` use that Xcode (`xcrun swift`). Tool versions stay in this file.

The workflow uses the standard `ubuntu-latest` and `xcode-27` runners. On a pull request the checks are `CI / <job name>`. All five jobs below are required status checks on `main`, and a branch must be up to date with `main` before it merges.

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

## Contributing

Read [CONTRIBUTING.md](CONTRIBUTING.md) before opening a pull request. It covers the trunk-based flow, Conventional Commits, Given-When-Then acceptance criteria, the `Follow-up to #N` rule, labels, review, and testing. New pull requests start from the [pull request template](.github/pull_request_template.md). In short:

- Every change starts from an issue and goes through a pull request that says `Closes #N`. Nothing is committed or merged directly to `main`.
- Branches are short-lived and rebased on `main`. Pull requests are rebase-merged once the five checks pass and Tech Architect approves. Pull requests with cost, architecture, performance or maintainability implications also need the owner's approval.
- Commits follow [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/), such as `feat(theme): ...`, `fix: ...`, `chore(ci): ...` or `docs: ...`, and each pull request is a short series of logical commits.
- Cursor Bugbot reviews pull requests, and Tester verifies app changes on the iOS and watchOS simulators and on macOS.
