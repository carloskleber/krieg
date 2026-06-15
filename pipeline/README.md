# Krieg map pipeline (Phase 0)

Offline tooling that turns a bounding box into a **scenario package** — a
self-contained, period-filtered, metric-projected board for the Krieg game
client to consume. See [`../docs/PLAN.md`](../docs/PLAN.md) §2 (Phase 0) and the
ADRs in [`../docs/adr/`](../docs/adr/) for the design.

This half never runs inside the game; it is a batch build step (ADR-0003).

## Install

Requires Python 3.11 or 3.12 and a C toolchain for the geospatial wheels.

```bash
cd pipeline
uv venv --python 3.12
uv pip install -e ".[dev]"
```

## Run

The pipeline is a deterministic CLI: `bbox + config → scenario package`.

```bash
# M0 spike — a hard-coded sample battlefield (Waterloo) → out/waterloo/
krieg-pipeline build --scenario scenarios/waterloo.yaml --out out/waterloo

# or pass a bbox directly (min_lon,min_lat,max_lon,max_lat)
krieg-pipeline build --bbox 4.38,50.66,4.43,50.70 --year 1880 --out out/demo
```

### Pick an area graphically

Rather than hand-writing a bbox, launch the **map selector** — a small local web
tool that opens an OpenStreetMap slippy map in your browser:

```bash
krieg-pipeline select        # opens http://127.0.0.1:8682/
```

Draw the battlefield rectangle with the ▭ tool, set the period knobs (target
year, contour interval, building clustering) and **Save scenario** — it writes a
validated `scenarios/<name>.yaml` and prints the exact `build` command to run.
Existing scenarios are drawn on the map and reloadable into the form.

This is the seed of the future **map editor** (PLAN §8): today it owns only the
*select a location* step, but the Leaflet draw/edit surface is the foundation for
later per-feature editing. The page needs internet for OSM tiles; the native
half writes scenarios through the same `ScenarioConfig` the CLI uses, so it can
never emit a package the pipeline would reject. Lives in
[`src/krieg_pipeline/mapeditor/`](src/krieg_pipeline/mapeditor/).

The output directory is a scenario package (ADR-0004):

```
out/waterloo/
  scenario.json     # manifest + vector features, in local metres
  assets/
    hillshade.png   # optional relief backdrop
```

## Stages

The build is a chain of testable stages (ADR-0003), matching PLAN §4:

```
acquire → clip → filter → reproject → contour → classify → emit
```

- **acquire** — fetch OSM features (Overpass) and a DEM tile (Copernicus GLO-30).
- **clip** — restrict everything to the requested bbox.
- **filter** — apply the declarative period ruleset (ADR-0006): drop
  anachronisms, demote roads to period classes, keep & categorise terrain.
- **reproject** — WGS84 → local UTM metres, origin at the bbox SW corner
  (ADR-0004).
- **contour** — derive contour lines (and a hillshade) from the DEM.
- **classify** — tag each feature with its board category (ADR-0004).
- **emit** — write `scenario.json` + assets with the full metadata block.

## Period ruleset

The 19th-century adaptation lives as data, not code (ADR-0006):
[`src/krieg_pipeline/rules/default.yaml`](src/krieg_pipeline/rules/default.yaml).
Edit it (or override per scenario) to change the period look without touching
the pipeline.
