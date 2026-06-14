# ADR-0002: Map & elevation data sources and licensing

- **Status:** Proposed
- **Date:** 2026-06-14
- **Deciders:** project owner

## Context

The board is built from two kinds of real-world data: **vector features**
(roads, water, woods, buildings, landuse) and **elevation** (to produce the
contours/relief that define 19th-century terrain). We must pick sources that are
(a) global enough to cover any chosen battlefield, (b) freely usable, and
(c) legally redistributable inside a shipped scenario package.

OSM is the obvious vector source but carries license obligations. Elevation is
*not* well covered by OSM and needs a separate DEM source.

## Decision

- **Vector features: OpenStreetMap**, obtained as a regional `.osm.pbf` extract
  (e.g. Geofabrik) clipped to the area, or via Overpass API for small areas.
- **Elevation: an open global DEM** — default **Copernicus GLO-30** (30 m,
  permissive ESA licence), with **SRTM 30 m** as a fallback. Higher-resolution
  national DEMs may be plugged in per-scenario when available.
- **Licensing is a first-class output.** OSM is **ODbL**: derived data is a
  "Produced Work"/"Derivative Database" and must carry attribution
  ("© OpenStreetMap contributors") and preserve the share-alike terms. Every
  scenario package embeds a machine-readable attribution/licence block, and the
  game client displays attribution on the board. DEM attribution (Copernicus /
  NASA) is recorded alongside.

## Alternatives considered

- **Vector:** commercial map APIs (Google/Mapbox/HERE) — richer in places but
  redistribution-restricted and unsuitable for baking into a shipped file.
  Rejected. Natural Earth — too coarse for a battlefield. Rejected.
- **Elevation:** SRTM 30 m (good, US-centric provenance, voids near poles);
  ASTER GDEM (noisier); national LiDAR DEMs (excellent but patchy coverage and
  varied licences). We default to Copernicus GLO-30 for clean global coverage
  and licence, allowing per-scenario overrides.
- **Ignore elevation, hand-draw contours.** Rejected — relief is central to the
  period aesthetic and to future LOS rules; deriving it from a DEM is cheap and
  reproducible.

## Consequences

- Scenario packages are **redistributable** provided attribution + share-alike
  are preserved; this constrains any future "marketplace" or closed bundling and
  must be respected in tooling output (ADR-0004 metadata block).
- Two acquisition paths (pbf extract vs Overpass) need supporting in the
  pipeline; Overpass has rate/size limits, so large areas use pbf extracts.
- DEM and OSM are fetched/aligned to the **same bbox and CRS** (ADR-0004) before
  contouring; mismatched extents are a likely early bug to guard against.
- Network access is confined to the **offline pipeline**; the game client ships
  only already-licensed, already-attributed packages.
