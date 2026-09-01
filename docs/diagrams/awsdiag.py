"""Minimal SVG builder for AWS architecture diagrams.

Hand-placed rather than graph-laid-out. Graphviz cannot express the nested
AWS Cloud / VPC / subnet containment that makes these diagrams readable, and
the whole point of this diagram is the containment.
"""
import base64, os, pathlib

# Official AWS architecture icons, vendored by the `diagrams` package:
#   python3 -m venv .venv && .venv/bin/pip install diagrams
# Set AWS_ICONS to that install's resources/aws directory, or let this find it.
ICONS = (pathlib.Path(os.environ["AWS_ICONS"]) if os.environ.get("AWS_ICONS") else next(
    (q for q in pathlib.Path(__file__).resolve().parents[2].glob(
        ".venv/lib/*/site-packages/resources/aws")), pathlib.Path("resources/aws")))

# AWS's own palette for grouping frames.
INK      = "#232F3E"   # squid ink: text, AWS Cloud frame
GREEN    = "#7AA116"   # VPC and public subnets
TEAL     = "#00A4A6"   # availability zones, private subnets
BLUE     = "#3B48CC"   # data tier
ORANGE   = "#ED7100"   # compute accents
GRAY     = "#5A6B86"
FONT = "-apple-system, BlinkMacSystemFont, 'Helvetica Neue', Arial, sans-serif"

_cache = {}
def icon_uri(rel):
    if rel not in _cache:
        p = ICONS / rel
        if not p.exists():
            raise FileNotFoundError(f"icon missing: {rel}")
        _cache[rel] = "data:image/png;base64," + base64.b64encode(p.read_bytes()).decode()
    return _cache[rel]


class Canvas:
    def __init__(self, w, h):
        self.w, self.h = w, h
        self.bg, self.mid, self.fg = [], [], []   # frames, links, nodes

    # ---- frames -----------------------------------------------------------
    def frame(self, x, y, w, h, title, color, fill="none", dashed=False,
              icon=None, opacity=1.0, title_dy=0):
        dash = ' stroke-dasharray="7 5"' if dashed else ''
        self.bg.append(
            f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="8" '
            f'fill="{fill}" fill-opacity="{opacity}" stroke="{color}" '
            f'stroke-width="2"{dash}/>')
        tx = x + 14
        if icon:
            self.bg.append(
                f'<image href="{icon_uri(icon)}" x="{tx}" y="{y+10}" '
                f'width="20" height="20"/>')
            tx += 26
        self.bg.append(
            f'<text x="{tx}" y="{y+25+title_dy}" font-family="{FONT}" font-size="13" '
            f'font-weight="600" fill="{color}">{title}</text>')

    def band(self, x, y, w, h, title, color, fill):
        self.frame(x, y, w, h, title, color, fill=fill, opacity=0.14)

    # ---- nodes ------------------------------------------------------------
    def node(self, cx, cy, icon, label, sub=None, size=46, above=False):
        """Icon centered on (cx, cy) with label(s) underneath."""
        self.fg.append(
            f'<image href="{icon_uri(icon)}" x="{cx-size/2}" y="{cy-size/2}" '
            f'width="{size}" height="{size}"/>')
        subs = [] if not sub else (sub if isinstance(sub, list) else [sub])
        if above:
            ly = cy - size/2 - 26 - 13*len(subs)
            self.fg.append(
                f'<text x="{cx}" y="{ly}" font-family="{FONT}" font-size="12" '
                f'font-weight="600" text-anchor="middle" fill="{INK}">{label}</text>')
            for i, line in enumerate(subs):
                self.fg.append(
                    f'<text x="{cx}" y="{ly+15+i*13}" font-family="{FONT}" '
                    f'font-size="10.5" text-anchor="middle" fill="{GRAY}">{line}</text>')
        else:
            self.fg.append(
                f'<text x="{cx}" y="{cy+size/2+16}" font-family="{FONT}" font-size="12" '
                f'font-weight="600" text-anchor="middle" fill="{INK}">{label}</text>')
            for i, line in enumerate(subs):
                self.fg.append(
                    f'<text x="{cx}" y="{cy+size/2+31+i*13}" font-family="{FONT}" '
                    f'font-size="10.5" text-anchor="middle" fill="{GRAY}">{line}</text>')

    def text(self, x, y, s, size=12, weight="400", fill=INK, anchor="start", italic=False):
        st = ' font-style="italic"' if italic else ''
        self.fg.append(
            f'<text x="{x}" y="{y}" font-family="{FONT}" font-size="{size}" '
            f'font-weight="{weight}" text-anchor="{anchor}" fill="{fill}"{st}>{s}</text>')

    # ---- links ------------------------------------------------------------
    def link(self, pts, label=None, dashed=False, color=INK, width=1.8,
             lx=None, ly=None, head=True, label_anchor="middle"):
        d = "M " + " L ".join(f"{x} {y}" for x, y in pts)
        dash = ' stroke-dasharray="6 4"' if dashed else ''
        marker = ' marker-end="url(#arrow)"' if head else ''
        if dashed and head:
            marker = ' marker-end="url(#arrowlight)"'
        self.mid.append(
            f'<path d="{d}" fill="none" stroke="{color}" stroke-width="{width}"'
            f'{dash} stroke-linejoin="round"{marker}/>')
        if label:
            if lx is None or ly is None:
                mx = sum(p[0] for p in pts) / len(pts)
                my = sum(p[1] for p in pts) / len(pts)
                lx, ly = (lx or mx), (ly or my)
            w = len(label) * 5.9 + 10
            off = {"middle": w/2, "start": 0, "end": w}[label_anchor]
            self.mid.append(
                f'<rect x="{lx-off}" y="{ly-11}" width="{w}" height="15" rx="3" '
                f'fill="#FFFFFF" fill-opacity="0.94"/>')
            self.mid.append(
                f'<text x="{lx}" y="{ly}" font-family="{FONT}" font-size="10.5" '
                f'text-anchor="{label_anchor}" fill="{GRAY}">{label}</text>')

    def render(self, path):
        svg = f'''<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="{self.w}" height="{self.h}" viewBox="0 0 {self.w} {self.h}">
<defs>
<marker id="arrow" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="6" markerHeight="6" orient="auto-start-reverse">
  <path d="M 0 0 L 10 5 L 0 10 z" fill="{INK}"/>
</marker>
<marker id="arrowlight" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="6" markerHeight="6" orient="auto-start-reverse">
  <path d="M 0 0 L 10 5 L 0 10 z" fill="{GRAY}"/>
</marker>
</defs>
<rect width="{self.w}" height="{self.h}" fill="#FFFFFF"/>
{chr(10).join(self.bg)}
{chr(10).join(self.mid)}
{chr(10).join(self.fg)}
</svg>'''
        pathlib.Path(path).write_text(svg)
        return path
