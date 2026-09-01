# Diagram sources

The architecture diagrams in `docs/images/` are generated, not drawn. Regenerating
them after an infrastructure change is a code edit, which is the point — the
previous Lucidchart export drifted until it described a cluster of EC2 instances
that never existed.

`awsdiag.py` is a small SVG builder: nested frames, icon nodes, and orthogonal
links with explicit waypoints. Layout is hand-placed rather than solved, because
Graphviz cannot express AWS Cloud / VPC / subnet containment and that containment
is most of what these diagrams communicate.

Icons are the official AWS architecture set, vendored by the `diagrams` package
and embedded as base64 so the SVG stands alone.

```bash
python3 -m venv .venv
.venv/bin/pip install diagrams            # for its icon assets only; no Graphviz needed
.venv/bin/python docs/diagrams/diagram_core.py docs/images/architecture-core.svg
.venv/bin/python docs/diagrams/diagram_data.py docs/images/architecture-data-pipeline.svg
```

Then rasterise. Any SVG renderer works; headless Chrome needs no extra install:

```bash
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
  --headless --force-device-scale-factor=2 --hide-scrollbars \
  --default-background-color=FFFFFFFF --window-size=1660,1250 \
  --screenshot=core.png file://$PWD/docs/images/architecture-core.svg
```

Every node maps to a resource in `infrastructure/`. `docs/architecture-inventory.md`
is the checklist.
