---
name: draw
description: Draw a picture with Python code (an SVG file) from the user's instructions — to-scale drawings with measurements, floor plans, furniture and woodwork sketches, diagrams, timelines, flowcharts, patterns, and generative/geometric art. Use when the user says "/draw", "draw me…", "make a diagram of…", "sketch this to scale", or asks for a picture where exact sizes, counts, or layout matter. Do NOT use for photo-like pictures or rough "what would this look like" mood images — that is an image model, if the project's CLAUDE.md describes one. Do NOT use for charts of data in an artifact (that's dataviz). Other skills (e.g. new-design for screen mockups) may use it too.
---

# Draw

Turn the user's instructions into a picture by writing a short Python script that outputs an
SVG (a picture stored as text, made of shapes). It is exact: sizes, counts and positions come
out as written, which an image model cannot do. Works in any folder or project.

No need to ask before drawing — it is free and runs on this machine. Just draw.

## Draw or an image model?

Only relevant where the project's `CLAUDE.md` describes an image model (for example FLUX in
the reader vault).

| Draw (this skill) | Image model (see CLAUDE.md, ask first) |
|---|---|
| Measurements, to-scale plans, furniture sketches | "Roughly what would this room look like" |
| Diagrams, timelines, flowcharts, layouts | Mood pictures to make a note nicer |
| Patterns, geometric and generative art | Anything that should look like a photo |

If the request is really an image-model job, say so in one line and suggest it instead.

Turning an existing picture into an SVG (tracing) is not part of this skill. Redrawing one
by hand is — follow "Matching a picture" below.

## Workflow

1. **Read the instructions.** If a key fact is missing (for example the room size for a floor
   plan), ask one short question. Otherwise pick sensible defaults and say what you picked.
2. **Write a throwaway script in the scratchpad directory** (never in the project) that uses
   the helper `svg.py` in this folder:
   ```python
   import os, sys; sys.path.insert(0, os.path.expanduser("~/.claude/skills/draw"))
   from svg import Canvas, PALETTES
   c = Canvas(800, 600, background="#faf7f2", seed=1)
   ...
   print(c.save("<absolute path>/resources/<name>.svg", preview=True))
   ```
   Run it with `python3`, saving to an absolute path. Plain Python only — nothing to install.
3. **Look at the result.** `preview=True` writes a PNG copy to `~/Pictures/Draw` and prints its
   path. Open it with the Read tool and check it: labels readable and not overlapping, nothing
   cut off at the edges, measurements match the instructions. Fix and re-run until it's right.
   - **Matching a picture?** See "Matching a picture" below.
   - **See-through drawing?** Pass `preview_background="#888"` to `save` so the preview isn't
     on white, where pale colours vanish. Check on the background it will really sit on too.
4. **Save it.** Leave the script in the scratchpad — macOS clears it from `/tmp` after a few days.
   - For a note or document: `resources/<name>.svg` next to it, embedded with
     `![description](resources/<name>.svg)`. Only add the embed when the user (or the skill
     that called this one) has said to update that file; otherwise say where it is.
   - With no note: the project's attachment folder if it has one (`attachments/` in the
     reader vault), otherwise ask where to put it.
   - Name the file in lowercase with dashes, e.g. `desk-side-view.svg`.
5. **Report** in a line or two: where the file is, the scale if there is one, and any default
   you chose. Show the preview PNG path so the user can open it.

Changes later ("make the table 20 cm wider") mean writing a new script and redrawing. Read
the old SVG first if it helps to match its layout and colours.

## Matching a picture

When redrawing an existing picture (a logo, an icon), work like this. Guessing positions and
colours by eye from the full picture gives lumpy shapes and the wrong shading.

1. **Make the canvas the original's size**, so its pixel positions can be used directly.
2. **Measure, don't estimate.** `zoom("original.png", x, y, w, h)` crops a part and enlarges
   it 2×; open it with Read and note where each shape starts, bends and ends. Convert back
   with original = (x + X / 2, y + Y / 2). Zoom into each busy area separately.
3. **Draw outlines with `smooth()` through the measured points**, not hand-placed Bezier
   controls. Repeat a point for a sharp corner. For symmetric shapes list the left half and
   add `mirror(half, cx)` — with **the shape's own centre** as `cx`, not the canvas centre.
   Outlines with pointed corners need `stroke_linejoin="miter"`; round joins blunt them.
4. **Take colours from the original.** `sample_colours("original.png", [(x, y), ...])` returns
   the colour at each point. For shading that changes down the picture, sample a few heights
   and make one gradient for the whole picture with `linear_gradient(..., span=..., offsets=...)`,
   so every shape gets the colour for where it sits — not a separate gradient per shape.
5. **Check with the overlay.** Call `c.reference("original.png")` before saving: the preview
   then also writes a copy with the original faintly on top (never in the saved SVG). A
   doubled edge means that shape is off — move its points and re-run until edges line up.

Say what you simplified (small details, textures) when you report.

## Rules

- **Metric units only** (cm, mm, m). For to-scale drawings, pick a simple scale (for example
  1 px = 0.5 cm), draw everything with it, and write the scale on the picture.
- **Label in plain language.** Spell out any short form.
- **Keep it readable.** Text at least 12 px, dark text on a light background, and leave a
  margin of about 40 px so nothing touches the edge.
- **Generative art uses the canvas seed** (`c.jitter`, `c.pick`, or `c.rng`), never the
  plain `random` module, so the same seed always gives the same picture. Tell the user the
  seed; "try seed 7" gets a new version.
- **Colours:** use a set from `PALETTES` unless the user asks for specific colours.

## What `svg.py` gives you

- Shapes: `rect`, `circle`, `ellipse`, `line`, `polyline`, `polygon`, `path`, `text`.
  Extra SVG attributes pass through as keyword arguments (`opacity=0.5`,
  `stroke_dasharray="4 4"`). A filled `path` gets no outline unless you give a `stroke`.
- **Curves:** `smooth(points, closed=True)` returns path data for a smooth curve through the
  points — use it for any rounded or organic shape instead of guessing Bezier control
  points. Repeat a point for a sharp corner; `tension=0.5` flattens the curve.
  `mirror(points, cx)` flips a half-outline for symmetric shapes (`half + mirror(half, cx)`).
- `mask("id", [raw shapes to cut out])` — e.g. a crescent is a circle minus a circle.
- `clip("id", [raw shapes])`, then `group_start(clip_path="url(#id)")` — keeps everything
  in the group inside those shapes, e.g. a pattern inside its frame.
- `group_start(transform="rotate(30 400 300)")` / `group_end()` to move, rotate, or scale
  a set of shapes together.
- `linear_gradient("id", [colours])` and `radial_gradient("id", [colours])`, then
  `fill="url(#id)"`. A radial colour can be `("#hex", opacity)` for light that fades out.
  `span=((x1, y1), (x2, y2))` spreads a linear gradient over the whole canvas instead of
  each shape; `offsets=[...]` (0–1) places its colours unevenly.
- **Effects and textures** — define once, then `filter="url(#id)"` on a shape or group:
  `glow("id", amount)`, `shadow("id", dx, dy, blur)`, `blur("id", amount)`, and
  `texture("id", kind)` with kind `paper`, `grain`, `stone`, `wood`, `brushed` or `clouds`
  (`strength` 0–1, `scale` to enlarge the pattern; follows the canvas seed).
- Working from a picture: `reference("original.png")` shows it over the previews only;
  `zoom(path, x, y, w, h)` crops and enlarges part of it; `sample_colours(path, points)`
  reads its colours. See "Matching a picture".
- `grid(spacing)` — light background grid.
- `dimension(x1, y1, x2, y2, "120 cm", offset=-30)` — measurement line with arrow heads and
  a label; `offset` moves it away from the object.
- `jitter(amount)`, `pick(list)`, `rng` — seeded randomness. `rng_for("name")` gives one
  part of the picture its own seeded sequence, so changing another part doesn't reshuffle it.
- `add(raw_svg)` — for anything the helpers don't cover.

If a drawing needs something the helper lacks and will likely be needed again, add it to
`svg.py` rather than repeating raw SVG.

## Patterns (`patterns.py`)

When a drawing has paving, tiles, wood, plants or geometric decoration, use these instead
of repeating one simple shape on a grid — that looks like clip art. Import with
`from patterns import ...` (same folder as `svg.py`). Each function only works out the
shapes and returns points; you draw them with the Canvas, so colours stay your choice.
Where it asks for `rng`, pass `c.rng_for("<part>")` (e.g. `"paving"`, `"patio"`), so each
pattern keeps its look when other parts change. The docstrings say what each returns and
how to draw it.

| Need | Function | Notes |
|---|---|---|
| Crazy paving, stone walls, cracked tiles | `voronoi(rng, x, y, w, h, n, gap=)` | Stones fit tightly with even joints (`gap`). `relax=0` uneven, `3` like cut stone. `keep=` an oval or polygon for a ragged-edged patch. Round corners with `smooth(cell, closed=True, tension=0.4)`. |
| Tile floors and walls | `truchet(rng, x, y, cols, rows, size)` | One tile turned at random; curves join across tiles. Gives lines, a two-colour fill, and the tile count. |
| Wood (tops, sides, slats) | `wood_grain(rng, x, y, w, h)` | Grain lines that bend round knots, plus the knots. One call per board so boards differ. Draw over the base colour, with the `wood` texture if you like. |
| Trees and bushes from above (plans) | `blob(...)` + `branches_from_above(...)` | Lumpy crown outline, plus branches spreading from the trunk. Layer two blobs for depth. |
| Plants from the side | `lsystem(rng, *PLANTS["tree"])` then `fit(...)` | Presets: `tree`, `fern`, `bush`. `wiggle=` makes each plant differ. |
| Feature floors, inlays | `penrose(x, y, w, h, edge)` | Thick and thin diamond tiles, never repeating. Each tile is marked whole or cut — count them for a cutting list. |
| Jaali screens, Islamic tiles and inlay | `star_pattern(x, y, w, h, size, tiling, angle)` | `octagon` (8-point stars), `hexagon` (6-point), `square`. A star sits in the middle of the area by default. Fill the panel dark (holes), draw the lines thick in the panel colour, add a solid frame. |

Keep patterns inside their area with `clip()`. For to-scale drawings, give sizes in the
drawing's scale (a 300 mm tile at 1 px = 5 mm is `size=60`) and say the real sizes in the
report.
