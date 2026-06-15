# ADR-0003: Map ingestion pipeline in Python

- **Status:** Accepted (realised by the Phase 0 pipeline, 2026-06-14)
- **Date:** 2026-06-14
- **Deciders:** project owner

## Context

Turning OSM + a DEM into a period board (PLAN §4) is a geospatial batch job:
download, clip, filter/reclassify features, reproject, generate contours and
hillshade, and serialise. This is exactly what the Python geospatial stack is
built for, and it is the opposite of what the game engine is good at. ADR-0001
already accepts a two-language split joined by a file format.

## Decision

Implement the pipeline as a **Python** command-line tool. Core libraries:

- **osmnx / pyrosm / `osmium`** — fetch and parse OSM (Overpass for small areas,
  `.osm.pbf` for large).
- **geopandas + shapely** — feature tables, filtering, clipping, geometry ops.
- **pyproj** — reprojection to the local metric CRS (ADR-0004).
- **rasterio + GDAL (`gdal_contour`, hillshade)** — DEM handling, contour and
  hillshade generation.

The tool is a deterministic, scriptable command: input = bbox/place + config
(target year, contour interval, DEM source); output = a scenario package
(ADR-0004). It runs offline as a build step, not inside the game.

Pipeline stages (each a testable unit): `acquire → clip → filter → reproject →
contour → classify → emit`, matching PLAN §4.

## Alternatives considered

- **Do ingestion inside Godot (GDScript/C#).** Rejected — would reimplement
  mature GIS libraries badly; ties content generation to the engine.
- **Pure GDAL/ogr2ogr shell scripts.** Workable for parts but awkward for the
  feature filtering/classification logic; Python wraps GDAL while keeping the
  filter rules (ADR-0006) expressive and testable.
- **A hosted/online service.** Over-engineered for a single-user desktop tool;
  adds infra and ODbL redistribution questions. Rejected for now.

## Consequences

- A Python toolchain (with the GDAL native dependency) is required to *author*
  scenarios; **playing** them requires only the game client. This separation is
  intentional — authors and players have different setups.
- Filter rules (ADR-0006) live as data/config consumed here, so changing the
  "period look" doesn't require code changes.
- Stage boundaries let us cache intermediate artifacts (e.g. re-run contouring
  without re-downloading OSM) and unit-test classification independently of I/O.
- Reproducibility: same inputs + same tool version + same config ⇒ identical
  package (record version & config hash in metadata, ADR-0004).
