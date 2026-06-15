"""Stage 7 — emit: write the scenario package (ADR-0004).

A directory containing ``scenario.json`` (manifest + vector features in local
metres) and an optional ``assets/`` raster backdrop. The metadata block is
mandatory and carries attribution/licensing (ADR-0002), CRS/bbox/origin, and the
reproducibility fields (generator version + config hash, ADR-0003).
"""

from __future__ import annotations

import datetime as _dt
import json
import logging
from pathlib import Path

import geopandas as gpd
from shapely.geometry import mapping

from .. import SCENARIO_FORMAT_VERSION, __version__
from ..config import ScenarioConfig
from .contour import HEIGHTMAP_ENCODING, Relief
from .reproject import Projection

log = logging.getLogger(__name__)

_PROP_KEYS = ("name", "road_class", "water_class", "building_role", "elevation")

OSM_ATTRIBUTION = "© OpenStreetMap contributors"
OSM_LICENSE = "ODbL-1.0"
DEM_ATTRIBUTION = "Copernicus DEM © ESA / produced using Copernicus WorldDEM-30"
DEM_LICENSE = "Copernicus DEM open licence"


def _round_coords(obj, ndigits: int):
    if isinstance(obj, (list, tuple)):
        if obj and isinstance(obj[0], (int, float)):
            return [round(float(c), ndigits) for c in obj]
        return [_round_coords(o, ndigits) for o in obj]
    return obj


def _feature_dicts(board: gpd.GeoDataFrame, ndigits: int) -> list[dict]:
    features = []
    for row in board.itertuples(index=False):
        geom = mapping(row.geometry)
        geom["coordinates"] = _round_coords(geom["coordinates"], ndigits)
        props = {}
        for key in _PROP_KEYS:
            val = getattr(row, key, None)
            if val is not None and val == val:  # drop None and NaN
                props[key] = round(float(val), 2) if key == "elevation" else val
        features.append({"category": row.category, "props": props, "geometry": geom})
    return features


def emit(
    board: gpd.GeoDataFrame,
    config: ScenarioConfig,
    proj: Projection,
    relief: Relief,
    out_dir: Path,
    coord_precision: int = 2,
) -> Path:
    out_dir = Path(out_dir)
    assets_dir = out_dir / "assets"
    out_dir.mkdir(parents=True, exist_ok=True)

    assets: dict = {}
    if relief.hillshade_path and relief.hillshade_path.exists():
        assets_dir.mkdir(parents=True, exist_ok=True)
        dest = assets_dir / "hillshade.png"
        if relief.hillshade_path.resolve() != dest.resolve():
            dest.write_bytes(relief.hillshade_path.read_bytes())
        assets["hillshade"] = {
            "path": "assets/hillshade.png",
            "bounds_m": [round(b, 2) for b in (relief.hillshade_bounds or ())],
        }
    if relief.heightmap_path and relief.heightmap_path.exists():
        assets_dir.mkdir(parents=True, exist_ok=True)
        dest = assets_dir / "heightmap.png"
        if relief.heightmap_path.resolve() != dest.resolve():
            dest.write_bytes(relief.heightmap_path.read_bytes())
        assets["heightmap"] = {
            "path": "assets/heightmap.png",
            "bounds_m": [round(b, 2) for b in (relief.heightmap_bounds or ())],
            "elevation_range_m": (
                [round(e, 2) for e in relief.elevation_range]
                if relief.elevation_range
                else None
            ),
            "encoding": HEIGHTMAP_ENCODING,
        }

    bbox = config.bbox
    manifest = {
        "format_version": SCENARIO_FORMAT_VERSION,
        "metadata": {
            "name": config.name,
            "generator": f"krieg-pipeline {__version__}",
            "generated_utc": _dt.datetime.now(_dt.timezone.utc).isoformat(),
            "config_hash": config.hash(),
            "target_year": config.target_year,
            "contour_interval_m": config.contour_interval_m,
            "crs": {
                "projected_epsg": proj.crs.to_epsg(),
                "projected": proj.crs.to_string(),
                "geographic": "EPSG:4326",
            },
            "bbox_wgs84": list(bbox.as_tuple()),
            "origin_utm": [round(c, 3) for c in proj.origin],
            "board_size_m": [round(s, 1) for s in proj.size_m],
            "elevation_range_m": (
                [round(e, 1) for e in relief.elevation_range]
                if relief.elevation_range
                else None
            ),
            "attribution": {"osm": OSM_ATTRIBUTION, "dem": DEM_ATTRIBUTION},
            "license": {"osm": OSM_LICENSE, "dem": DEM_LICENSE},
        },
        "assets": assets,
        "features": _feature_dicts(board, coord_precision),
    }

    scenario_path = out_dir / "scenario.json"
    scenario_path.write_text(json.dumps(manifest, indent=1))
    log.info(
        "Wrote %s (%d features, %d assets).",
        scenario_path,
        len(manifest["features"]),
        len(assets),
    )
    return scenario_path
