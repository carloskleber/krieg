"""Stage 4 — reproject: WGS84 → local metric CRS, rebased to the bbox SW corner.

The package stores geometry in **metres** with a local origin at the bbox's
south-west corner, so the board is a flat plane where 1 unit = 1 metre
(ADR-0004). We pick the UTM zone covering the bbox centroid.
"""

from __future__ import annotations

import logging
from dataclasses import dataclass

import geopandas as gpd
from pyproj import CRS
from pyproj.aoi import AreaOfInterest
from pyproj.database import query_utm_crs_info
from shapely.affinity import translate
from shapely.geometry import box

from ..config import BBox

log = logging.getLogger(__name__)


@dataclass
class Projection:
    crs: CRS  # the chosen UTM CRS
    origin: tuple[float, float]  # (easting, northing) subtracted to localise
    size_m: tuple[float, float]  # board width, height in metres


def pick_utm(bbox: BBox) -> CRS:
    """UTM zone covering the bbox centroid (ADR-0004)."""
    candidates = query_utm_crs_info(
        datum_name="WGS 84",
        area_of_interest=AreaOfInterest(
            west_lon_degree=bbox.min_lon,
            south_lat_degree=bbox.min_lat,
            east_lon_degree=bbox.max_lon,
            north_lat_degree=bbox.max_lat,
        ),
    )
    if not candidates:
        raise RuntimeError(f"no UTM zone found for {bbox}")
    return CRS.from_epsg(candidates[0].code)


def reproject(
    features: gpd.GeoDataFrame, bbox: BBox
) -> tuple[gpd.GeoDataFrame, Projection]:
    crs = pick_utm(bbox)

    # Project the bbox itself to find the local origin (SW corner) and extent.
    bbox_geo = gpd.GeoSeries([box(*bbox.as_tuple())], crs="EPSG:4326")
    bbox_utm = bbox_geo.to_crs(crs)
    minx, miny, maxx, maxy = bbox_utm.total_bounds
    origin = (minx, miny)
    size = (maxx - minx, maxy - miny)

    if features.empty:
        out = features.to_crs(crs) if features.crs else features
    else:
        out = features.to_crs(crs).copy()
        out["geometry"] = out.geometry.apply(
            lambda g: translate(g, xoff=-origin[0], yoff=-origin[1])
        )
        out.set_crs(crs, allow_override=True, inplace=True)

    proj = Projection(crs=crs, origin=origin, size_m=size)
    log.info(
        "Reprojected to %s; board %.0f×%.0f m, origin=(%.1f, %.1f).",
        crs.to_string(),
        size[0],
        size[1],
        origin[0],
        origin[1],
    )
    return out, proj
