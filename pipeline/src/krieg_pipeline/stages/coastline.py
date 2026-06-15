"""Stage 2b — coastline: synthesise the sea from ``natural=coastline`` ways.

OSM never tags the open sea as an area — the shore is a set of directed
``natural=coastline`` ways, and "water" is simply *the side of them the land is
not on* (OSM convention: land lies to the **left** of a coastline way's
direction of travel). An island scenario like Fundão therefore arrives with a
shoreline but no water polygon at all, so most of the board reads as dry land.

This stage rebuilds the missing water: it nodes the coastline linework against
the bbox rectangle, polygonises the faces that result, and keeps the faces that
fall on the seaward (right-hand) side of the nearest coastline segment. Those
faces are re-tagged ``natural=water`` so the ordinary period ruleset keeps them,
and the raw coastline ways — which classify as nothing — are dropped.

Runs in WGS84, right after clip and before filter (it speaks tags, not metres).
"""

from __future__ import annotations

import logging

import geopandas as gpd
import pandas as pd
from shapely.geometry import LineString, MultiLineString, Polygon, box
from shapely.ops import polygonize, unary_union

from ..config import BBox

log = logging.getLogger(__name__)


def _is_coastline(tags: dict | None) -> bool:
    return bool(tags) and tags.get("natural") == "coastline"


def _linestrings(geom) -> list[LineString]:
    """Flatten any geometry into the linestrings that make up its boundary."""
    if geom is None or geom.is_empty:
        return []
    gtype = geom.geom_type
    if gtype == "LineString":
        return [geom]
    if gtype == "MultiLineString":
        return list(geom.geoms)
    if gtype in ("Polygon", "MultiPolygon"):
        return _linestrings(geom.boundary)
    if gtype == "GeometryCollection":
        out: list[LineString] = []
        for g in geom.geoms:
            out.extend(_linestrings(g))
        return out
    return []


def _face_is_sea(face, segments: list, eps: float) -> bool:
    """Decide whether a polygonised face is open water.

    OSM puts land to the **left** of a coastline way's direction, sea to the
    right. For every coastline segment we drop a probe a hair to each side of its
    midpoint and see which lands inside this face: a left-probe hit votes "land",
    a right-probe hit votes "sea". Segments that don't border the face fall on
    neither side and don't vote. Tallying every bordering segment (rather than
    trusting the single nearest one) is robust when a face is hemmed in by
    coastline pieces running in different directions — the case that flips an
    island inside-out.
    """
    from shapely.geometry import Point

    land_votes = 0
    sea_votes = 0
    for ax, ay, bx, by in segments:
        dx = bx - ax
        dy = by - ay
        length = (dx * dx + dy * dy) ** 0.5
        if length <= 0.0:
            continue
        # Unit left normal (-dy, dx); midpoint of the segment.
        nx = -dy / length
        ny = dx / length
        mx = (ax + bx) * 0.5
        my = (ay + by) * 0.5
        if face.contains(Point(mx + nx * eps, my + ny * eps)):
            land_votes += 1
        elif face.contains(Point(mx - nx * eps, my - ny * eps)):
            sea_votes += 1
    return sea_votes > land_votes


def synthesize_water(
    features: gpd.GeoDataFrame, bbox: BBox
) -> tuple[gpd.GeoDataFrame, int]:
    """Replace ``natural=coastline`` ways with the sea polygon they imply.

    Returns the features with coastline rows dropped and any synthesised water
    polygons appended (tagged ``natural=water``), plus the count added.
    """
    if features.empty:
        return features, 0
    is_coast = features["tags"].apply(_is_coastline)
    if not is_coast.any():
        return features, 0

    bbox_poly = box(*bbox.as_tuple())
    coast = features[is_coast]
    rest = features[~is_coast]

    lines: list[LineString] = []
    segments: list[tuple[float, float, float, float]] = []
    for geom in coast.geometry:
        for ls in _linestrings(geom):
            clipped = ls.intersection(bbox_poly)
            lines.extend(_linestrings(clipped))
            # Side tests use the *original* (un-noded) orientation so the
            # land-on-left convention survives polygonisation.
            coords = list(ls.coords)
            for (ax, ay), (bx, by) in zip(coords, coords[1:]):
                segments.append((ax, ay, bx, by))

    if not lines or not segments:
        log.info("Coastline present but no usable linework; leaving as-is.")
        return rest.reset_index(drop=True), 0

    # Node the shore against the bbox edges and split it into faces.
    noded = unary_union(MultiLineString(lines).union(bbox_poly.boundary))
    faces = [f for f in polygonize(noded) if not f.is_empty]
    # Probe offset: a metre or so in degrees — small against the bbox, large
    # enough to sit cleanly inside the adjacent face.
    span = min(bbox.max_lon - bbox.min_lon, bbox.max_lat - bbox.min_lat)
    eps = span * 1e-3
    sea_faces = [f for f in faces if _face_is_sea(f, segments, eps)]

    if not sea_faces:
        log.info("Coastline yielded no seaward faces; leaving as-is.")
        return rest.reset_index(drop=True), 0

    sea = unary_union(sea_faces).intersection(bbox_poly)
    polys = list(sea.geoms) if sea.geom_type == "MultiPolygon" else [sea]
    polys = [p for p in polys if isinstance(p, Polygon) and not p.is_empty]

    water_rows = [
        {
            "osm_id": None,
            "osm_type": "synthetic",
            "tags": {"natural": "water", "krieg:source": "coastline"},
            "geometry": p,
        }
        for p in polys
    ]
    water = gpd.GeoDataFrame(water_rows, geometry="geometry", crs=features.crs)
    out = gpd.GeoDataFrame(
        pd.concat([rest, water], ignore_index=True),
        geometry="geometry",
        crs=features.crs,
    )
    log.info(
        "Coastline: %d shore ways -> %d sea polygon(s).",
        int(is_coast.sum()),
        len(polys),
    )
    return out, len(polys)
