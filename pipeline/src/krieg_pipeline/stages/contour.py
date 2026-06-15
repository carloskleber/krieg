"""Stage 5 — contour: derive contour lines (and a hillshade) from the DEM.

OSM has no relief, so we synthesise it (ADR-0006). Contours come out as vector
``relief`` features in local metres (joined with the rest of the board); the
hillshade is an optional raster backdrop (ADR-0004).
"""

from __future__ import annotations

import logging
import math
from dataclasses import dataclass
from pathlib import Path

import geopandas as gpd
import numpy as np
from shapely.affinity import translate
from shapely.geometry import LineString

from .reproject import Projection

log = logging.getLogger(__name__)


@dataclass
class Relief:
    contours: gpd.GeoDataFrame  # local metres, column: elevation
    hillshade_path: Path | None
    hillshade_bounds: tuple[float, float, float, float] | None  # in local metres
    elevation_range: tuple[float, float] | None


def _grids(transform, width: int, height: int):
    """Cell-centre lon/lat coordinate grids for an affine transform."""
    cols = np.arange(width) + 0.5
    rows = np.arange(height) + 0.5
    xs = transform.c + cols * transform.a  # transform.b == 0 for north-up
    ys = transform.f + rows * transform.e
    return np.meshgrid(xs, ys)


def _contour_lines(z, X, Y, interval: float):
    """Marching-squares contour extraction via matplotlib, kept headless."""
    import matplotlib

    matplotlib.use("Agg")
    from matplotlib import pyplot as plt

    zmin, zmax = float(np.nanmin(z)), float(np.nanmax(z))
    lo = math.ceil(zmin / interval) * interval
    hi = math.floor(zmax / interval) * interval
    if hi < lo:
        return [], (zmin, zmax)
    levels = np.arange(lo, hi + interval, interval)

    fig = plt.figure()
    try:
        cs = plt.contour(X, Y, z, levels=levels)
        out = []
        # Matplotlib >=3.8: use get_paths(); fall back to allsegs for older.
        if hasattr(cs, "allsegs"):
            for level, segs in zip(cs.levels, cs.allsegs):
                for seg in segs:
                    if len(seg) >= 2:
                        out.append((float(level), LineString(seg)))
        return out, (zmin, zmax)
    finally:
        plt.close(fig)


def _hillshade(z, azimuth=315.0, altitude=45.0):
    """Standard hillshade (0–255) from an elevation array."""
    z = np.nan_to_num(z, nan=float(np.nanmin(z)))
    dy, dx = np.gradient(z)
    slope = np.pi / 2.0 - np.arctan(np.hypot(dx, dy))
    aspect = np.arctan2(-dx, dy)
    az = np.radians(360.0 - azimuth + 90.0)
    alt = np.radians(altitude)
    shaded = np.sin(alt) * np.sin(slope) + np.cos(alt) * np.cos(slope) * np.cos(
        az - aspect
    )
    return (np.clip((shaded + 1) / 2, 0, 1) * 255).astype(np.uint8)


def contour(
    dem_path: Path | None, proj: Projection, interval: float, assets_dir: Path
) -> Relief:
    empty = gpd.GeoDataFrame(
        {"elevation": []}, geometry=[], crs=proj.crs
    )
    if dem_path is None:
        return Relief(empty, None, None, None)

    import rasterio

    with rasterio.open(dem_path) as src:
        z = src.read(1).astype("float64")
        if src.nodata is not None:
            z[z == src.nodata] = np.nan
        z[z < -1000] = np.nan  # guard against sentinel voids
        transform, dem_crs = src.transform, src.crs
        height, width = z.shape

    if np.all(np.isnan(z)):
        log.warning("DEM is all-nodata; no relief generated.")
        return Relief(empty, None, None, None)

    X, Y = _grids(transform, width, height)
    lines, (zmin, zmax) = _contour_lines(z, X, Y, interval)

    if lines:
        elevs = [e for e, _ in lines]
        geoms = gpd.GeoSeries([g for _, g in lines], crs=dem_crs)
        local = geoms.to_crs(proj.crs).apply(
            lambda g: translate(g, xoff=-proj.origin[0], yoff=-proj.origin[1])
        )
        contours = gpd.GeoDataFrame({"elevation": elevs}, geometry=list(local), crs=proj.crs)
    else:
        contours = empty
    log.info("Generated %d contour segments (%.0f–%.0f m).", len(contours), zmin, zmax)

    # Hillshade backdrop.
    hs_path = hs_bounds = None
    try:
        import matplotlib

        matplotlib.use("Agg")
        from matplotlib import image as mpimg

        assets_dir.mkdir(parents=True, exist_ok=True)
        hs_path = assets_dir / "hillshade.png"
        mpimg.imsave(hs_path, _hillshade(z), cmap="gray", vmin=0, vmax=255)

        corners = gpd.GeoSeries.from_xy(
            [transform.c, transform.c + width * transform.a],
            [transform.f + height * transform.e, transform.f],
            crs=dem_crs,
        ).to_crs(proj.crs)
        xs = [p.x - proj.origin[0] for p in corners]
        ys = [p.y - proj.origin[1] for p in corners]
        hs_bounds = (min(xs), min(ys), max(xs), max(ys))
        log.info("Hillshade written -> %s", hs_path)
    except Exception as exc:  # noqa: BLE001
        log.warning("Hillshade generation failed: %s", exc)
        hs_path = hs_bounds = None

    return Relief(contours, hs_path, hs_bounds, (zmin, zmax))
