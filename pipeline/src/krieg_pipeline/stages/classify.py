"""Stage 6 — classify: assemble the final board feature set.

Merges the filtered vector features with the synthesised relief contours, applies
the building-clustering knob (ADR-0006), and produces one tidy GeoDataFrame whose
every row carries a board ``category`` (ADR-0004). No rendering happens here —
just classification.
"""

from __future__ import annotations

import logging

import geopandas as gpd
import pandas as pd
from shapely.geometry import MultiPolygon, Polygon

log = logging.getLogger(__name__)

# Property columns carried per feature (besides geometry/category).
PROP_COLUMNS = ["name", "road_class", "water_class", "building_role", "elevation"]

# Clustering only kicks in past this many ordinary buildings (ADR-0006).
_CLUSTER_MIN = 8
# Footprints within this distance (metres) merge into one village block.
_CLUSTER_GAP_M = 18.0


def _cluster_buildings(board: gpd.GeoDataFrame) -> gpd.GeoDataFrame:
    is_ordinary = (board["category"] == "building") & (
        board["building_role"] == "ordinary"
    )
    ordinary = board[is_ordinary]
    if len(ordinary) < _CLUSTER_MIN:
        return board

    merged = ordinary.geometry.buffer(_CLUSTER_GAP_M).union_all()
    merged = merged.buffer(-_CLUSTER_GAP_M)  # erode back to ~original footprints
    polys = merged.geoms if isinstance(merged, MultiPolygon) else [merged]
    blocks = [p for p in polys if isinstance(p, Polygon) and not p.is_empty]

    block_gdf = gpd.GeoDataFrame(
        {
            "category": "settlement",
            "name": None,
            "road_class": None,
            "water_class": None,
            "building_role": None,
            "elevation": None,
        },
        geometry=blocks,
        crs=board.crs,
        index=range(len(blocks)),
    )
    log.info(
        "Clustered %d ordinary buildings into %d village blocks.",
        len(ordinary),
        len(block_gdf),
    )
    return pd.concat([board[~is_ordinary], block_gdf], ignore_index=True)


def classify(
    features: gpd.GeoDataFrame,
    contours: gpd.GeoDataFrame,
    cluster_buildings: bool,
) -> gpd.GeoDataFrame:
    crs = features.crs if not features.empty else contours.crs

    # Relief contours -> uniform schema.
    relief = contours.copy()
    if not relief.empty:
        relief["category"] = "relief"
        for col in PROP_COLUMNS:
            if col not in relief.columns:
                relief[col] = None

    parts = [df for df in (features, relief) if not df.empty]
    if not parts:
        board = gpd.GeoDataFrame(
            {"category": [], **{c: [] for c in PROP_COLUMNS}}, geometry=[], crs=crs
        )
    else:
        keep = ["category", *PROP_COLUMNS, "geometry"]
        parts = [df.reindex(columns=keep) for df in parts]
        board = gpd.GeoDataFrame(
            pd.concat(parts, ignore_index=True), geometry="geometry", crs=crs
        )

    if cluster_buildings and not board.empty:
        board = _cluster_buildings(board)

    board = board[~board.geometry.is_empty & board.geometry.notna()].reset_index(
        drop=True
    )
    log.info(
        "Board assembled: %d features across %d categories.",
        len(board),
        board["category"].nunique() if not board.empty else 0,
    )
    return board
