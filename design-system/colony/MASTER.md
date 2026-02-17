# Colony Design System (Master)

Applies to the Flutter desktop app (macOS first). Page-specific overrides live in `design-system/colony/pages/*.md`.

## Product Principles

- Professional, dark, minimal.
- One vivid accent with restrained glow; no rainbow UI.
- Density over decoration, but never clutter.
- Everything keyboard-addressable (macOS) and pointer-friendly.

## Design Tokens

### Color

Core neutrals (OLED-friendly):

| Token | Hex | Notes |
|---|---:|---|
| `bg0` | `#05070D` | app background (outside map) |
| `bg1` | `#070B14` | world canvas base |
| `surface0` | `#0B1220` | panels / drawers |
| `surface1` | `#0F172A` | elevated panels |
| `border0` | `#1B2742` | hairline borders |
| `text0` | `#E6EDF7` | primary text |
| `text1` | `#A9B5CC` | secondary text |
| `muted0` | `#6B7A99` | metadata / timestamps |

Accent + semantic states:

| Token | Hex | Usage |
|---|---:|---|
| `accentCyan` | `#22D3EE` | focus, selection, links |
| `success` | `#A3E635` | running/healthy |
| `warning` | `#FBBF24` | throttled, needs attention |
| `danger` | `#FB7185` | failed/stopped/errors |
| `info` | `#60A5FA` | informational badges |

Glow rules (minimal):

- Only `accentCyan` and `danger` may glow.
- Glow is a state indicator, not decoration: selection, focus, active session output, rate limit warning.

Recommended glow values (convert to Flutter `BoxShadow`):

| Token | Value |
|---|---|
| `glowSmall` | blur 10, spread 0, alpha 0.35 |
| `glowMed` | blur 18, spread 0, alpha 0.28 |
| `glowLarge` | blur 28, spread 0, alpha 0.22 |

### Typography

Two families max:

- UI: system first (`SF Pro` on macOS), fallback `Inter`.
- Monospace: `JetBrains Mono` (terminal/logs, code, IDs, metrics).

Type scale (Flutter `TextTheme` oriented):

| Role | Size | Weight | Family |
|---|---:|---:|---|
| `title` | 18 | 600 | UI |
| `subtitle` | 14 | 600 | UI |
| `body` | 13 | 400 | UI |
| `meta` | 11 | 500 | UI |
| `mono` | 12 | 450 | Mono |

### Spacing, Radius, Elevation

Spacing (8pt grid):

- `s1=4`, `s2=8`, `s3=12`, `s4=16`, `s5=24`, `s6=32`, `s7=48`

Radius:

- `r1=8` (chips, buttons)
- `r2=12` (cards, drawers)
- `r3=16` (modal sheets)

Elevation (avoid big shadows on dark UI; use borders + blur instead):

- `e0`: none
- `e1`: subtle border + 6px shadow (alpha 0.25)
- `e2`: sheet/drawer + 12px shadow (alpha 0.30)

### Motion

- Default duration 140ms.
- Large transitions (drawer expand/collapse) 220ms.
- Curves: easeOut for enter, easeIn for exit.
- Respect reduced motion (disable glow pulsing and large parallax).

## Core Interaction Model

Two modes:

- Operate mode (default): click selects; actions happen.
- Build mode (temporary): long-press a building enters; drag buildings; click empty exits.

Selection + focus:

- Selected entity shows an outline + glow (cyan), never a filled highlight.
- Keyboard focus ring uses `accentCyan` at 2px with small glow.

Global input:

- A command bar is always reachable via keyboard (macOS suggestion: Cmd+K).
- Typing `@` opens session autocomplete; pressing Enter sends to the selected session (or the addressed one).

## Component Baselines

### Command Bar

- Single-line input with optional leading "target pill" when an `@session` is resolved.
- Inline suggestions list anchored to the bar, not a full modal.
- Error state is inline (red border + one-line error), never a toast only.

### Drawers (Inspector)

- One drawer model: hidden / half / full.
- Content is dense but scannable: tabs are allowed only if >2 panes (Logs / Actions / Metrics).
- The drawer owns the "send message" field for the selected session.

### Badges

- Status badge uses semantic colors; text always `text0`.
- Rate limit badge: show used percent and a countdown; turns warning glow near threshold.

### Iconography

- Use one icon set across the app (recommended: Phosphor or Lucide equivalent for Flutter).
- No emojis.

## Accessibility and QA Rules

- Target size: 32x32 minimum on desktop, 44x44 for touch (future iOS).
- Contrast: text meets 4.5:1 against `surface0`.
- Keyboard: everything in drawers and command bar is reachable without a mouse.
- Hover is additive, never required (important actions must be accessible via click/keyboard).

Before delivering any UI code, verify:

- [ ] No emojis used as icons (use SVG instead)
- [ ] All icons from consistent icon set (Heroicons/Lucide)
- [ ] `cursor-pointer` on all clickable elements
- [ ] Hover states with smooth transitions (150-300ms)
- [ ] Light mode: text contrast 4.5:1 minimum
- [ ] Focus states visible for keyboard navigation
- [ ] `prefers-reduced-motion` respected
- [ ] Responsive: 375px, 768px, 1024px, 1440px
- [ ] No content hidden behind fixed navbars
- [ ] No horizontal scroll on mobile
