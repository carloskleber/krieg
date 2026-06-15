"""Offline unit tests for the pipeline stages (no network)."""

from __future__ import annotations

import json
from pathlib import Path

import geopandas as gpd
import pytest
from shapely.geometry import LineString, Polygon

from krieg_pipeline.config import BBox, ScenarioConfig
from krieg_pipeline.ruleset import Ruleset
from krieg_pipeline.stages.classify import classify
from krieg_pipeline.stages.contour import Relief
from krieg_pipeline.stages.emit import emit
from krieg_pipeline.stages.filter import filter_features
from krieg_pipeline.stages.reproject import reproject

BBOX = BBox(4.38, 50.66, 4.43, 50.70)


def _features():
    rows = [
        {"osm_id": 1, "osm_type": "way", "tags": {"highway": "secondary", "name": "Chaussée"},
         "geometry": LineString([(4.39, 50.67), (4.41, 50.69)])},
        {"osm_id": 2, "osm_type": "way", "tags": {"highway": "motorway"},
         "geometry": LineString([(4.39, 50.67), (4.42, 50.68)])},
        {"osm_id": 3, "osm_type": "way", "tags": {"natural": "wood"},
         "geometry": Polygon([(4.40, 50.67), (4.41, 50.67), (4.41, 50.68), (4.40, 50.68)])},
        {"osm_id": 4, "osm_type": "way", "tags": {"power": "line"},
         "geometry": LineString([(4.39, 50.66), (4.40, 50.70)])},
        {"osm_id": 5, "osm_type": "way", "tags": {"man_made": "windmill"},
         "geometry": Polygon([(4.395, 50.675), (4.396, 50.675), (4.396, 50.676), (4.395, 50.676)])},
        {"osm_id": 6, "osm_type": "way", "tags": {"vespene": "geyser"},  # unclassified
         "geometry": Polygon([(4.42, 50.69), (4.421, 50.69), (4.421, 50.691), (4.42, 50.691)])},
    ]
    return gpd.GeoDataFrame(rows, geometry="geometry", crs="EPSG:4326")


def test_config_year_range():
    with pytest.raises(ValueError):
        ScenarioConfig(name="x", bbox=BBOX, target_year=1700)
    with pytest.raises(ValueError):
        ScenarioConfig(name="x", bbox=BBOX, target_year=1950)
    assert ScenarioConfig(name="x", bbox=BBOX, target_year=1880).hash()


def test_bbox_parse_and_validate():
    assert BBox.parse("4.38,50.66,4.43,50.70").as_tuple() == (4.38, 50.66, 4.43, 50.70)
    with pytest.raises(ValueError):
        BBox(4.43, 50.66, 4.38, 50.70)  # min > max


def test_filter_drops_anachronisms_and_keeps_period():
    ruleset = Ruleset.load(None)
    kept, report = filter_features(_features(), ruleset, year=1880)
    cats = set(kept["category"])
    # motorway + power dropped; wood/road/building kept; vespene unclassified.
    assert "road" in cats and "wood" in cats and "building" in cats
    assert report.dropped >= 3  # motorway, power, vespene
    assert sum(report.unclassified.values()) == 1
    # road got its period class.
    road = kept[kept["category"] == "road"].iloc[0]
    assert road["road_class"] == "chaussee"
    # windmill kept as a strongpoint.
    mill = kept[kept["building_role"] == "strongpoint"]
    assert len(mill) == 1


def test_reproject_is_metric_and_local_origin():
    ruleset = Ruleset.load(None)
    kept, _ = filter_features(_features(), ruleset, year=1880)
    projected, proj = reproject(kept, BBOX)
    assert proj.crs.is_projected
    # Board ~ a few km across, and all geometry sits in the local frame (>= 0).
    assert 1000 < proj.size_m[0] < 10000
    minx, miny, maxx, maxy = projected.total_bounds
    assert minx >= -1.0 and miny >= -1.0  # rebased to SW corner
    assert maxx <= proj.size_m[0] + 1 and maxy <= proj.size_m[1] + 1


def test_classify_and_emit_roundtrip(tmp_path: Path):
    ruleset = Ruleset.load(None)
    kept, _ = filter_features(_features(), ruleset, year=1880)
    projected, proj = reproject(kept, BBOX)
    empty_contours = gpd.GeoDataFrame({"elevation": []}, geometry=[], crs=proj.crs)
    board = classify(projected, empty_contours, cluster_buildings=False)
    relief = Relief(empty_contours, None, None, None)
    config = ScenarioConfig(name="test", bbox=BBOX, target_year=1880)

    path = emit(board, config, proj, relief, tmp_path)
    data = json.loads(path.read_text())

    assert data["format_version"] == "0.1"
    assert data["metadata"]["target_year"] == 1880
    assert data["metadata"]["crs"]["projected_epsg"] == proj.crs.to_epsg()
    assert "© OpenStreetMap contributors" == data["metadata"]["attribution"]["osm"]
    assert len(data["features"]) == len(board)
    # Coordinates are plain metres (small positive numbers), not degrees.
    geom = data["features"][0]["geometry"]
    assert geom["type"] in ("LineString", "Polygon", "Point", "MultiPolygon")


def test_building_clustering_collapses_dense_blocks():
    crs = "EPSG:32631"
    # 10 tiny adjacent footprints, 5 m apart -> should cluster.
    polys = [
        Polygon([(x, 0), (x + 3, 0), (x + 3, 3), (x, 3)]) for x in range(0, 50, 5)
    ]
    n = len(polys)
    board = gpd.GeoDataFrame(
        {
            "category": ["building"] * n,
            "name": [None] * n,
            "road_class": [None] * n,
            "water_class": [None] * n,
            "building_role": ["ordinary"] * n,
            "elevation": [None] * n,
        },
        geometry=polys,
        crs=crs,
    )
    empty = gpd.GeoDataFrame({"elevation": []}, geometry=[], crs=crs)
    out = classify(board, empty, cluster_buildings=True)
    assert (out["category"] == "settlement").any()
    assert not (out["building_role"] == "ordinary").any()
