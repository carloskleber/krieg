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
from krieg_pipeline.stages.contour import (
    HEIGHTMAP_ENCODING,
    Relief,
    _encode_heightmap,
    contour,
)
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

    assert data["format_version"] == "0.2"
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


def test_heightmap_encode_roundtrips():
    import numpy as np

    zmin, zmax = 87.4, 166.2
    z = np.linspace(zmin, zmax, 64).reshape(8, 8).astype("float64")
    z[0, 0] = np.nan  # a void should encode without error
    rgba = _encode_heightmap(z, zmin, zmax)

    assert rgba.shape == (8, 8, 4) and rgba.dtype == np.uint8
    u16 = rgba[..., 0].astype(np.uint16) * 256 + rgba[..., 1].astype(np.uint16)
    decoded = zmin + (u16 / 65535.0) * (zmax - zmin)
    # 16-bit over an ~80 m span resolves to ~1 mm; voids decode to the floor.
    assert abs(decoded[1, 1] - z[1, 1]) < 0.01
    assert decoded[0, 0] == pytest.approx(zmin)


def test_contour_emits_heightmap_asset(tmp_path: Path):
    import numpy as np
    import rasterio
    from PIL import Image
    from rasterio.transform import from_origin

    # A tiny synthetic WGS84 DEM ramp over the test bbox.
    w = h = 32
    res = (BBOX.max_lon - BBOX.min_lon) / w
    yy, xx = np.mgrid[0:h, 0:w]
    z = (90.0 + (xx / w) * 70.0 + (yy / h) * 5.0).astype("float32")
    dem = tmp_path / "dem.tif"
    with rasterio.open(
        dem, "w", driver="GTiff", height=h, width=w, count=1,
        dtype="float32", crs="EPSG:4326",
        transform=from_origin(BBOX.min_lon, BBOX.max_lat, res, res),
    ) as d:
        d.write(z, 1)

    _, proj = reproject(_features_geo(), BBOX)
    relief = contour(dem, proj, 10.0, tmp_path / "assets")

    assert relief.heightmap_path is not None and relief.heightmap_path.exists()
    assert relief.heightmap_bounds is not None
    im = Image.open(relief.heightmap_path)
    assert im.mode == "RGBA" and im.size == (w, h)

    # The asset is registered in the manifest with its decode metadata.
    board = classify(
        reproject(_features_geo(), BBOX)[0], relief.contours, cluster_buildings=False
    )
    config = ScenarioConfig(name="t", bbox=BBOX, target_year=1880)
    data = json.loads(emit(board, config, proj, relief, tmp_path).read_text())
    hm = data["assets"]["heightmap"]
    assert hm["path"] == "assets/heightmap.png"
    assert hm["encoding"] == HEIGHTMAP_ENCODING
    assert len(hm["bounds_m"]) == 4 and len(hm["elevation_range_m"]) == 2


def _features_geo():
    kept, _ = filter_features(_features(), Ruleset.load(None), year=1880)
    return kept
