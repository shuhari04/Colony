# Session Drawer Overrides

Applies to the bottom drawer that shows a single session's live output and input.

## Layout Rules

- Default state is half height.
- Full height is reserved for "reading mode" (logs, diffs, long output).
- Top bar is always visible: session name, target (local/host), status, primary actions.

## Terminal/Log Styling

- Output uses `JetBrains Mono` (`mono` token).
- Background uses `surface0`; the log viewport itself can be `bg1` to create a "well".
- Use subtle separators (1px `border0`) and timestamp color `muted0`.

Stream feedback:

- While streaming: show a thin cyan progress line at the top of the log viewport (no spinners).
- When rate-limited: show a warning badge with remaining time; apply `glowSmall` to the badge only.

## Composer (Send Message)

- Composer is pinned to the bottom of the drawer.
- Multi-line input expands up to 5 lines; after that it scrolls internally.
- `@` autocomplete opens above the composer and never covers the send button.

Keyboard rules (macOS):

- Enter sends.
- Shift+Enter inserts newline.
- Esc collapses suggestions first, then collapses drawer.

## Anti-Patterns

- No glitch/scanline effects.
- No animated backgrounds behind text.
- No toast-only errors for send failures (must show inline).
