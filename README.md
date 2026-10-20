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

The on-screen name is **Little Orbit** on every platform. The watchOS app is standalone (it is not embedded in the iOS app) and runs in the watchOS simulator. Values live in `Config/`.

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

The four modules are platform-independent, so they compile on Linux. The apps themselves build in Xcode on macOS.

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
| `build` | macOS only | `xcodebuild -version`, then `xcodebuild` for each shared scheme in `LittleOrbit.xcodeproj` |
| `validate-project` | Linux and macOS | `xcprojformatter` on each `project.xcproj` |

`lint` prints a note and succeeds when the tree has no Swift sources. `build` runs `xcodebuild -version` first and stops unless it reports Xcode 27.2 or newer. On Linux that check fails and the message points at `swift build` for shared package code. `test` stops when the tree has no `Package.swift`. `validate-project` succeeds and prints a short note when no `project.xcproj` exists yet.

SwiftLint reads `.swiftlint.yml` and swift-format reads `.swift-format`. `mise run lint`, `mise run format`, and `mise run format-check` stay the same commands.

### CI

CI runs `mise install` and `mise run` against this `mise.toml`. Tool versions stay in this file.

### Project format fallback

Validation uses `xcprojformatter` on JSON `project.xcproj` files. If that format cannot be used, add XcodeGen with mise in the change that switches formats and record why.
