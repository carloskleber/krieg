# ADR-0004: Scenario package format & coordinate system

- **Status:** Accepted (realised by the Phase 0 pipeline, 2026-06-14)
- **Date:** 2026-06-14
- **Deciders:** project owner

## Context

The pipeline (ADR-0003) and the game client (ADR-0001) are separate programs in
different languages. Their only contract is the **scenario package**: the baked,
read-only board. Getting this format right matters more than either side's
internals, because it is the stable interface and the unit of redistribution
(ADR-0002). Two questions: *what format* and *what coordinate system*.

A small battlefield is only a few km across. Using raw lat/long (degrees) would
make the board distort and complicate distance/movement math. We want metres.

## Decision

### Coordinate system
Reproject all geometry to a **local metric CRS** — the **UTM zone** covering the
scenario's centroid (or a custom transverse-Mercator centred on the bbox for
areas straddling a zone boundary). In the package, coordinates are **metres**
with a local origin at the bbox's south-west corner, so the board is effectively
a flat plane where 1 unit = 1 metre. The original CRS, UTM zone, and the
lat/long bbox are recorded in metadata for traceability.

### Format
A **versioned package**: a directory (or zip) containing

- `scenario.json` — manifest + **vector features** as GeoJSON-like geometry in
  local metres, each tagged with a **period category** (ADR-0006): `relief`
  (contour lines, with elevation), `water`, `wood`, `field`, `road` (with period
  class), `bridge`/`ford`, `settlement`, `building`.
- `assets/` — optional rasters (hillshade PNG) and styling hints.
- A required **metadata block**: `format_version`, source attribution & licences
  (OSM/DEM), CRS + bbox + origin, target year, contour interval, generator
  version, config hash, timestamp.

GeoJSON-style geometry (just rebased to metres) keeps it inspectable, trivially
parseable in both Python and Godot, and debuggable with standard GIS tools.

### Game state is separate
The scenario package is **read-only content**. Piece positions, turn log, and
fog-of-war state live in a **separate save file** that references a scenario by
id + version. The board and the game never mix in one file.

## Alternatives considered

- **Keep WGS84 lat/long in the package, project in the client.** Rejected —
  pushes projection math and distortion handling into the game; metres-at-author-
  time is simpler and deterministic.
- **Web Mercator (EPSG:3857).** Rejected — area/distance distortion away from the
  equator; UTM/local TM is correct for a small region.
- **Pre-rendered raster tiles only.** Rejected — loses vector semantics needed
  for selection, LOS, and rules; a hillshade raster is kept only as a *backdrop*.
- **Engine-native binary (e.g. Godot resource).** Rejected — couples the format
  to ADR-0001 and breaks tool-agnostic inspection; JSON+assets stays portable.
- **One file holding board + pieces.** Rejected — conflates immutable content
  with mutable play state; complicates sharing scenarios and versioning saves.

## Consequences

- `format_version` is sacred: the client checks it and refuses unknown majors.
  Format changes are themselves ADR-worthy.
- Large/dense areas may produce big JSON; if it hurts, we add an optional binary
  geometry sidecar *without* changing the logical schema (revisit then).
- Because everything is in metres from a known origin, distance measurement,
  scale bars, and future movement ranges (ADR-0007) are straightforward.
- Either side can be rewritten (e.g. a web client per ADR-0001) as long as it
  honours this format.
