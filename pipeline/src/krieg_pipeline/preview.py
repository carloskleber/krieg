"""Quick-look renderer for a scenario package (M0 eyeball, PLAN §6).

Not the game client — just a matplotlib plot of the baked features so an author
can sanity-check a build. Reads only the public ``scenario.json`` contract.
"""

from __future__ import annotations

import json
import logging
from pathlib import Path

log = logging.getLogger(__name__)

# (colour, line width, is-filled), drawn in this order so fills sit under lines.
_STYLE = {
    "field": ("#d8cfa3", 0.0, True),
    "wood": ("#5a7d4a", 0.0, True),
    "settlement": ("#9c6b4a", 0.0, True),
    "water": ("#5b7fa6", 1.0, True),
    "building": ("#7a4a3a", 0.0, True),
    "relief": ("#b8a06a", 0.5, False),
    "road": ("#3a2f25", 0.8, False),
    "bridge": ("#000000", 2.0, False),
    "ford": ("#3a6f9a", 2.0, False),
}
_ORDER = ["field", "wood", "settlement", "water", "building", "relief", "road", "bridge", "ford"]


def render(scenario_path: Path, out_path: Path, dpi: int = 110) -> Path:
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    from shapely.geometry import shape

    data = json.loads(Path(scenario_path).read_text())
    by_cat: dict[str, list] = {}
    for feat in data["features"]:
        by_cat.setdefault(feat["category"], []).append(shape(feat["geometry"]))

    w, h = data["metadata"].get("board_size_m", [1000, 1000])
    fig, ax = plt.subplots(figsize=(10, 10 * h / w if w else 10))
    ax.set_facecolor("#efe7cf")

    for cat in _ORDER:
        if cat not in by_cat:
            continue
        color, lw, filled = _STYLE[cat]
        for geom in by_cat[cat]:
            gt = geom.geom_type
            if gt in ("Polygon", "MultiPolygon"):
                polys = geom.geoms if gt == "MultiPolygon" else [geom]
                for p in polys:
                    x, y = p.exterior.xy
                    ax.fill(
                        x, y,
                        color=color if filled else "none",
                        alpha=0.85 if filled else 1.0,
                        edgecolor=color, linewidth=lw,
                    )
            else:
                lines = geom.geoms if gt == "MultiLineString" else [geom]
                for line in lines:
                    x, y = line.xy
                    ax.plot(x, y, color=color, linewidth=max(lw, 0.4))

    ax.set_aspect("equal")
    ax.set_title(f"Krieg — {data['metadata'].get('name', '?')} "
                 f"({data['metadata'].get('target_year', '?')})")
    ax.set_xlabel("metres E of origin")
    ax.set_ylabel("metres N of origin")
    out_path = Path(out_path)
    fig.savefig(out_path, dpi=dpi, bbox_inches="tight")
    plt.close(fig)
    log.info("Preview written -> %s", out_path)
    return out_path
