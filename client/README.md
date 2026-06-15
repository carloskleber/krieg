# Krieg — game client (Phase 1: tabletop sandbox)

The interactive half of Krieg: a **Godot 4** desktop app (ADR-0001) that loads a
scenario package produced by the [`pipeline/`](../pipeline/) (ADR-0004) and lets
you play on it like a tabletop — place and move wooden-block pieces, measure
distances, save and reload. **No rules are enforced** (ADR-0005): this is
"Tabletop Simulator for our board", a human-umpired sandbox.

> Status: **Phase 1 implemented** (M1 board renderer + M2 sandbox). Compiles and
> runs clean under **Godot 4.6** (`--headless` smoke test: all 14 classes
> register, scenario loads, board draws with no errors). Interactive
> input/visuals still want a windowed pass on your machine.

## Requirements

- **Godot 4.2+** (standard build, GDScript only — no C#, no GDExtension).
- A scenario package. One is bundled: [`scenarios/waterloo/`](scenarios/waterloo/)
  (copied from `pipeline/out/waterloo`).

## Running

From the editor: open this folder (`client/`) as a Godot project and press Play.

From the command line:

```bash
godot --path client                          # uses the bundled waterloo scenario
godot --path client -- --scenario=/abs/path/to/scenario.json
```

If no scenario is found, the app opens a file picker for a `scenario.json`.

## Controls

| Action | Input |
|--------|-------|
| Pan | drag with **right** or **middle** mouse |
| Zoom | mouse **wheel** (anchored at the cursor) |
| Frame whole board | **Frame** button |
| Place a piece | **Place** tool, pick Unit + Side, then **left-click** |
| Select / move | **Select** tool, **left-click** a piece, drag to move |
| Cycle buried pieces | left-click the same overlapping spot repeatedly |
| Rotate (facing) | **Q** / **E** (hold **Shift** for fine) |
| Stack count ± | **+** / **-** |
| Cycle side | **F** |
| Edit label | **L** |
| Remove | **Delete** or **X** |
| Nudge | **arrow keys** |
| Measure | **Measure** tool, left-drag (shows metres and 1:8000 cm) |
| Movement-range ring | set **Range m** > 0 (advisory only, follows selection) |
| Save / Load / Clear | toolbar buttons (`*.krieg.json`) |

## Architecture

Rendering is kept out of game/rules logic (ADR-0001) so Phase 2 rules and the
Phase 3 agent seam can attach to plain data, not the renderer.

```text
main/Main.gd          orchestration: load scenario → build board, camera, pieces, HUD
scenario/Scenario.gd  parse scenario.json (ADR-0004) into typed, read-only data
board/
  BoardView.gd        composes hillshade backdrop + vector terrain in world space
  TerrainRenderer.gd  draws features by category (_draw), built once from metres
  FeatureStyles.gd    period staff-map palette + per-category draw params
pieces/
  UnitCatalogue.gd    roster: infantry/cavalry/artillery/HQ/marker × sides
  Piece.gd            one wooden-block token (visual + data + persistence)
  PieceLayer.gd       place/select/drag/rotate/stack/label/remove + range ring
game/GameState.gd     save/load mutable play state (separate file, ADR-0004)
tools/
  Geo.gd              metres ↔ Godot world (1 unit = 1 m, north up)
  CameraController.gd pan/zoom
  Ruler.gd            measuring tape (metres + 1:8000)
ui/
  Hud.gd              toolbar, info/help, file dialogs, label editor
  ScaleBar.gd         zoom-aware scale bar with 1:8000 annotation
```

### Coordinates

The package stores geometry in **local metres**, origin at the bbox SW corner,
**+y north** (ADR-0004). Godot 2D is **+y down**, so `Geo` maps metre `(x, y)` →
world `(x, -y)`. No node is ever flipped (which would mirror piece labels);
1 world unit = 1 metre, so distances and the scale bar are direct.

### Save files

A save references its scenario by `name` + `config_hash` and stores only piece
state (positions in metres, facing, side, label, stack). Loading a save made for
a different board warns but does not block — the board is read-only content, the
save is the mutable game (ADR-0004).

## Known limitations / next steps

- Polygon holes are dropped on fill (rare in period data); donut lakes would fill solid.
- Hillshade is a faint multiply-less backdrop (`self_modulate` alpha), not true multiply blend.
- No export presets committed yet; CI cross-export to Linux + Windows (ADR-0001) is a later task.
- Rules (movement rates, LOS, combat) are Phase 2 — the range ring here is purely advisory.
