# KSoOSM - Kriegspiel over OpenStreetMap

A desktop **Kriegsspiel** played on real-world terrain. Choose a battlefield
anywhere on Earth, and the tool downloads its OpenStreetMap and elevation data,
strips away anything anachronistic, keeps what mattered in the 19th century —
woods, rivers, roads, villages, contour lines — and renders it as a period
staff-map board. Wooden-block pieces are placed and moved on top.

The design follows the original dual-umpire structure: an offline pipeline
prepares the map, and the desktop client runs the game. An opt-in rules engine
advises on movement reach and line of sight without enforcing anything — the
umpire still adjudicates.

> **Status:** Phases 0, 1, and Phase 2 / M4 implemented. See [docs/PLAN.md](docs/PLAN.md).

---

## Repository layout

```
pipeline/   Offline map tooling (Python). Turns a bbox into a scenario package.
client/     Desktop game client (Godot 4). Loads a scenario and runs the game.
docs/
  PLAN.md         Project plan and roadmap.
  adr/            Architecture Decision Records (design reasoning).
```

The two halves are joined by a versioned JSON **scenario package** (ADR-0004).
Either can be replaced independently as long as the format holds.

---

## Quick start

### 1 — Build a scenario (pipeline)

Requires Python 3.11 or 3.12.

```bash
cd pipeline
uv venv --python 3.12 && uv pip install -e ".[dev]"

# Build the bundled Waterloo sample
krieg-pipeline build --scenario scenarios/waterloo.yaml --out out/waterloo

# Or any bbox (min_lon,min_lat,max_lon,max_lat)
krieg-pipeline build --bbox 4.38,50.66,4.43,50.70 --year 1880 --out out/demo
```

Output: `out/<name>/scenario.json` + `assets/hillshade.png`.

### 2 — Run the client (game)

Requires **Godot 4.2+** (standard build, GDScript only).

```bash
godot --path client                           # uses the bundled waterloo scenario
godot --path client -- --scenario=/path/to/scenario.json
```

Or open `client/` as a Godot project and press Play. A file picker appears if
no scenario is found.

A built scenario from step 1 can be copied into `client/scenarios/` to make it
the default.

---

## What's implemented

| Milestone | Description | Status |
|-----------|-------------|--------|
| M0 — Pipeline spike | bbox → `scenario.json` (OSM + DEM, period-filtered, metric) | Done |
| M1 — Board renderer | Period staff-map with terrain, water, woods, roads, contours | Done |
| M2 — Sandbox | Place/move/rotate/stack/label pieces; save/load game state | Done |
| M4 — Advisory rules | Pluggable rules engine; terrain-aware reach + LOS overlay | Done |
| M3 — Pipeline UX | Interactive area picker, period-filter config | Planned |
| M5 — Umpire rules | Combat tables, seeded dice, turn structure, log | Planned |
| M6 — Double-blind | Fog of war, per-player views, umpire view | Planned |
| M7+ — Agents | AI player or umpire via stable state/action interface | Planned |

---

## Design principles

1. **Map first, rules later.** The first deliverable is a faithful, beautiful
   period board you can play on manually. The sandbox enforces nothing.
2. **Adjudicate like an umpire.** Rules assist; they don't (yet) enforce.
   The M4 advisory engine suggests movement reach and LOS but never blocks a move.
3. **Deterministic core.** Pipeline and future combat resolution are
   reproducible from inputs + a seed.
4. **Clean agent seam.** Game state is structured so an AI agent can later
   occupy the player or umpire chair without rearchitecting (ADR-0008).

---

## Documentation

- [docs/PLAN.md](docs/PLAN.md) — full project plan, roadmap, and open questions
- [client/README.md](client/README.md) — client controls, architecture, coordinates
- [pipeline/README.md](pipeline/README.md) — pipeline stages and period ruleset
- [docs/adr/](docs/adr/) — Architecture Decision Records (all significant design choices)

---

## Data sources and licensing

- Map features: **OpenStreetMap** (© OpenStreetMap contributors, ODbL).
- Elevation: **Copernicus GLO-30 DEM** (© DLR/ESA, open licence).
- No proprietary data. See [ADR-0002](docs/adr/0002-data-sources-licensing.md).
