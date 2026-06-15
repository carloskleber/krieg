# ADR-0009: Optional 3D board view (relief sand-table)

- **Status:** Proposed
- **Date:** 2026-06-15
- **Deciders:** project owner

## Context

The Phase 1 client (ADR-0001) renders the board as a flat 2D staff map: vector
features painted in a canvas (`TerrainRenderer`), pieces drawn as flat wooden
rectangles (`Piece`), all under a `Camera2D` in metre-based world space (ADR-0004,
`Geo`). Relief is conveyed only indirectly — contour lines (`relief` features)
and a faint hillshade backdrop.

We want a **3D option**: a relief "sand table" where the terrain has real
elevation and the unit tokens have volume, so ridgelines, dead ground, and the
lie of the land read at a glance — the way a physical Kriegsspiel terrain model
or a relief map does. This must not regress the existing 2D board, which is fast,
legible, and the way the game is actually played most of the time.

Forces:

- The client is **2D throughout** (`Node2D`, `Camera2D`, `_draw`). A 3D view
  introduces a second rendering world, camera, and input path.
- Elevation today exists only as **contour lines** (sparse) and a hillshade PNG.
  A smooth terrain mesh wants a real heightfield.
- At the game scale (~3.6 km board, ~80 m of relief) the terrain is **almost
  geometrically flat** — true-scale relief is imperceptible.
- The scenario package is a versioned contract (ADR-0004); changing it costs a
  format bump and a rebuild, and must stay backward-compatible.
- Effort budget: this is a hobby/research project. Reuse beats rewrite.

## Decision

Add 3D as a **switchable view alongside** the 2D board, not a replacement. A
`ViewManager` toggles between a 2D subtree (unchanged) and a new 3D subtree in a
single Godot viewport, hiding the inactive set. The **shared source of truth is
the game state** — the metres-based piece array (ADR-0004, `GameState`) — so
switching views serializes from the active piece layer and rebuilds the other;
positions, facing, stacking, labels, and selection are preserved. Saves remain
cross-compatible between views (ground height is derived, never stored).

Three sub-decisions:

1. **Elevation source: a pipeline-emitted heightmap.** The contour stage already
   loads the DEM; it additionally writes a 16-bit grayscale `heightmap.png` asset
   plus its metric bounds and elevation range. The client builds the terrain mesh
   by displacing a grid with this heightmap. Format version bumps `0.1 → 0.2`;
   the asset is **optional**, so 0.1 packages still load (2D as before; 3D falls
   back to the contour-interpolated `ElevationField` already used by the rules
   engine, ADR-0005).

2. **Terrain skin by texture-baking the 2D renderer.** Rather than re-draping every
   vector feature as conformal 3D geometry, the existing `TerrainRenderer` is
   rendered once into a `SubViewport` and used as the terrain mesh's albedo. All
   of `FeatureStyles`/`TerrainRenderer` is reused unchanged; the staff-map styling
   simply becomes the skin over the relief.

3. **Configurable vertical exaggeration (default ~3×).** Elevation is multiplied by
   an adjustable factor, exposed in the HUD, so relief reads like a relief model.
   True 1:1 scale would be barely perceptible at this board size.

Coordinate contract (`Geo3D`): scenario metres `(x east, y north)` + elevation map
to Godot `Vector3(x, elev * exag, -y)` — Godot is y-up; north → −Z so a top-down
3D camera reads north-up like the 2D board (consistent with `Geo`, ADR-0004).

## Alternatives considered

- **Replace the 2D board with 3D.** One renderer to maintain, but loses the fast,
  crisp flat map and forces every existing 2D tool (ruler, rules overlays, HUD)
  through a 3D rewrite at once. Rejected: the toggle keeps 2D as the proven
  baseline and lets 3D grow incrementally.
- **Derive the heightfield from contours in-client (no pipeline change).** Avoids
  the format bump, but contours are sparse (10 m interval) so the mesh terraces
  between them. Kept only as the **fallback** for pre-0.2 packages.
- **Drape each vector feature as 3D meshes** (tessellated polygons/roads conformed
  to terrain). Higher geometric fidelity, far more code, marginal visual gain over
  a baked skin at this scale. Rejected for the skin-bake; building *extrusion*
  (footprints → prisms) is kept as optional polish where volume genuinely helps.
- **8-bit heightmap.** Simpler, but ~80 m over 256 levels visibly terraces. Chose
  16-bit.

## Consequences

- **Easier:** relief, dead ground, and line-of-sight become literally visible; the
  rules `ElevationField`/LOS gain a faithful 3D depiction. The 2D board is
  untouched and remains the default.
- **Harder / new commitments:** a second camera and input path (3D picking via
  raycast) that must stay at feature parity with the 2D piece layer — mitigated by
  factoring shared piece actions/keybindings into a common base. Mixing 2D canvas
  and 3D in one viewport requires hiding the inactive subtree (canvas always draws
  over 3D).
- **Format:** `scenario.json` goes to `0.2` with an optional `heightmap` asset;
  the client must keep loading 0.1. Bundled scenarios are rebuilt.
- **To revisit:** terrain mesh LOD/perf if larger boards arrive; whether building
  extrusion and conformal roads are worth promoting from optional polish.
</content>
</invoke>
