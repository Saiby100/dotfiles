#!/usr/bin/env python3
"""Pattern makers for the draw skill: crazy paving, tile patterns, wood grain, plants,
Penrose tiles and Islamic star patterns.

Each function only works out the shapes (lists of points) and returns them. You draw them
with the Canvas as usual, so you choose the colours, line widths and textures. Pass c.rng
as rng, so the canvas seed decides the randomness and the same seed gives the same picture.

    import os, sys; sys.path.insert(0, os.path.expanduser("~/.claude/skills/draw"))
    from svg import Canvas, PALETTES
    from patterns import voronoi

    c = Canvas(800, 600, seed=1)
    for stone in voronoi(c.rng, 100, 100, 600, 400, n=40, gap=4):
        c.polygon(stone, fill=c.pick(PALETTES["mono"][2:]))

Only Python's built-in libraries are used, so there is nothing to install.
"""

import cmath
import math

GOLDEN = (1 + 5 ** 0.5) / 2


# --- small geometry helpers -------------------------------------------------
def centroid(poly):
    """The middle point of a polygon (its centre of area)."""
    area = cx = cy = 0
    n = len(poly)
    for i in range(n):
        (x0, y0), (x1, y1) = poly[i], poly[(i + 1) % n]
        cross = x0 * y1 - x1 * y0
        area += cross
        cx += (x0 + x1) * cross
        cy += (y0 + y1) * cross
    if abs(area) < 1e-9:
        return (sum(p[0] for p in poly) / n, sum(p[1] for p in poly) / n)
    return (cx / (3 * area), cy / (3 * area))


def _clip(poly, a, b, c):
    """The part of a convex polygon where a*x + b*y <= c."""
    out = []
    n = len(poly)
    for i in range(n):
        p, q = poly[i], poly[(i + 1) % n]
        fp = a * p[0] + b * p[1] - c
        fq = a * q[0] + b * q[1] - c
        if fp <= 0:
            out.append(p)
        if (fp < 0 < fq) or (fq < 0 < fp):
            t = fp / (fp - fq)
            out.append((p[0] + t * (q[0] - p[0]), p[1] + t * (q[1] - p[1])))
    return out


# --- crazy paving, cracked tiles, stone walls --------------------------------
def inside_polygon(px, py, poly):
    """True if the point is inside the polygon (any shape, not only convex ones)."""
    hit = False
    n = len(poly)
    for i in range(n):
        (x0, y0), (x1, y1) = poly[i], poly[(i + 1) % n]
        if (y0 > py) != (y1 > py) and px < x0 + (py - y0) * (x1 - x0) / (y1 - y0):
            hit = not hit
    return hit


def voronoi(rng, x, y, w, h, n, gap=0, relax=1, points=None, keep=None):
    """Split a rectangle into n cells around scattered points (a Voronoi diagram). The cells
    fit together with no holes, like crazy paving, a dry-stone wall seen from the front, or
    cracked tiles. Returns a list of polygons (lists of points).

    gap: width of the joint between cells, in pixels (also half of it along the outside).
    relax: rounds of evening out the cell sizes: 0 = very uneven with some slivers,
           1 = natural stone, 3 = cells of nearly the same size, like cut stone.
    points: your own cell centres instead of random ones.
    keep: an area that isn't a rectangle - only cells whose middle is inside it are kept, so
          the patch gets a ragged stone edge. Give a polygon (list of points, e.g. a blob())
          or a function (x, y) -> True/False, e.g. an oval:
              keep=lambda px, py: ((px - cx) / rx) ** 2 + ((py - cy) / ry) ** 2 <= 1
          Make the rectangle a little bigger than the area, so no kept stone is cut straight
          by the rectangle's edge.

    For softer stone corners draw each cell as c.path(smooth(cell, closed=True, tension=0.4)).
    """
    sites = list(points) if points else [(x + rng.random() * w, y + rng.random() * h)
                                         for _ in range(n)]
    box = [(x, y), (x + w, y), (x + w, y + h), (x, y + h)]

    def cells(sites, g):
        out = []
        for i, (px, py) in enumerate(sites):
            poly = box
            for j, (qx, qy) in enumerate(sites):
                if i == j or not poly:
                    continue
                a, b = qx - px, qy - py
                d = math.hypot(a, b)
                if d == 0:
                    continue
                # Keep the side nearer to p, moved back by half the joint.
                poly = _clip(poly, a, b, (qx * qx + qy * qy - px * px - py * py) / 2 - g / 2 * d)
            out.append(poly)
        return out

    for _ in range(relax):
        sites = [centroid(p) for p in cells(sites, 0) if len(p) >= 3]
    result = []
    for poly in cells(sites, gap):
        if gap:
            poly = _clip(poly, -1, 0, -(x + gap / 2))
            poly = _clip(poly, 1, 0, x + w - gap / 2)
            poly = _clip(poly, 0, -1, -(y + gap / 2))
            poly = _clip(poly, 0, 1, y + h - gap / 2)
        if len(poly) < 3:
            continue
        if keep is not None:
            mx, my = centroid(poly)
            if not (keep(mx, my) if callable(keep) else inside_polygon(mx, my, keep)):
                continue
        result.append(poly)
    return result


# --- Truchet tiles -------------------------------------------------------------
def truchet(rng, x, y, cols, rows, size):
    """A Truchet tile pattern: every square tile holds two quarter-circles joining the
    middles of its sides, turned one of two ways at random. The curves run on from tile to
    tile in winding paths, so a simple tile gives a pattern across the whole floor.

    Returns a dict:
      "lines": path data for all the curves - c.path(d, stroke=..., stroke_width=...)
      "fill":  a list of (path data, 0 or 1) to colour the two sides of the curves in two
               colours, drawn in order: for d, i in ...: c.path(d, fill=colours[i])
      "count": how many tiles (each is the same tile, so this is the tile count to buy)
    """
    h = size / 2
    lines, fill = [], []
    for r in range(rows):
        for col in range(cols):
            x0, y0 = x + col * size, y + r * size
            turned = rng.random() < 0.5
            # The corners inside the quarter-circles share one colour; which one depends on
            # the corner's place on the grid, so the colours always match across tiles.
            disc = (r + col + turned) % 2
            fill.append((f"M{x0:.2f},{y0:.2f}h{size:.2f}v{size:.2f}h{-size:.2f}Z", 1 - disc))
            if not turned:  # curves round the top-left and bottom-right corners
                arcs = [(x0, y0, f"M{x0 + h:.2f},{y0:.2f} A{h:.2f},{h:.2f} 0 0 1 {x0:.2f},{y0 + h:.2f}"),
                        (x0 + size, y0 + size,
                         f"M{x0 + size:.2f},{y0 + h:.2f} A{h:.2f},{h:.2f} 0 0 0 {x0 + h:.2f},{y0 + size:.2f}")]
            else:  # curves round the top-right and bottom-left corners
                arcs = [(x0 + size, y0,
                         f"M{x0 + h:.2f},{y0:.2f} A{h:.2f},{h:.2f} 0 0 0 {x0 + size:.2f},{y0 + h:.2f}"),
                        (x0, y0 + size,
                         f"M{x0:.2f},{y0 + h:.2f} A{h:.2f},{h:.2f} 0 0 1 {x0 + h:.2f},{y0 + size:.2f}")]
            for cx, cy, arc in arcs:
                lines.append(arc)
                fill.append((f"{arc} L{cx:.2f},{cy:.2f}Z", disc))
    return {"lines": " ".join(lines), "fill": fill, "count": rows * cols}


# --- wood grain ----------------------------------------------------------------
def wood_grain(rng, x, y, w, h, spacing=4, knots=None, waviness=1.0, min_knot=5):
    """Grain lines for a board seen from the top or side, running along its length (left to
    right), bending round knots. Draw them over the board's base colour (and the "wood"
    texture if you like); give each board its own call so no two look the same.
    For a board that stands up, draw inside group_start(transform="rotate(90 cx cy)").

    spacing: pixels between grain lines. knots: how many (default 0-2 at random).
    waviness: 0 = straight lines, 1 = normal, 2 = very wavy.
    min_knot: smallest knot height in pixels (up to a quarter of the board), so knots stay
    visible on narrow boards and slats.

    Returns (lines, knots): lines is a list of polylines (lists of points) for
    c.polyline(line, stroke=..., stroke_width=0.6); knots is a list of (cx, cy, rx, ry)
    ellipses - draw each as a dark ellipse with one or two rings round it.
    """
    n = max(3, int(h / spacing))
    count = rng.randint(0, 2) if knots is None else knots
    smallest = min(min_knot, h / 4) / 2  # knot height is twice its radius
    ks = [(x + w * rng.uniform(0.15, 0.85), y + h * rng.uniform(0.25, 0.75),
           max(h * rng.uniform(0.05, 0.1), smallest)) for _ in range(count)]
    # A few slow waves shared by every line, so the lines run together like real grain.
    waves = [(rng.uniform(0.5, 2.5) * 2 * math.pi / w, rng.uniform(0, 2 * math.pi),
              rng.uniform(0.3, 1.0) * h * 0.03 * waviness) for _ in range(3)]
    steps = max(20, int(w / 5))
    lines = []
    for i in range(n):
        base = y + (i + 0.5) * h / n + rng.uniform(-0.3, 0.3) * h / n
        f, ph, a = (rng.uniform(1, 4) * 2 * math.pi / w, rng.uniform(0, 2 * math.pi),
                    h * 0.01 * waviness)
        pts = []
        for s in range(steps + 1):
            px = x + w * s / steps
            py = base + a * math.sin(f * (px - x) + ph)
            py += sum(amp * math.sin(fr * (px - x) + p) for fr, p, amp in waves)
            for kx, ky, kr in ks:
                # Push the line away from the knot, most strongly right next to it.
                dy = py - ky
                push = kr * 1.6 * math.exp(-((px - kx) / (kr * 4)) ** 2) * math.exp(-(dy / (kr * 3)) ** 2)
                py += push if dy >= 0 else -push
            pts.append((px, min(max(py, y), y + h)))
        lines.append(pts)
    return lines, [(kx, ky, kr * 1.4, kr) for kx, ky, kr in ks]


# --- plants and trees ----------------------------------------------------------
def blob(rng, cx, cy, r, lobes=11, wobble=0.12):
    """Points round a lumpy, scalloped outline: a bush or tree crown seen from above, or a
    cloud. Each bump is a rounded arc of its own size, with a dip between bumps.
    Draw with c.path(smooth(points, closed=True), fill=...). Layer two or three (smaller and
    lighter on top) for depth.
    lobes: how many bumps (7-9 for a shrub, 10-14 for a tree). wobble: how deep the dips
    are, as a share of r (0.05 = nearly round, 0.2 = very bumpy)."""
    start = rng.uniform(0, 2 * math.pi)
    sizes = [rng.uniform(0.6, 1.4) for _ in range(lobes)]  # some bumps stick out more
    per = 8  # points along each bump
    pts = []
    for i in range(lobes * per):
        a = start + i * 2 * math.pi / (lobes * per)
        bump = math.sin(math.pi * (i % per) / per)  # 0 at the dips, 1 at the top of a bump
        rr = r * (1 - wobble * sizes[i // per] * (1 - bump))
        pts.append((cx + rr * math.cos(a), cy + rr * math.sin(a)))
    return pts


def branches_from_above(rng, cx, cy, r, main=6, depth=3):
    """Branch lines of a tree seen from above (for plans), spreading out from the trunk and
    staying inside radius r. Returns (x1, y1, x2, y2, level) segments; level 0 is the main
    branches - draw them thicker. Put them over a see-through crown made with blob()."""
    segs = []

    def grow(x0, y0, ang, length, level):
        x1, y1 = x0 + length * math.cos(ang), y0 + length * math.sin(ang)
        segs.append((x0, y0, x1, y1, level))
        if level + 1 < depth:
            for turn in (-1, 1):
                grow(x1, y1, ang + turn * rng.uniform(0.3, 0.6), length * rng.uniform(0.5, 0.65), level + 1)

    start = rng.uniform(0, 2 * math.pi)
    for i in range(main):
        grow(cx, cy, start + i * 2 * math.pi / main + rng.uniform(-0.2, 0.2), r * rng.uniform(0.4, 0.5), 0)
    return segs


# Ready-made plants seen from the side: (start, rules, rounds, turn in degrees).
PLANTS = {
    "tree": ("X", {"X": "F[+X]F[-X]+X", "F": "FF"}, 5, 22),
    "fern": ("X", {"X": "F+[[X]-X]-F[-FX]+X", "F": "FF"}, 5, 25),
    "bush": ("F", {"F": "FF+[+F-F-F]-[-F+F+F]"}, 4, 22.5),
}


def lsystem(rng, start, rules, rounds, turn, wiggle=0):
    """A plant seen from the side, grown from rewrite rules (an L-system). Each round
    replaces every letter by its rule; then F draws a step forward, + and - turn by `turn`
    degrees, and [ ] start and end a side branch. Use a ready-made one from PLANTS:
        segs = lsystem(c.rng, *PLANTS["tree"], wiggle=6)
    wiggle: random extra degrees at each turn, so two plants from the same rules differ.

    Returns (x1, y1, x2, y2, level) segments growing upwards from (0, 0), one unit per step;
    level is how many branches deep it is - draw deeper levels thinner. Place it with
    fit(segs, x, y, w, h).
    """
    s = start
    for _ in range(rounds):
        s = "".join(rules.get(ch, ch) for ch in s)
    x = y = 0.0
    a, level, stack, segs = -90.0, 0, [], []
    for ch in s:
        if ch == "F":
            nx, ny = x + math.cos(math.radians(a)), y + math.sin(math.radians(a))
            segs.append((x, y, nx, ny, level))
            x, y = nx, ny
        elif ch == "+":
            a += turn + rng.uniform(-wiggle, wiggle)
        elif ch == "-":
            a -= turn + rng.uniform(-wiggle, wiggle)
        elif ch == "[":
            stack.append((x, y, a, level))
            level += 1
        elif ch == "]":
            x, y, a, level = stack.pop()
    return segs


def fit(segs, x, y, w, h):
    """Scale and move segments to fit inside a box, keeping their shape, standing on the
    middle of the box's bottom edge (where a plant's root goes)."""
    xs = [v for s in segs for v in (s[0], s[2])]
    ys = [v for s in segs for v in (s[1], s[3])]
    k = min(w / max(max(xs) - min(xs), 1e-9), h / max(max(ys) - min(ys), 1e-9))
    mx = (max(xs) + min(xs)) / 2
    return [(x + w / 2 + (x1 - mx) * k, y + h + (y1 - max(ys)) * k,
             x + w / 2 + (x2 - mx) * k, y + h + (y2 - max(ys)) * k, lv)
            for x1, y1, x2, y2, lv in segs]


# --- Penrose tiling ------------------------------------------------------------
def penrose(x, y, w, h, edge):
    """A Penrose tiling (P3) covering a rectangle: two diamond-shaped tiles, a thick one and
    a thin one, that fill the floor without the pattern ever repeating exactly.
    edge: the side length of a tile, in pixels (every tile has the same side length).

    Returns a list of (kind, points, whole): kind is "thick" or "thin"; whole is False for
    tiles cut by the rectangle's edge. Keep the drawing inside the rectangle with c.clip().
    Count whole and cut tiles of each kind for a cutting list.
    """
    cx, cy = x + w / 2, y + h / 2
    radius = math.hypot(w, h) / 2 / math.cos(math.pi / 10) * 1.05  # the starting wheel must cover the corners
    rounds = max(0, round(math.log(radius / edge) / math.log(GOLDEN)))
    tris = []
    for i in range(10):  # start with a wheel of ten triangles
        b, c = cmath.rect(1, (2 * i - 1) * math.pi / 10), cmath.rect(1, (2 * i + 1) * math.pi / 10)
        if i % 2 == 0:
            b, c = c, b
        tris.append((0, 0j, b, c))
    for _ in range(rounds):  # split each triangle into smaller ones
        out = []
        for kind, a, b, c in tris:
            if kind == 0:
                p = a + (b - a) / GOLDEN
                out += [(0, c, p, b), (1, p, c, a)]
            else:
                q = b + (a - b) / GOLDEN
                r = b + (c - b) / GOLDEN
                out += [(1, r, c, a), (1, q, r, b), (0, r, q, a)]
        tris = out
    # Each tile is two triangles joined along their side b-c.
    halves = {}
    for kind, a, b, c in tris:
        key = (kind,) + tuple(sorted((round(z.real, 6), round(z.imag, 6)) for z in (b, c)))
        halves.setdefault(key, []).append((a, b, c))
    tiles = []
    for parts in halves.values():
        if len(parts) != 2:
            continue
        (a1, b, c), (a2, _, _) = parts
        pts = [(cx + z.real * radius, cy + z.imag * radius) for z in (a1, b, a2, c)]
        inside = [x <= px <= x + w and y <= py <= y + h for px, py in pts]
        if not any(inside):
            mx, my = centroid(pts)
            if not (x - edge <= mx <= x + w + edge and y - edge <= my <= y + h + edge):
                continue
        u, v = b - a1, c - a1
        angle = abs(math.degrees(cmath.phase(v / u)))
        kind = "thin" if angle < 50 or angle > 130 else "thick"
        tiles.append((kind, pts, all(inside)))
    return tiles


# --- Islamic geometric star patterns ---------------------------------------------
def _tiles(x, y, w, h, size, tiling, gx, gy):
    """Polygons of a simple tiling covering the rectangle, with a spare row round it.
    (gx, gy) is where one tile's centre goes - that is where a star's centre ends up."""
    def span(lo, length, origin, step):  # tile numbers covering lo..lo+length
        return range(math.floor((lo - origin) / step) - 1, math.ceil((lo + length - origin) / step) + 2)

    polys = []
    if tiling == "square":
        hs = size / 2
        for i in span(x, w, gx, size):
            for j in span(y, h, gy, size):
                sx, sy = gx + i * size, gy + j * size
                polys.append([(sx - hs, sy - hs), (sx + hs, sy - hs), (sx + hs, sy + hs), (sx - hs, sy + hs)])
    elif tiling == "octagon":  # octagons with small squares between them
        a = size / (1 + 2 ** 0.5)  # side of an octagon (and of a small square)
        rv = a / (2 * math.sin(math.pi / 8))
        for i in span(x, w, gx, size):
            for j in span(y, h, gy, size):
                ox, oy = gx + i * size, gy + j * size
                polys.append([(ox + rv * math.cos(math.pi / 8 + k * math.pi / 4),
                               oy + rv * math.sin(math.pi / 8 + k * math.pi / 4)) for k in range(8)])
                sx, sy, d = ox + size / 2, oy + size / 2, a / 2 ** 0.5
                polys.append([(sx, sy - d), (sx + d, sy), (sx, sy + d), (sx - d, sy)])
    elif tiling == "hexagon":
        r = size / 3 ** 0.5  # size is the distance between hexagon centres
        for i in span(x, w, gx, 1.5 * r):
            for j in span(y, h, gy, size):
                hx, hy = gx + i * 1.5 * r, gy + j * size + (size / 2 if i % 2 else 0)
                polys.append([(hx + r * math.cos(k * math.pi / 3), hy + r * math.sin(k * math.pi / 3))
                              for k in range(6)])
    else:
        raise ValueError('tiling must be "square", "octagon" or "hexagon"')
    return polys


def _ray_toward(m, corner, t, inside):
    """Direction from point m towards a corner, turned by angle t towards the inside."""
    ex, ey = corner[0] - m[0], corner[1] - m[1]
    length = math.hypot(ex, ey)
    ex, ey = ex / length, ey / length
    for s in (1, -1):
        dx = ex * math.cos(s * t) - ey * math.sin(s * t)
        dy = ex * math.sin(s * t) + ey * math.cos(s * t)
        if dx * (inside[0] - m[0]) + dy * (inside[1] - m[1]) > 0:
            return dx, dy
    return None


def _meet(p, d, q, e):
    """Where the ray from p along d meets the line through q along e."""
    den = d[0] * e[1] - d[1] * e[0]
    if abs(den) < 1e-9:
        return None
    s = ((q[0] - p[0]) * e[1] - (q[1] - p[1]) * e[0]) / den
    return (p[0] + s * d[0], p[1] + s * d[1]) if s > 0 else None


def star_pattern(x, y, w, h, size, tiling="octagon", angle=67.5, centre=True):
    """Lines of an Islamic geometric star pattern filling a rectangle, as used in jaali
    screens, tiles and inlay. It starts from a simple tiling and, from the middle of every
    tile edge, draws two lines into the tile at `angle` degrees to the edge until they meet
    the lines from the next edge (Hankin's method). The lines join up across tiles into
    stars and interlacing bands.

    tiling: "octagon" (8-point stars, the classic look), "square" (4- and 8-point stars) or
            "hexagon" (6-point stars). size: distance between star centres, in pixels.
    angle:  how far the lines turn in from the edge. Lower = sharper, more open stars.
            Good values: octagon 67.5 (try 60-75), square 67.5, hexagon 60 (try 55-70).
    centre: True puts a star in the exact middle of the rectangle, so the pattern is even
            on both sides of a panel; False starts from the top-left corner.

    Returns a list of segments ((x1, y1), (x2, y2)). Keep them inside the rectangle with
    c.clip(). For a carved screen, fill the panel with a dark colour (the holes) and draw the
    segments as thick lines in the panel colour with stroke_linecap="round" - the lines are
    the stone or wood that is left. Add a solid frame round the edge.
    """
    t = math.radians(angle)
    segs = []
    gx, gy = (x + w / 2, y + h / 2) if centre else (x, y)
    for poly in _tiles(x, y, w, h, size, tiling, gx, gy):
        n, mid = len(poly), centroid(poly)
        mids = [((poly[i][0] + poly[(i + 1) % n][0]) / 2, (poly[i][1] + poly[(i + 1) % n][1]) / 2)
                for i in range(n)]
        for i in range(n):
            j, corner = (i + 1) % n, poly[(i + 1) % n]
            d1 = _ray_toward(mids[i], corner, t, mid)
            d2 = _ray_toward(mids[j], corner, t, mid)
            if not d1 or not d2:
                continue
            meet = _meet(mids[i], d1, mids[j], d2)
            if meet:
                segs += [(mids[i], meet), (mids[j], meet)]
    return segs
