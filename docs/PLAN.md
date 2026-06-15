# Krieg — Project Plan

A desktop **Kriegsspiel** (war game) played on real-world terrain sourced from
OpenStreetMap, re-skinned to emulate a 19th-century battlefield. Units are
rendered as "wooden pieces" on a map that behaves like a tabletop board.

> Status: **Phases 0, 1, and Phase 2 / M4 implemented.** The offline map
> pipeline (M0 spike) turns a bbox into a versioned scenario package
> ([`pipeline/`](../pipeline/)), and the **Godot 4 game client**
> ([`client/`](../client/)) loads that package and runs as a tabletop sandbox
> (M1 board renderer + M2 pieces & save/load). On top of that, an **opt-in
> advisory rules engine** ([`client/rules/`](../client/rules/), M4) now suggests
> terrain-aware movement reach and line-of-sight via a pluggable *Strategos
> (1880)* ruleset — advisory only, nothing enforced (ADR-0005). Enforced
> resolution (M5) and double-blind (M6) remain design-only. The ADRs in
> [`docs/adr/`](adr/) define the design; ADRs 0001, 0002, 0003, 0004, 0005,
> 0006, 0007 are now *Accepted*, the rest remain *Proposed*.

---

## 1. Vision

Recreate the feel of a classic 19th-century map-based Kriegsspiel — the kind
played by the Prussian general staff (Reisswitz, 1824) and later adapted in the
United States as *Strategos* (Charles A. L. Totten, 1880) — but on a digital
table, using **real geography** instead of an abstract printed map.

The player chooses a real place, the tool downloads its OpenStreetMap data,
strips away anything anachronistic (motorways, power lines, modern sprawl),
keeps and emphasises what mattered in the 1800s (terrain relief, woods, rivers,
fords, roads, villages, individual buildings), and presents it as a wargaming
board. Wooden-block style pieces are placed and moved on top.

### Guiding principles

1. **Map first, rules later.** The first deliverable is a faithful, beautiful,
   period board you can *play on manually* — a sandbox, not a rules engine.
2. **Adjudicate like an umpire, not a video game.** Kriegsspiel was refereed by
   a human umpire with tables and dice. We mirror that: the system assists, it
   does not (initially) enforce.
3. **Deterministic, inspectable core.** Map processing and any future rules
   resolution must be reproducible from inputs + a seed.
4. **Clean seam for automation.** Structure the game state so that an AI agent
   can later occupy the chair of a player or the umpire without rearchitecting.

### Explicit non-goals (for now)

- Not a real-time strategy game. Turn / pulse based, like the original.
- Not a global map browser. Each game is a single, bounded battlefield (a few km
  across), pre-processed offline — not live tile streaming.
- Not historically exhaustive. We emulate the *aesthetic and scale* of a
  19th-century engagement, not a specific documented order of battle.
- Only the three combat arms of the period — infantry, cavalry, artillery.
  No naval, air, or armoured units (the target range is 1860–1917; see §7).

---

## 2. Scope by phase

### Phase 0 — Map pipeline (offline tooling) — ✅ implemented
Turn a bounding box / place name into a **scenario package**: a self-contained
bundle of period-filtered, projected map features plus generated topography.
No game yet. Validated by visual inspection of rendered output.

Built as the Python CLI in [`pipeline/`](../pipeline/) (`krieg-pipeline build`),
a chain of testable stages `acquire → clip → filter → reproject → contour →
classify → emit` (ADR-0003). The M0 spike runs end to end on the bundled
[`waterloo`](../pipeline/scenarios/waterloo.yaml) scenario.

- [x] Download OSM extract for an area (Overpass; `.osm.pbf` path TBD for large areas).
- [x] Download a DEM for the same area (Copernicus GLO-30, ADR-0002).
- [x] Filter & reclassify features into period categories (declarative ruleset, ADR-0006).
- [x] Project to a local metric CRS so the board is flat and in real metres (ADR-0004).
- [x] Generate contour lines / hillshade from the DEM.
- [x] Emit a versioned `scenario.json` + assets, plus a `preview` quick-look renderer.

### Phase 1 — Tabletop sandbox (the MVP) — ✅ implemented
A desktop application that loads a scenario package and lets one person (or two,
hot-seat) move pieces freely. **No enforced rules.** This is "Tabletop Simulator
for our board."

Built as the Godot 4 client in [`client/`](../client/) (ADR-0001). It loads a
scenario package (the bundled `waterloo` by default) and runs the sandbox.

- [x] Render the board: terrain fills, woods, water, roads, buildings, contours,
  plus a faint hillshade backdrop, in a 19th-century staff-map palette.
- [x] Pan / zoom / measure distance (in metres and in 1:8000 game scale).
- [x] Place, select, move, rotate, stack, label, and remove pieces.
- [x] Piece roster from a unit catalogue (infantry / cavalry / artillery / HQ /
  markers), styled as wooden blocks.
- [x] Save / load a game state (piece positions; a separate file from the board).
- [x] A measuring ruler and a movement-range overlay (purely advisory).

### Phase 2 — Assisted umpire (rules, opt-in) — 🟡 M4 implemented
Layer Kriegsspiel/Strategos mechanics on top as **advisory then enforced**
tools, behind a pluggable rules interface (ADR-0005). Built in
[`client/rules/`](../client/rules/): a renderer-free `Ruleset` interface with a
`Strategos` (1880) implementation, fed by a `TerrainModel` (covering terrain +
road proximity) and an `ElevationField` (contour-interpolated heightfield).

- [x] Movement rates by unit type & terrain (data table, ADR-0007), surfaced as
  a terrain-aware **advisory reach** overlay for the selected piece.
- [x] **Line-of-sight** from terrain + elevation (an advisory LOS probe tool).
- [ ] Turn/pulse structure.
- [ ] Combat resolution tables + dice, with a logged, seeded RNG. *(M5)*
- [ ] Double-blind / fog-of-war mode (two player views + umpire view), echoing
  the original three-room setup. *(M6)*

### Phase 3 — AI agents (research)
Expose the game state behind a stable interface so an automated agent can act as
a player or umpire (ADR-0008). Out of scope to build now; the seam is designed
for now.

---

## 3. Architecture overview

Two cleanly separated halves, joined by a versioned file format:

```text
  ┌──────────────────────────────┐        ┌───────────────────────────────┐
  │  Map Pipeline (offline)      │        │  Game Client (desktop)        │
  │  Python + GDAL/GeoPandas     │        │  Godot 4 (built, ADR-0001)    │
  │                              │        │                               │
  │  OSM extract ─┐              │        │  loads ▼                      │
  │  DEM ─────────┼─► filter ──► │ scenario│  Board renderer              │
  │               │   project ──►│ package │  Piece manager (sandbox)     │
  │               │   contours ─►│  (.json │  Rules engine (Phase 2,      │
  │               │              │ +assets)│    pluggable)                 │
  │               └──────────────┘  ───────►  Save/load game state        │
  └──────────────────────────────┘        └───────────────────────────────┘
                                                     ▲
                                                     │ Phase 3
                                              ┌──────┴───────┐
                                              │  Agent API   │  (ADR-0008)
                                              │  player/umpire│
                                              └──────────────┘
```

- **Map Pipeline** is batch tooling. It runs rarely (once per scenario), can be
  slow, and lives in the Python geospatial ecosystem where the right libraries
  exist (osmnx, geopandas, shapely, rasterio, GDAL).
- **Game Client** is the interactive desktop app. It never touches the network
  or raw OSM; it only consumes finished scenario packages. This keeps it small,
  offline, and deterministic.
- **Scenario package** is the contract between them (ADR-0004). Stable, versioned,
  documented. Either half can be rewritten as long as the format holds.
- **Game state** (piece positions, turn log) is a separate save file, never
  mixed into the scenario package — the board is read-only content, the game is
  mutable.

See [`docs/adr/`](adr/) for the reasoning behind each choice.

---

## 4. The map → board transformation

The heart of Phase 0. Conceptual steps (detail in ADR-0003 / ADR-0006):

1. **Acquire.** Given a place or bbox, fetch OSM features and a DEM tile.
2. **Filter to period.** Drop anachronisms (motorways, railways pre-/post- the
   target year, power lines, modern landuse). Keep & reclassify period features:
   relief, water, woods/forest, fields/heath, roads & tracks (downgraded to
   period road classes), bridges/fords, settlements, and *individual buildings*
   (which were tactically meaningful — strongpoints, farms, churches).
3. **Project.** Reproject from WGS84 to a local metric CRS (UTM zone of the area)
   so 1 unit ≈ 1 metre and the board reads as flat — appropriate for a small
   battlefield.
4. **Topography.** From the DEM, generate contour lines at a chosen interval and
   optionally a hillshade raster, so relief reads at a glance like an old
   staff map.
5. **Stylise.** Tag features with the visual category the renderer will use
   (no rendering here — just classification), and compute a scale bar in
   Kriegsspiel terms.
6. **Emit.** Write `scenario.json` (vector features, in local metres) plus any
   raster assets (hillshade), with metadata: source attribution, CRS, bbox,
   target year, contour interval, generation timestamp & tool version.

---

## 5. Tech stack (proposed)

| Concern              | Choice (proposed)                         | ADR |
|----------------------|-------------------------------------------|-----|
| Game client / engine | Godot 4 (GDScript), 2D, desktop           | 0001 |
| Map data source      | OpenStreetMap (ODbL) + open DEM           | 0002 |
| Pipeline language    | Python (osmnx, geopandas, shapely, GDAL)  | 0003 |
| Board format / CRS   | Versioned JSON in local UTM metres        | 0004 |
| Rules approach       | Manual sandbox → pluggable rules engine   | 0005 |
| Period adaptation    | Declarative feature filter rules          | 0006 |
| Elevation source     | Open DEM (Copernicus GLO-30 / SRTM)       | 0002 |
| AI agent seam        | State + action interface (future)         | 0008 |

These are starting positions, recorded as ADRs so they can be revisited with
context rather than re-argued from scratch.

---

## 6. Roadmap & milestones

- **M0 — Pipeline spike.** ✅ *Done (2026-06-14).* One bbox → a `scenario.json`
  you can open and eyeball as plotted polygons (`krieg-pipeline build … --preview`).
  Proves the data path end to end; validated on the Waterloo bbox.
- **M1 — Board renderer.** ✅ *Done (2026-06-14).* Godot client loads
  `scenario.json` and draws the period board (terrain, water, woods, roads,
  buildings, contours, hillshade) with pan/zoom/measure.
- **M2 — Sandbox.** ✅ *Done (2026-06-14).* Pieces: place/move/rotate/stack/
  label/remove, plus save/load game state. *Phase 1 complete — playable
  manually.*
- **M3 — Pipeline UX.** Choose an area by name/bbox; period filter is
  configurable (target year, road set, building density).
- **M4 — Rules v0 (advisory).** ✅ *Done (2026-06-15).* Pluggable rules engine
  ([`client/rules/`](../client/rules/), ADR-0005) with a *Strategos* ruleset;
  terrain-aware movement-reach overlay and an elevation/cover line-of-sight
  probe — both advisory, no enforcement.
- **M5 — Rules v1 (umpire).** Combat tables, seeded dice, turn structure, log.
- **M6 — Double-blind.** Fog of war, per-player views, umpire view.
- **M7+ — Agents.** Stable agent interface; first scripted/AI umpire or player.

---

## 7. Open questions

Tracked here, with resolutions dated as they land (not blocking the plan):

- **Target period precision.** *Resolved (2026-06-14):* a **configurable target
  year**, with a valid range of **1860–1917**. Only the three 19th-century
  combat arms — **infantry, cavalry, artillery** — are in scope; no naval, air,
  or armoured units. The year drives which roads/railways count as anachronistic
  (ADR-0006). *(See also §1 non-goals.)*
- **Scale.** *Resolved (2026-06-14):* adopt the original **~1:8000** as the
  game scale. The board substrate stays in real metres (ADR-0004); 1:8000 is the
  default play scale and the scale-bar ratio (ADR-0007).
- **Building granularity.** *Resolved (2026-06-14):* **cluster** dense/small
  footprints into period village blocks **where convenient for the game scale**,
  rather than rendering every OSM building; tactically-significant standalone
  buildings (farms, churches, mills) are still kept individually. Implemented as
  a clustering knob in the period filter (ADR-0006).
- **Engine.** *Resolved:* **Godot 4**, compiled to native Linux + Windows
  binaries, no Electron (ADR-0001). Only reopen if browser-playability later
  becomes a goal (Tauri being the fallback). The pipeline/format stay
  engine-agnostic, so this is low-risk.
- **Rules edition.** *Resolved (2026-06-14):* focus on **Strategos (1880)** as
  the first ruleset; the pluggable engine (ADR-0005) keeps the door open to
  similar rulesets (Reisswitz, house variants) in the near future.
