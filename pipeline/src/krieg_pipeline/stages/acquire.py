"""Stage 1 — acquire: fetch OSM features (Overpass) and a DEM tile.

This is the only stage that touches the network (ADR-0002/0003). OSM comes from
the Overpass API with inline geometry; elevation from the public Copernicus
GLO-30 bucket. DEM acquisition is best-effort: if it fails, the build continues
without relief rather than aborting.
"""

from __future__ import annotations

import logging
import math
from dataclasses import dataclass
from pathlib import Path

import geopandas as gpd
import requests
from shapely.geometry import LineString, Point, Polygon

from ..config import BBox
from ..ruleset import Ruleset

log = logging.getLogger(__name__)

OVERPASS_URL = "https://overpass-api.de/api/interpreter"
COP_DEM_BASE = "https://copernicus-dem-30m.s3.amazonaws.com"

# Overpass requires an identifying User-Agent and rejects requests without one.
_USER_AGENT = "krieg-pipeline/0.1 (+https://github.com/ck/krieg)"
_HEADERS = {"User-Agent": _USER_AGENT, "Accept": "application/json"}

# Closed ways with these keys are areas (polygons); otherwise they are lines.
_AREA_KEYS = {"building", "landuse", "natural", "leisure", "amenity", "historic"}
_LINE_KEYS = {"highway", "waterway", "barrier", "railway"}


@dataclass
class Acquired:
    features: gpd.GeoDataFrame  # WGS84 (EPSG:4326), columns: osm_id, osm_type, tags, geometry
    dem_path: Path | None  # local GeoTIFF clipped to bbox, or None


def _build_query(bbox: BBox, fetch: list[str], timeout: int = 90) -> str:
    s, w, n, e = bbox.min_lat, bbox.min_lon, bbox.max_lat, bbox.max_lon
    selectors = []
    for key in fetch:
        selectors.append(f'  way["{key}"]({s},{w},{n},{e});')
        selectors.append(f'  node["{key}"]({s},{w},{n},{e});')
    body = "\n".join(selectors)
    return (
        f"[out:json][timeout:{timeout}];\n"
        f"(\n{body}\n);\n"
        f"out geom tags;"
    )


def _element_geometry(el: dict):
    """Turn one Overpass element into a shapely geometry, or None."""
    etype = el["type"]
    if etype == "node":
        return Point(el["lon"], el["lat"])
    if etype == "way":
        geom = el.get("geometry")
        if not geom or len(geom) < 2:
            return None
        coords = [(p["lon"], p["lat"]) for p in geom]
        tags = el.get("tags", {})
        closed = len(coords) >= 4 and coords[0] == coords[-1]
        is_area = closed and (
            tags.get("area") == "yes"
            or (_AREA_KEYS & tags.keys() and not (_LINE_KEYS & tags.keys()))
        )
        if is_area:
            try:
                return Polygon(coords)
            except Exception:  # noqa: BLE001 - degenerate ring
                return None
        return LineString(coords)
    return None


def fetch_osm(bbox: BBox, ruleset: Ruleset, session: requests.Session | None = None):
    """Fetch OSM features in ``bbox`` as a WGS84 GeoDataFrame."""
    query = _build_query(bbox, ruleset.fetch)
    log.info("Querying Overpass for %d selectors…", len(ruleset.fetch))
    sess = session or requests.Session()
    resp = sess.post(
        OVERPASS_URL, data={"data": query}, headers=_HEADERS, timeout=180
    )
    resp.raise_for_status()
    elements = resp.json().get("elements", [])

    rows = []
    for el in elements:
        geom = _element_geometry(el)
        if geom is None or geom.is_empty:
            continue
        rows.append(
            {
                "osm_id": el.get("id"),
                "osm_type": el["type"],
                "tags": el.get("tags", {}),
                "geometry": geom,
            }
        )
    gdf = gpd.GeoDataFrame(rows, geometry="geometry", crs="EPSG:4326")
    log.info("Overpass returned %d usable features (of %d elements).", len(gdf), len(elements))
    return gdf


def _dem_tile_name(lat: int, lon: int) -> str:
    ns = "N" if lat >= 0 else "S"
    ew = "E" if lon >= 0 else "W"
    return (
        f"Copernicus_DSM_COG_10_{ns}{abs(lat):02d}_00_{ew}{abs(lon):03d}_00_DEM"
    )


def _tiles_for_bbox(bbox: BBox) -> list[tuple[int, int]]:
    lats = range(math.floor(bbox.min_lat), math.floor(bbox.max_lat) + 1)
    lons = range(math.floor(bbox.min_lon), math.floor(bbox.max_lon) + 1)
    return [(la, lo) for la in lats for lo in lons]


def fetch_dem(bbox: BBox, work_dir: Path) -> Path | None:
    """Fetch & clip the Copernicus GLO-30 DEM covering ``bbox``.

    Best-effort: returns None on any failure (no auth required for the bucket,
    but it may be unreachable in some environments).
    """
    try:
        import rasterio
        from rasterio.mask import mask
        from rasterio.merge import merge
        from shapely.geometry import box
    except Exception:  # noqa: BLE001
        log.warning("rasterio unavailable; skipping DEM.")
        return None

    srcs = []
    try:
        with rasterio.Env(
            GDAL_HTTP_UNSAFESSL="YES",
            GDAL_DISABLE_READDIR_ON_OPEN="EMPTY_DIR",
            CPL_VSIL_CURL_ALLOWED_EXTENSIONS=".tif",
        ):
            for lat, lon in _tiles_for_bbox(bbox):
                name = _dem_tile_name(lat, lon)
                url = f"/vsicurl/{COP_DEM_BASE}/{name}/{name}.tif"
                try:
                    srcs.append(rasterio.open(url))
                    log.info("DEM tile opened: %s", name)
                except Exception as exc:  # noqa: BLE001
                    log.warning("DEM tile %s unavailable: %s", name, exc)
            if not srcs:
                return None

            mosaic, transform = merge(srcs)
            profile = srcs[0].profile.copy()
            profile.update(
                height=mosaic.shape[1], width=mosaic.shape[2], transform=transform
            )
            # Copernicus COGs carry no nodata, so mask(crop=True) would fill the
            # out-of-bbox corners with 0 and pollute the elevation range. Stamp a
            # sentinel so those cells are recognisably void downstream (contour).
            if profile.get("nodata") is None:
                profile["nodata"] = -32768.0

            clip_dir = work_dir / "dem"
            clip_dir.mkdir(parents=True, exist_ok=True)
            merged_path = clip_dir / "merged.tif"
            with rasterio.open(merged_path, "w", **profile) as dst:
                dst.write(mosaic)

            with rasterio.open(merged_path) as src:
                geom = [box(*bbox.as_tuple())]
                clipped, ctransform = mask(src, geom, crop=True)
                cprofile = src.profile.copy()
                cprofile.update(
                    height=clipped.shape[1],
                    width=clipped.shape[2],
                    transform=ctransform,
                )
                dem_path = clip_dir / "dem.tif"
                with rasterio.open(dem_path, "w", **cprofile) as dst:
                    dst.write(clipped)
            log.info("DEM clipped to bbox -> %s", dem_path)
            return dem_path
    except Exception as exc:  # noqa: BLE001
        log.warning("DEM acquisition failed (%s); continuing without relief.", exc)
        return None
    finally:
        for s in srcs:
            try:
                s.close()
            except Exception:  # noqa: BLE001
                pass


def acquire(bbox: BBox, ruleset: Ruleset, work_dir: Path) -> Acquired:
    features = fetch_osm(bbox, ruleset)
    dem_path = fetch_dem(bbox, work_dir)
    return Acquired(features=features, dem_path=dem_path)
