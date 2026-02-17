# World Map Overrides

Applies to the main 45-degree isometric world view.

## Visual Rules

Background:

- Use `bg1` as base plus a subtle vignette (center slightly brighter).
- Optional: a faint grid/noise overlay at 3-5% opacity to avoid banding.

Depth cues (minimal, not gamey):

- Use 1px `border0` outlines for selectable buildings/units.
- Use a soft drop shadow only for floating UI (drawer, command bar), not map tiles.

Selection:

- Selected building/unit: cyan outline + `glowSmall`.
- Hover: outline only (no glow) and a slight lift (translateY -1px in world-space, not screen-space).

## Interaction Rules

- Scroll wheel / trackpad: zoom in/out, anchored around pointer.
- Drag: pan.
- Click building: select + open drawer (half).
- Long-press building: enter Build mode (drag building).
- Click empty: exit Build mode or deselect (if already in Operate).

## Density Rules

- Always show at most 3 overlays per entity (name, status dot, tiny metric).
- Collapse overlays when zoomed out: show only status dot + count.

## Node (Local/Remote) Encoding

Do not rely on color alone. Use a secondary channel:

- Local: no stripe.
- Remote: thin left stripe on the building label plate + a small "antenna" glyph on units.
