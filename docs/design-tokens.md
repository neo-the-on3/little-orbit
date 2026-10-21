# Design tokens

`LittleOrbitTheme` (in `Packages/LittleOrbitKit`) holds the design tokens from the team's Figma design system file, little-orbit-design-system (`LittleOrbitTheme.designSystemFileName`). The file is private; ask the maintainer for access. It isn't linked here because this repository is public. Figma is the source of truth. Do not add or change a token value without changing it in Figma first.

The module depends only on `LittleOrbitCore`. It is presentation-level and never imports Domain or Persistence.

## What is in the module

| Swift | Figma | Notes |
| --- | --- | --- |
| `ThemeColor` | Collection "Semantic", modes Light and Dark (39 variables) | Each `ColorToken` has a `light` and a `dark` value. Use only semantic colours in screens. |
| `CategoryColor` | Primitives `category/*` (13 hues) | One value in both modes. Always used with a white glyph. |
| `Typography.IOS`, `.MacOS`, `.WatchOS`, `.Amount` | Text styles on "Foundations / Typography" | Sizes, weights, line heights and tracking are the SF values at the default Dynamic Type size. Figma shows them in Inter because SF is not available there. |
| `Spacing`, `Layout` | Collection "Spacing" (`space/*`, `margin/*`, `target/*`) | Points. `space/0_5` is `Spacing.spaceHalf`. |
| `Radius` | Collection "Radius" (`radius/*`) | Points. `xs`, `sm`, `md`, `lg`, `xl` are `extraSmall`, `small`, `medium`, `large`, `extraLarge` (SwiftLint needs 3+ character names). Use continuous corners. `radius/full` is 999; prefer `Capsule()`. |
| `Elevation` | Effect styles `Elevation/0 Flat` to `Elevation/3 Popover` | Drop shadows, light mode only. |

Brand primitives (`brand/*`, `neutral/*`, `green/*`, `red/*`, `amber/*`, `purple/*`) are not exposed. Figma hides them from publishing; semantic tokens alias them.

The value types and constants are plain Swift, so they build and are tested on Linux. SwiftUI adapters are compiled only where SwiftUI exists (`#if canImport(SwiftUI)`).

## Using tokens in SwiftUI

```swift
Text(amount)
    .font(.theme(Typography.Amount.iOSBody))
    .foregroundStyle(Color(ThemeColor.moneyPositive))
    .padding(Spacing.space4)
    .background(Color(ThemeColor.bgElevated), in: RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
    .themeElevation(Elevation.card)
```

- `Color(_ token: ColorToken)` follows the current appearance: Light value in light mode, Dark value in dark mode. watchOS is always dark and uses the Dark value.
- `Font.theme(_:)` uses the system font with the token's Apple text style, weight and design (`.rounded` plus monospaced digits for amounts). Because it is a text style, it scales with Dynamic Type up to the accessibility sizes. The stored point sizes are not applied directly. Pick styles from your platform's group; `Typography.currentPlatform` lists them.
- `themeElevation(_:)` draws the token's shadows in light mode only. In dark mode the design system replaces shadows with `bg/elevated`, so put the surface on `ThemeColor.bgElevated`. System sheets, popovers and menus keep their own system shadows in dark mode; never add theme shadows on top of them. Figma's blur radius is halved for SwiftUI's shadow radius.
- `ThemeSwatchView` shows every token. Its previews cover Light, Dark and the Accessibility 3 Dynamic Type size.

## Traceability and tests

`Tests/LittleOrbitThemeTests/Fixtures/figma-variables.json` holds the unedited `get_variable_defs` responses from the Figma MCP server for these nodes:

| Fixture key | Node | Frame |
| --- | --- | --- |
| `semanticLight` | `6:9` | Foundations / Color › Semantic / Light |
| `semanticDark` | `6:222` | Foundations / Color › Semantic / Dark |
| `primitives` | `6:435` | Foundations / Color › Primitives |
| `typography` | `7:5` | Foundations / Typography › Platforms |
| `spacing` | `7:146` | Foundations / Spacing & Layout › Scale |
| `radiusElevation` | `7:223` | Foundations / Radius & Elevation |

The tests (which run on Linux and macOS) compare every token with that fixture: names, Light and Dark values, text style metrics, spacing, radii and shadow layers. They also check the design system's own rules: text colours reach WCAG 4.5:1 on every background in both modes, and category hues reach 4.5:1 with white.

## Refreshing tokens from Figma

1. In the design system file, change the variable or style in Figma.
2. With the Figma MCP server, open the design system file and call `get_variable_defs` on each node in the table above. If a frame moved, find its new id with `get_metadata` on the page.
3. Paste each response, unedited, into the matching key of `figma-variables.json`. Update `_source.retrieved`.
4. Run `mise run test`. Each failure names a token whose Swift value no longer matches Figma.
5. Update the Swift constants (`ThemeColor.swift`, `Typography.swift`, `Spacing.swift`, `Radius.swift`, `Elevation.swift`) until the tests pass. A new Figma variable fails the name checks until it is added.
6. Check `ThemeSwatchView` previews in Light, Dark and a large Dynamic Type size, and ask the UI Designer to confirm the values.
