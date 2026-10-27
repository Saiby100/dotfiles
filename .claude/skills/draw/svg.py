#!/usr/bin/env python3
"""Small helper for drawing SVG pictures with plain Python.

Import it from a throwaway script:

    import os, sys; sys.path.insert(0, os.path.expanduser("~/.claude/skills/draw"))
    from svg import Canvas, PALETTES

    c = Canvas(800, 600, background="#faf7f2")
    c.rect(100, 100, 300, 200, fill=PALETTES["earth"][0], stroke="#333")
    c.dimension(100, 320, 400, 320, "120 cm")
    c.save("resources/table.svg", preview=True)

Only Python's built-in libraries are used, so there is nothing to install.
Coordinates are in pixels, measured from the top-left corner.
"""

import math
import os
import random
import subprocess
import tempfile
from xml.sax.saxutils import escape

# Where preview PNGs are written.
PREVIEW_FOLDER = os.path.expanduser("~/Pictures/Draw")

# Colour sets that look good together. Each is dark-to-light or a loose group.
PALETTES = {
    "earth":  ["#5b3a29", "#8c5a3c", "#c08552", "#dab49d", "#f3e9dc"],
    "ocean":  ["#03045e", "#0077b6", "#00b4d8", "#90e0ef", "#caf0f8"],
    "forest": ["#1b4332", "#2d6a4f", "#52b788", "#95d5b2", "#d8f3dc"],
    "sunset": ["#3d0c45", "#8f2d56", "#d81159", "#ff8c42", "#ffd166"],
    "mono":   ["#111111", "#444444", "#777777", "#aaaaaa", "#dddddd"],
    "pastel": ["#ffadad", "#ffd6a5", "#fdffb6", "#caffbf", "#9bf6ff", "#bdb2ff"],
    "bold":   ["#264653", "#2a9d8f", "#e9c46a", "#f4a261", "#e76f51"],
    "wood":   ["#4a2c17", "#7b4a26", "#a86f3d", "#c9965f", "#e8c9a0"],
}


def _attrs(**kw):
    """Turn keyword arguments into SVG attributes (stroke_width -> stroke-width)."""
    parts = []
    for key, value in kw.items():
        if value is None:
            continue
        name = key.rstrip("_").replace("_", "-")
        parts.append(f'{name}="{escape(str(value), {chr(34): "&quot;"})}"')
    return " ".join(parts)


def smooth(points, closed=False, tension=1.0):
    """Path data for a smooth curve through the given points (Catmull-Rom spline).

    Much easier than placing Bezier control points: list points along the outline you
    want and the curve passes through each one. Use with c.path(smooth(pts, closed=True)).
    A lower tension (e.g. 0.5) gives flatter curves between points; 0 gives straight lines.
    To make a sharp corner, repeat a point twice.
    """
    pts = list(points)
    if closed and len(pts) > 2 and pts[-1] == pts[0]:
        pts.pop()  # a closed outline doesn't need its first point again (e.g. half + mirror)
    if closed:
        ext = [pts[-1]] + pts + [pts[0], pts[1]]
    else:
        ext = [pts[0]] + pts + [pts[-1]]
    d = [f"M{pts[0][0]:.2f},{pts[0][1]:.2f}"]
    t = tension / 6
    for i in range(1, len(ext) - 2):
        p0, p1, p2, p3 = ext[i - 1], ext[i], ext[i + 1], ext[i + 2]
        if p1 == p2:
            continue  # a repeated point is a sharp corner; drawing it would add a tiny loop
        # Next to a corner, aim straight at it so the curve doesn't overshoot.
        if p0 == p1:
            p0 = (2 * p1[0] - p2[0], 2 * p1[1] - p2[1])
        if p2 == p3:
            p3 = (2 * p2[0] - p1[0], 2 * p2[1] - p1[1])
        c1 = (p1[0] + (p2[0] - p0[0]) * t, p1[1] + (p2[1] - p0[1]) * t)
        c2 = (p2[0] - (p3[0] - p1[0]) * t, p2[1] - (p3[1] - p1[1]) * t)
        d.append(f"C{c1[0]:.2f},{c1[1]:.2f} {c2[0]:.2f},{c2[1]:.2f} {p2[0]:.2f},{p2[1]:.2f}")
    if closed:
        d.append("Z")
    return " ".join(d)


def mirror(points, cx):
    """The points flipped left-to-right around the vertical line x = cx, in reverse order.

    For symmetric shapes, list one half from top to bottom and join it with its mirror:
        half = [(512, 210), (430, 300), (385, 345), (282, 450), (282, 590)]
        outline = half + mirror(half, 512)
    """
    return [(2 * cx - x, y) for x, y in reversed(points)]


# Settings for c.texture(): noise frequency across, noise frequency down, layers of detail,
# and how strongly it darkens. A low frequency across and a high one down gives streaks.
TEXTURES = {
    "paper":  (0.9, 0.9, 4, 0.15),
    "grain":  (0.6, 0.6, 2, 0.25),   # film grain, sand, matte print
    "stone":  (0.04, 0.04, 5, 0.4),
    "wood":   (0.008, 0.25, 3, 0.45),  # grain runs left to right
    "brushed": (0.002, 0.6, 2, 0.2),  # brushed metal, left to right
    "clouds": (0.012, 0.012, 4, 0.5),
}


def zoom(image_path, x, y, w, h, scale=2):
    """Crop part of a picture and enlarge it, to measure shapes in it. Returns the path of
    the enlarged crop (in the temp folder); open it with the Read tool. A point at (X, Y) in
    the crop is at (x + X / scale, y + Y / scale) in the original. Uses macOS's sips."""
    out = os.path.join(tempfile.mkdtemp(prefix="draw-zoom-"), f"zoom-{x}-{y}.png")
    subprocess.run(["sips", "-s", "format", "png", "-c", str(h), str(w), "--cropOffset", str(y), str(x),
                    image_path, "--out", out], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(["sips", "-Z", str(round(max(w, h) * scale)), out],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return out


def _read_png(path):
    """Decode a PNG into (width, height, rows of (r, g, b) tuples) with plain Python.
    Other formats (JPG etc.) are converted to PNG with sips first."""
    import struct
    import zlib
    with open(path, "rb") as f:
        is_png = f.read(8) == b"\x89PNG\r\n\x1a\n"  # by content: some ".png" files are JPEGs
    if not is_png:
        tmp = os.path.join(tempfile.mkdtemp(prefix="draw-png-"), "in.png")
        subprocess.run(["sips", "-s", "format", "png", path, "--out", tmp],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        path = tmp
    with open(path, "rb") as f:
        data = f.read()
    pos, idat, palette = 8, b"", None
    while pos < len(data):
        length, kind = struct.unpack(">I4s", data[pos:pos + 8])
        chunk = data[pos + 8:pos + 8 + length]
        if kind == b"IHDR":
            w, h, depth, ctype, _, _, interlace = struct.unpack(">IIBBBBB", chunk)
        elif kind == b"PLTE":
            palette = [tuple(chunk[i:i + 3]) for i in range(0, len(chunk), 3)]
        elif kind == b"IDAT":
            idat += chunk
        pos += 12 + length
    if depth != 8 or interlace:
        raise ValueError("only 8-bit, non-interlaced PNGs can be sampled; convert it with sips first")
    bpp = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}[ctype]
    raw = zlib.decompress(idat)
    stride = w * bpp
    rows, prev = [], bytearray(stride)
    for y in range(h):
        f = raw[y * (stride + 1)]
        line = bytearray(raw[y * (stride + 1) + 1:(y + 1) * (stride + 1)])
        for i in range(stride):
            a = line[i - bpp] if i >= bpp else 0
            b = prev[i]
            c = prev[i - bpp] if i >= bpp else 0
            if f == 1:
                line[i] = (line[i] + a) & 255
            elif f == 2:
                line[i] = (line[i] + b) & 255
            elif f == 3:
                line[i] = (line[i] + (a + b) // 2) & 255
            elif f == 4:
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                line[i] = (line[i] + (a if pa <= pb and pa <= pc else b if pb <= pc else c)) & 255
        prev = line
        if ctype == 3:
            rows.append([palette[v] for v in line])
        elif ctype in (0, 4):
            rows.append([(v, v, v) for v in line[::bpp]])
        else:
            rows.append([tuple(line[i:i + 3]) for i in range(0, stride, bpp)])
    return w, h, rows


def sample_colours(image_path, points, radius=2):
    """The colours of a picture at the given (x, y) points, as "#rrggbb", each averaged over
    a small square so noise doesn't skew it. Use it to take colours from an original you
    are matching, e.g. a gradient's colours at a few heights. Plain Python, nothing to install."""
    w, h, rows = _read_png(image_path)
    out = []
    for x, y in points:
        px = [rows[yy][xx] for yy in range(max(0, y - radius), min(h, y + radius + 1))
              for xx in range(max(0, x - radius), min(w, x + radius + 1))]
        out.append("#%02x%02x%02x" % tuple(sum(p[i] for p in px) // len(px) for i in range(3)))
    return out


def _find_browser():
    """A Chrome-type browser for previews: it draws filters, textures and shadows,
    which macOS's sips leaves out."""
    for app in ("Google Chrome", "Chromium", "Brave Browser", "Microsoft Edge"):
        exe = f"/Applications/{app}.app/Contents/MacOS/{app}"
        if os.path.exists(exe):
            return exe
    for name in ("google-chrome", "chromium", "chromium-browser"):
        for d in os.environ.get("PATH", "").split(os.pathsep):
            if os.path.exists(os.path.join(d, name)):
                return os.path.join(d, name)
    return None


class Canvas:
    def __init__(self, width, height, background="#ffffff", seed=1):
        self.width = width
        self.height = height
        self.items = []
        self.defs = []
        self.seed = seed
        self.rng = random.Random(seed)  # same seed -> same picture
        self.reference_image = None  # shown in previews only, never saved
        if background:
            self.rect(0, 0, width, height, fill=background)

    # --- basic shapes -----------------------------------------------------
    def add(self, raw):
        """Add any raw SVG text."""
        self.items.append(raw)

    def rect(self, x, y, w, h, fill="none", stroke=None, stroke_width=None, rx=None, **kw):
        self.add(f"<rect {_attrs(x=x, y=y, width=w, height=h, rx=rx, fill=fill, stroke=stroke, stroke_width=stroke_width, **kw)}/>")

    def circle(self, cx, cy, r, fill="none", stroke=None, stroke_width=None, **kw):
        self.add(f"<circle {_attrs(cx=cx, cy=cy, r=r, fill=fill, stroke=stroke, stroke_width=stroke_width, **kw)}/>")

    def ellipse(self, cx, cy, rx, ry, fill="none", stroke=None, stroke_width=None, **kw):
        self.add(f"<ellipse {_attrs(cx=cx, cy=cy, rx=rx, ry=ry, fill=fill, stroke=stroke, stroke_width=stroke_width, **kw)}/>")

    def line(self, x1, y1, x2, y2, stroke="#000", stroke_width=1, **kw):
        self.add(f"<line {_attrs(x1=x1, y1=y1, x2=x2, y2=y2, stroke=stroke, stroke_width=stroke_width, **kw)}/>")

    def polyline(self, points, stroke="#000", stroke_width=1, fill="none", **kw):
        pts = " ".join(f"{x:.2f},{y:.2f}" for x, y in points)
        self.add(f"<polyline {_attrs(points=pts, fill=fill, stroke=stroke, stroke_width=stroke_width, **kw)}/>")

    def polygon(self, points, fill="none", stroke=None, stroke_width=None, **kw):
        pts = " ".join(f"{x:.2f},{y:.2f}" for x, y in points)
        self.add(f"<polygon {_attrs(points=pts, fill=fill, stroke=stroke, stroke_width=stroke_width, **kw)}/>")

    def path(self, d, fill="none", stroke=None, stroke_width=1, **kw):
        """A filled path gets no outline unless you give a stroke; an unfilled one gets a
        thin black line so it is visible."""
        if stroke is None and fill == "none":
            stroke = "#000"
        if stroke is None:
            stroke_width = None
        self.add(f"<path {_attrs(d=d, fill=fill, stroke=stroke, stroke_width=stroke_width, **kw)}/>")

    def text(self, x, y, content, size=16, fill="#222", anchor="start", weight="normal",
             font="Helvetica, Arial, sans-serif", **kw):
        """anchor: start (left), middle, or end (right). y is the text baseline."""
        self.add(f"<text {_attrs(x=x, y=y, font_size=size, fill=fill, text_anchor=anchor, font_weight=weight, font_family=font, **kw)}>{escape(str(content))}</text>")

    # --- groups, gradients ------------------------------------------------
    def group_start(self, transform=None, **kw):
        """Start a group, e.g. transform="rotate(30 400 300)". Close with group_end()."""
        self.add(f"<g {_attrs(transform=transform, **kw)}>")

    def group_end(self):
        self.add("</g>")

    def linear_gradient(self, gid, colours, x1=0, y1=0, x2=0, y2=1, span=None, offsets=None):
        """Define a gradient, then use fill="url(#gid)". Default runs top to bottom.

        By default each shape gets the whole gradient across its own size. To shade the
        whole picture as one, so every shape gets the colour for where it sits, give span
        in canvas pixels: span=((0, 200), (0, 820)) runs from y=200 to y=820.
        offsets (0-1, one per colour) place colours unevenly, e.g. at sampled heights."""
        offsets = offsets or [i / max(len(colours) - 1, 1) for i in range(len(colours))]
        stops = "".join(f'<stop offset="{o:.3f}" stop-color="{c}"/>' for o, c in zip(offsets, colours))
        if span:
            (x1, y1), (x2, y2) = span
            units = ' gradientUnits="userSpaceOnUse"'
        else:
            units = ""
        self.defs.append(f'<linearGradient id="{gid}"{units} x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}">{stops}</linearGradient>')

    def radial_gradient(self, gid, colours, cx=0.5, cy=0.5, r=0.5):
        """A round gradient from the centre outwards, used as fill="url(#gid)".
        Colours can be "#hex" or ("#hex", opacity), e.g. a glow that fades out:
        ["#fff3c4", ("#f5c96a", 0.6), ("#f5c96a", 0)]."""
        stops = []
        for i, c in enumerate(colours):
            colour, opacity = c if isinstance(c, tuple) else (c, 1)
            stops.append(f'<stop offset="{i / max(len(colours) - 1, 1):.3f}" '
                         f'stop-color="{colour}" stop-opacity="{opacity}"/>')
        self.defs.append(f'<radialGradient id="{gid}" cx="{cx}" cy="{cy}" r="{r}">{"".join(stops)}</radialGradient>')

    def mask(self, mid, cutouts, keep=None):
        """A mask that hides the given shapes, e.g. to cut a crescent out of a circle:
            c.mask("moon", ['<circle cx="532" cy="333" r="46"/>'])
            c.circle(515, 352, 52, fill="gold", mask="url(#moon)")
        keep: raw SVG shapes for the visible area (default: the whole canvas)."""
        keep = keep or [f'<rect width="{self.width}" height="{self.height}"/>']
        body = "".join(k.replace("/>", ' fill="#fff"/>', 1) for k in keep) + \
               "".join(c.replace("/>", ' fill="#000"/>', 1) for c in cutouts)
        self.defs.append(f'<mask id="{mid}">{body}</mask>')

    def clip(self, cid, shapes):
        """Keep a group inside the given raw SVG shapes - e.g. a pattern inside its frame:
            c.clip("panel", ['<rect x="40" y="40" width="300" height="600"/>'])
            c.group_start(clip_path="url(#panel)") ... c.group_end()"""
        self.defs.append(f'<clipPath id="{cid}">{"".join(shapes)}</clipPath>')

    # --- filters: blur, glow, shadow, texture -----------------------------
    # Define once, then add filter="url(#id)" to any shape or group.
    def blur(self, fid, amount=4):
        self.defs.append(f'<filter id="{fid}" x="-50%" y="-50%" width="200%" height="200%">'
                         f'<feGaussianBlur stdDeviation="{amount}"/></filter>')

    def glow(self, fid, amount=8, strength=1):
        """A soft light around the shape in its own colour (lanterns, neon, stars)."""
        nodes = '<feMergeNode in="b"/>' * max(1, round(strength))
        self.defs.append(f'<filter id="{fid}" x="-50%" y="-50%" width="200%" height="200%">'
                         f'<feGaussianBlur in="SourceGraphic" stdDeviation="{amount}" result="b"/>'
                         f'<feMerge>{nodes}<feMergeNode in="SourceGraphic"/></feMerge></filter>')

    def shadow(self, fid, dx=4, dy=6, blur=6, opacity=0.35, colour="#000"):
        """A drop shadow under the shape."""
        self.defs.append(f'<filter id="{fid}" x="-30%" y="-30%" width="160%" height="160%">'
                         f'<feDropShadow dx="{dx}" dy="{dy}" stdDeviation="{blur}" '
                         f'flood-color="{colour}" flood-opacity="{opacity}"/></filter>')

    def texture(self, fid, kind="paper", strength=None, scale=1):
        """A surface texture laid over the shape's own colour: paper, grain, stone, wood,
        brushed or clouds (see TEXTURES). strength 0-1 sets how dark it gets; scale above 1
        makes the pattern bigger. Uses the canvas seed, so the pattern repeats exactly."""
        fx, fy, octaves, default = TEXTURES[kind]
        k = default if strength is None else strength
        # Noise is roughly 0.25-0.75; map it to 1-k .. 1 so it only darkens.
        slope, icpt = 2 * k, 1 - 1.5 * k
        fn = f'type="linear" slope="{slope:.3f}" intercept="{icpt:.3f}"'
        self.defs.append(
            f'<filter id="{fid}" x="0" y="0" width="100%" height="100%">'
            f'<feTurbulence type="fractalNoise" baseFrequency="{fx / scale:.4f} {fy / scale:.4f}" '
            f'numOctaves="{octaves}" seed="{self.seed}" result="n"/>'
            f'<feColorMatrix in="n" type="saturate" values="0" result="g"/>'
            f'<feComponentTransfer in="g" result="t"><feFuncR {fn}/><feFuncG {fn}/><feFuncB {fn}/>'
            f'<feFuncA type="linear" slope="0" intercept="1"/></feComponentTransfer>'
            f'<feBlend in="SourceGraphic" in2="t" mode="multiply" result="m"/>'
            f'<feComposite in="m" in2="SourceGraphic" operator="in"/></filter>')

    # --- working from an existing picture ---------------------------------
    def reference(self, image_path, opacity=0.35):
        """Show a picture behind the drawing in previews only (never in the saved SVG),
        stretched to the canvas. Use it when copying or matching an existing image:
        save(preview=True) then also writes an overlay preview, so you can see exactly
        where your shapes are off."""
        self.reference_image = (os.path.abspath(image_path), opacity)

    # --- helpers for technical drawings -----------------------------------
    def grid(self, spacing, stroke="#e5e5e5", stroke_width=1):
        """Light background grid, e.g. one line every 10 cm."""
        x = 0
        while x <= self.width:
            self.line(x, 0, x, self.height, stroke=stroke, stroke_width=stroke_width)
            x += spacing
        y = 0
        while y <= self.height:
            self.line(0, y, self.width, y, stroke=stroke, stroke_width=stroke_width)
            y += spacing

    def dimension(self, x1, y1, x2, y2, label, offset=0, colour="#444", size=14):
        """A measurement line with arrow heads at both ends and a label in the middle."""
        ang = math.atan2(y2 - y1, x2 - x1)
        nx, ny = -math.sin(ang) * offset, math.cos(ang) * offset
        ax, ay, bx, by = x1 + nx, y1 + ny, x2 + nx, y2 + ny
        if offset:  # short lines joining the measured points to the measurement line
            self.line(x1, y1, ax, ay, stroke=colour, stroke_width=0.8)
            self.line(x2, y2, bx, by, stroke=colour, stroke_width=0.8)
        self.line(ax, ay, bx, by, stroke=colour, stroke_width=1)
        head = 8
        for (px, py, a) in ((ax, ay, ang), (bx, by, ang + math.pi)):
            self.polygon([(px, py),
                          (px + head * math.cos(a + 0.35), py + head * math.sin(a + 0.35)),
                          (px + head * math.cos(a - 0.35), py + head * math.sin(a - 0.35))],
                         fill=colour)
        mx, my = (ax + bx) / 2, (ay + by) / 2
        deg = math.degrees(ang)
        if deg > 90 or deg < -90:  # keep the label the right way up
            deg += 180
        self.add(f'<g transform="translate({mx:.2f} {my:.2f}) rotate({deg:.2f})">'
                 f'<text x="0" y="-5" font-size="{size}" fill="{colour}" text-anchor="middle" '
                 f'font-family="Helvetica, Arial, sans-serif">{escape(label)}</text></g>')

    # --- randomness -------------------------------------------------------
    def jitter(self, amount):
        """Random number between -amount and +amount, from the canvas seed."""
        return self.rng.uniform(-amount, amount)

    def pick(self, options):
        return self.rng.choice(options)

    def rng_for(self, name):
        """A separate random sequence for one part of the picture, still decided by the
        canvas seed. Give each pattern its own (patterns.voronoi(c.rng_for("paving"), ...)),
        so changing one part doesn't reshuffle the others."""
        return random.Random(f"{self.seed}-{name}")

    # --- output -----------------------------------------------------------
    def to_string(self, background=None, reference=False):
        defs = f"<defs>{''.join(self.defs)}</defs>" if self.defs else ""
        under = ""
        if background:
            under += f'<rect width="{self.width}" height="{self.height}" fill="{background}"/>'
        body = "\n".join(self.items)
        over = ""
        if reference and self.reference_image:
            import base64
            path, opacity = self.reference_image
            kind = "png" if path.lower().endswith(".png") else "jpeg"
            with open(path, "rb") as f:
                data = base64.b64encode(f.read()).decode()
            # The reference goes on top, faint, so both it and the drawing stay visible.
            over = (f'<image x="0" y="0" width="{self.width}" height="{self.height}" '
                    f'preserveAspectRatio="none" opacity="{opacity}" '
                    f'href="data:image/{kind};base64,{data}"/>')
        return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{self.width}" height="{self.height}" '
                f'viewBox="0 0 {self.width} {self.height}">\n{defs}\n{under}{body}\n{over}</svg>\n')

    def save(self, path, preview=False, preview_background=None):
        """Write the SVG. With preview=True, also write a PNG copy to ~/Pictures/Draw and
        return its path, so it can be looked at. preview_background (e.g. "#888") puts a
        colour behind the preview only - use it for see-through drawings, which otherwise
        look like they sit on white. If a reference picture is set, an overlay preview with
        it on top is written too.

        Previews use Chrome (or another Chrome-type browser) when installed, which draws
        everything; otherwise macOS's sips, which leaves out textures and drop shadows and
        ignores bold text."""
        os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
        with open(path, "w", encoding="utf-8") as f:
            f.write(self.to_string())
        if not preview:
            return path
        folder = PREVIEW_FOLDER
        os.makedirs(folder, exist_ok=True)
        name = os.path.basename(path)
        out = self._render(self.to_string(preview_background), os.path.join(folder, name + ".png"))
        print(f"preview: {out}" if out else "preview failed")
        if self.reference_image:
            ref = self._render(self.to_string(preview_background, reference=True),
                               os.path.join(folder, name + ".overlay.png"))
            print(f"overlay with reference: {ref}" if ref else "overlay preview failed")
        return out

    def _render(self, svg_text, png):
        src = os.path.join(tempfile.mkdtemp(prefix="draw-src-"), os.path.basename(png)[:-4] + ".svg")
        with open(src, "w", encoding="utf-8") as f:
            f.write(svg_text)
        browser = _find_browser()
        if browser:
            subprocess.run([browser, "--headless=new", "--disable-gpu", "--hide-scrollbars",
                            f"--window-size={self.width},{self.height}",
                            "--default-background-color=00000000",
                            f"--screenshot={png}", "file://" + src],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=60)
        if not os.path.exists(png):
            subprocess.run(["sips", "-s", "format", "png", src, "--out", png],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        return png if os.path.exists(png) else None
