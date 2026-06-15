# ADR-0001: Game client engine — Godot 4

- **Status:** Accepted (realised by the Phase 1 client in [`client/`](../../client/), 2026-06-14)
- **Date:** 2026-06-14
- **Deciders:** project owner

## Context

The interactive half of Krieg is a **desktop game** with a "tabletop" feel:
a large 2D board you pan/zoom, on top of which physical-looking "wooden piece"
tokens are dragged, rotated, and stacked. The end product is a **compiled,
multi-platform native desktop binary** — **Linux is the primary target,
Windows a required secondary**, macOS a nice-to-have. It loads pre-baked
scenario packages (ADR-0004) and does no networking or GIS processing of its own.

Requirements that drive the choice:

- Strong, performant **2D rendering** of many vector polygons (terrain, woods,
  buildings) plus sprites for pieces.
- Good **input handling** for direct manipulation (drag/rotate/select/measure).
- **Compiled, self-contained native binaries** for Linux and Windows with **no
  bundled browser/runtime**. The project owner explicitly rejects an
  Electron-style web-app-in-a-window approach.
- Free / open-source, no per-seat licensing — this is a hobby/research project.
- A scene/node model that keeps the future rules engine (ADR-0005) and agent
  seam (ADR-0008) cleanly separable from rendering.

## Decision

Build the game client in **Godot 4.x** using GDScript (dropping to C# or GDExtension
only if a hotspot demands it). Godot's 2D pipeline, built-in `Camera2D`,
`Polygon2D`/custom `_draw()`, and resource/scene system fit a map board well;
its export templates produce **self-contained native binaries** (a single
executable + pck, no separate runtime to install) for **Linux and Windows**
(and macOS), satisfying the "compiled, no Electron" constraint; the engine is
MIT-licensed.

Packaging target: a Linux build (plain binary, plus optionally Flatpak/AppImage
later) is the development and primary release artifact; a Windows `.exe` export
is produced from the same project with no code changes. Cross-export is done
from the Linux dev machine via Godot's export templates, so no Windows toolchain
is needed to ship Windows.

## Alternatives considered

- **Electron (web app in a bundled Chromium).** **Rejected outright** — explicit
  project-owner preference against it, and it contradicts the "compiled native,
  no bundled runtime" requirement: large binaries, a shipped browser, and a
  web-app rather than a desktop-game feel.
- **Web stack compiled natively via Tauri (TypeScript + MapLibre/deck.gl/PixiJS
  in a Tauri shell).** *Pros:* best-in-class map rendering, huge GIS-web
  ecosystem, small native binaries (uses the OS webview, not a bundled
  Chromium), easy to later put online. *Cons:* still a web app at heart, so it's
  more naturally a slippy-map than a wooden-piece board; adds a Rust/JS split;
  relies on each OS's webview, which is more variable than a self-rendered game.
  **Strongest alternative** — and the one to choose *if* browser-playability
  later becomes a goal. The pipeline output is engine-agnostic, so this stays
  open without blocking us.
- **Unity.** *Pros:* mature, capable. *Cons:* licensing/telemetry friction,
  heavier than needed for 2D, larger toolchain. Overkill here.
- **Native (C++/Qt or Rust/egui/bevy).** *Pros:* full control; Bevy is a
  genuine 2D option. *Cons:* far more boilerplate for UI, input, and packaging;
  slower path to a playable sandbox. Bevy is the one to reconsider if we outgrow
  Godot.
- **Tabletop Simulator (mod).** *Pros:* fastest path to "pieces on a board."
  *Cons:* requires owning TTS, Lua-only, can't ship standalone, no clean agent
  seam. Rejected as a product, but useful as a paper prototype reference.

## Consequences

- The game client and the map pipeline are in **different languages** (GDScript
  vs Python). This is acceptable *because* they only communicate through the
  versioned scenario file (ADR-0004), never via shared code.
- We commit to keeping rendering logic out of game/rules logic so that ADR-0005
  and ADR-0008 are not coupled to Godot. Rules + state should be plain data
  structures testable without the engine.
- If a browser version becomes a goal, the engine decision — but not the
  pipeline or the file format — must be revisited (Tauri being the fallback).
- **CI builds two artifacts** from one project: a Linux binary and a Windows
  `.exe`, both cross-exported from Linux. Windows is a release target from the
  start, not an afterthought, so platform-specific path/input assumptions are
  avoided in the client code.
