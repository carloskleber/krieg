"""Stage 2 — clip: restrict all features to the requested bbox.

Overpass already bbox-limits the query, but ways may extend past the edge, so we
hard-clip to a clean rectangle (ADR-0002: DEM and OSM share the same extent).
"""

from __future__ import annotations

import logging

import geopandas as gpd
from shapely.geometry import box

from ..config import BBox

log = logging.getLogger(__name__)


def clip(features: gpd.GeoDataFrame, bbox: BBox) -> gpd.GeoDataFrame:
    if features.empty:
        return features
    clip_box = gpd.GeoDataFrame(
        geometry=[box(*bbox.as_tuple())], crs="EPSG:4326"
    )
    clipped = gpd.clip(features, clip_box).reset_index(drop=True)
    clipped = clipped[~clipped.geometry.is_empty & clipped.geometry.notna()]
    log.info("Clipped to bbox: %d -> %d features.", len(features), len(clipped))
    return clipped.reset_index(drop=True)
