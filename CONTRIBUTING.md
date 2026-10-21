# Contributing to little-orbit

This guide covers how work moves from an issue to `main`. It applies to everyone who changes the repository, people and agents alike. Setup and build steps are in the [README](README.md).

## Issues come first

- **Every change starts from an issue** on the [project board](https://github.com/users/neo-the-on3/projects/1). Every pull request references its issue with `Closes #N` (or `Refs #N` when it only partly addresses it).
- **Build to the issue's Given-When-Then acceptance criteria.** Each criterion reads "Given a context, When an action happens, Then an outcome follows". The pull request shows evidence for each one: a test, a CI check, a screenshot, or a Tester note.
- **Scope freeze.** Once a ticket is taken up, its scope is not edited. If the scope needs to change, or you find more work, open a new issue titled `Follow-up to #N` and link it from the original.
- **Design source.** UI work is built only from the team's Figma design files (private; ask the maintainer for access): the app designs and the design system. In the pull request, name the frames you built from by frame name and node ID. Don't paste Figma links, because this repository is public.

### Labels and ownership

| Label | Meaning |
| --- | --- |
| `role:product-manager`, `role:ui-designer`, `role:developer`, `role:tester`, `role:project-manager` | Who owns the issue right now. Ownership uses these labels, not GitHub assignees. |
| `type:requirements`, `type:design`, `type:feature`, `type:bug`, `type:chore` | Kind of work. |
| `platform:ios`, `platform:macos`, `platform:watchos` | Platforms the change affects. |
| `priority:high`, `priority:medium`, `priority:low` | Order of work. |
| `blocked` | Work cannot continue. ProjectManager coordinates. |
| `needs-kiran` | Waiting on the repository owner: an important or paid decision, or a pull request review. Only the owner removes it. Add it again only when the owner's input is needed again. |

- When you start a ticket, comment **`Taken up by <role>`**, for example `Taken up by Developer`.
- When you pass a ticket to another role, comment **`Handed off to <role>: <reason>`** and switch the `role:*` label.
- When you respond on an issue, do not change labels other than the ones these rules describe.

### Author line

Every bot posts through the repository owner's GitHub account, so the account alone doesn't show who wrote a post. Start every GitHub comment, pull request review, pull request description and new issue body with an author line, then a blank line, then the message:

```text
Author: Developer

Taken up by Developer
```

The roles are `Product Manager`, `UI Designer`, `Developer`, `Tester` and `Project Manager`. This applies whether you post with `gh`, the GitHub website or the Cursor app. Comments written before this rule are not edited. The repository owner's own comments, including approvals, don't need an author line.

## Trunk-based development

- `main` is the trunk. It is always releasable and is protected.
- **Every change goes through a pull request. Never commit or merge directly to `main`.**
- Use short-lived branches from the latest `origin/main`, named `<type>/<short-description>`, for example `feat/accounts-list`, `fix/watchos-standalone-install`, `docs/readme`, `chore/ci-test-reporting`.
- Keep pull requests small: one issue per pull request. Open it as a draft early and mark it ready when the checks pass.
- Keep the branch up to date by rebasing on `origin/main`, never by merging `main` into it.

## Commits

### Conventional Commits

Every new commit follows [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/): `<type>(<optional scope>): <summary>`, written in the imperative mood.

| Type | Use for | Example |
| --- | --- | --- |
| `feat` | A user-visible feature | `feat(theme): add design tokens from the Figma design system` |
| `fix` | A bug fix | `fix(watchos): mark the watch app as standalone so it installs` |
| `refactor` | A code change that neither fixes a bug nor adds a feature | `refactor(domain): move LedgerRepository into Domain` |
| `test` | Tests only | `test(theme): check every token against a Figma variables fixture` |
| `docs` | Documentation only | `docs: add CONTRIBUTING.md` |
| `build` | Build system, packages, or project configuration | `build: raise the package floor to iOS 27` |
| `chore` | Tooling and housekeeping; use the `ci` scope for workflows | `chore(ci): install the watch and iOS apps on simulators` |

Put the reason for the change in the commit body. Put `Closes #N` in the pull request description; a commit may repeat it.

### Logical commits

- Structure each pull request as a short series of logical commits. Each commit does one thing, builds, and passes its own tests.
- Fold fix-ups into the commit they fix (`git commit --fixup=<sha>`, then `git rebase -i --autosquash origin/main`). Don't leave "fix typo" or "address review" commits in the branch.
- Never squash a whole pull request into one commit.

### Force-pushing

- Rewriting history is fine on your own feature branch. Push it with `git push --force-with-lease`, never with a plain `--force`.
- Never force-push `main`.

## Review and merge

1. **Checks.** These five required checks must pass, and the branch must be up to date with `main` (strict):
   - `lint`
   - `format-check`
   - `Linux tests`
   - `validate-project`
   - `macOS build and test`
2. **Automated review.** Cursor Bugbot reviews pull requests. Resolve or answer every review thread; unresolved threads block the merge.
3. **Tester verification.** Request verification from Tester for anything that runs in an app (see [Testing](#testing)). Tester reports on the pull request.
4. **Owner approval.** Merge only after the repository owner approves the pull request in a comment or review.
5. **Rebase-merge only.** Use **Rebase and merge**. Squash merges and merge commits are not allowed, so the logical commits land on `main` as they are. If `main` has moved, rebase the branch, wait for the checks again, then merge.

## Local toolchain

All tools come from [mise](https://mise.jdx.dev/) and the pins in `mise.toml`. Install mise, then from the repository root:

```sh
mise trust
mise install
```

Before pushing, run the same checks CI runs:

```sh
mise run lint              # SwiftLint (.swiftlint.yml), strict
mise run format-check      # swift-format lint --strict (.swift-format)
mise run validate-project  # xcprojformatter on LittleOrbit.xcodeproj/project.xcproj
mise run test              # swift test for each package
```

`mise run format` rewrites Swift sources with swift-format. On Linux, `mise install` can rewrite `mise.lock` for your distribution; restore it with `git checkout mise.lock` and don't commit that change. The README's [Tooling](README.md#tooling) section explains each task and the Linux and macOS toolchains.

## Testing

- **Package tests** run with `mise run test` on Linux and macOS. Put platform-independent logic in the packages so it is covered on Linux too.
- **Simulators only.** Apple builds are verified on the iOS 27.2 and watchOS 27.2 simulators and on macOS, with Xcode 27.2. There are no device builds, and testing does not need an Apple ID, certificate, or provisioning profile. Choose simulators by UDID, not by name, because names can repeat.
- **No signing for tests.** Simulator builds don't sign, and Mac builds are ad-hoc signed. CI builds with `CODE_SIGNING_ALLOWED=NO`. `Config/Signing.local.xcconfig` is optional and gitignored. Create it from `Config/Signing.local.xcconfig.example` only if you want a local device build, and never commit it or any team ID, certificate, or profile.
- **Tester verification.** Tester checks pull requests on the simulators and macOS against the acceptance criteria. If a feature can only be checked on a real device, say so in the pull request.

## Architecture: MVVM with Clean layering

Shared code lives in the local Swift package `Packages/LittleOrbitKit`. The Xcode app targets stay thin.

| Layer | Module | Holds | May depend on |
| --- | --- | --- | --- |
| Core | `LittleOrbitCore` | Small shared utilities | nothing |
| Domain | `LittleOrbitDomain` | Entities and business rules in plain Swift, with no SwiftData or SwiftUI | Core |
| Data | `LittleOrbitPersistence` | SwiftData records, mapping to domain types, repository implementations | Domain, Core |
| Presentation | `LittleOrbitTheme` | Design tokens and SwiftUI styling | Core |
| Presentation | App targets in `Apps/` | SwiftUI views, one `@Observable`, `@MainActor` view model per screen | any module |

- Dependencies point inward. Domain never imports Persistence, SwiftData, or SwiftUI. Theme never imports Domain or Persistence.
- Views read and write data through view models. View models talk to repository protocols, not to SwiftData directly, so storage can change later. Avoid `@Query` in views.
- Add a thin use-case type only where there is real logic to hold.
- Repository protocols belong in Domain. `LedgerRepository` currently lives in Persistence and moves to Domain in a follow-up. A `Features` module for view models arrives with the first screens.

## Pull request template

New pull requests start from [`.github/pull_request_template.md`](.github/pull_request_template.md). Fill in every section and delete the ones that don't apply. Keep the `Author: <Role>` first line.
