Author: <Role>

<!-- Replace <Role> with Product Manager, UI Designer, Developer, Tester, Project Manager or Tech Architect. Keep this as the first line, followed by a blank line. -->
<!-- Title: a Conventional Commits summary, e.g. "feat(accounts): add the accounts list". -->

Closes #

## Summary

<!-- What changes and why. Mention anything left for a "Follow-up to #N" issue. -->

## Platforms affected

- [ ] iOS
- [ ] macOS
- [ ] watchOS
- [ ] Shared package only (`Packages/LittleOrbitKit`)
- [ ] Tooling, CI, or docs only

## Acceptance criteria

<!-- Copy each Given-When-Then criterion from the issue and show the evidence for it:
     a test name, a CI check, a screenshot, or a Tester note. -->

- **Given … When … Then …**: evidence

## Design

<!-- Name the Figma frame(s) this implements by frame name and node ID, for example "#22/iOS/Account list/Populated/Light (5:2)". No links: the Figma files are private and this repository is public. Write "None" for non-UI changes. -->

- Figma frames:

## Screenshots

<!-- Required for UI changes when you already have a capture: Light and Dark, and a large Dynamic Type size where it matters. Simulator or CI screenshots are fine; don't export from Figma just for this. -->

## Testing

- **Linux checks:** `mise run lint`, `mise run format-check`, `mise run validate-project`, `mise run test`
- **CI:** the five required checks (`lint`, `format-check`, `Linux tests`, `validate-project`, `macOS build and test`)
- **Tester (simulators and macOS, Xcode 27.2):** what to check on the iOS 27.2 and watchOS 27.2 simulators and on macOS

## Checklist

- [ ] The description starts with `Author: <Role>`
- [ ] UI changes include a screenshot (simulator or CI capture)
- [ ] No `@`-mentions in the description or commit messages (refer to teammates by role)
- [ ] The pull request references its issue (`Closes #N`), and the issue's scope was not edited
- [ ] Commits follow Conventional Commits and are logical, with fix-ups folded in
- [ ] `mise run lint` and `mise run format-check` pass
- [ ] Tests added or updated, and `mise run test` passes
- [ ] Every acceptance criterion is met, with evidence above
- [ ] Tester verification requested (or not needed: tooling or docs only)
- [ ] No secrets, team IDs, certificates, or profiles committed
