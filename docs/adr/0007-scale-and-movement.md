# ADR-0007: Game scale & movement model

- **Status:** Proposed
- **Date:** 2026-06-14
- **Deciders:** project owner

## Context

A Kriegsspiel ties the map to play through **scale** (ground distance per board
distance) and **time/movement** (how far a unit moves per turn). Reisswitz's
apparatus used roughly **1:8000** with special scaled rulers; *Strategos* (1880)
defines its own scales and turn lengths. Because ADR-0004 stores the board in
**real metres**, we have exact ground truth and only need to fix the *play*
parameters layered on top — and those parameters are also what future rules
(ADR-0005) and agents (ADR-0008) consume.

This resolves the PLAN §7 "scale" open question (2026-06-14).

## Decision

- **Adopt the original ~1:8000 as the game scale** (PLAN §7). It is the default
  play scale and the ratio shown on the scale bar.
- **Ground truth is metres** (ADR-0004); the board is not pre-scaled to a paper
  ratio. A configurable **display scale** (metres-per-pixel at zoom 1) and a
  **scale bar** shown in both metres and the **1:8000** Kriegsspiel ratio
  translate for the player — so the metric substrate and the 1:8000 play scale
  coexist.
- **Target period is a configurable year in 1860–1917**, with only three combat
  arms (infantry / cavalry / artillery). Movement-rate tables are keyed by these
  `unit_type`s (PLAN §7, ADR-0006).
- **Movement and time are a small data table**, not hard-coded: per
  `unit_type × terrain_category`, a rate in **metres per turn**, with a defined
  turn length (default reference ~2 minutes/turn, per the original "move"
  cadence — tunable). Terrain categories come straight from ADR-0004/0006
  (road faster, wood/field slower, water/relief impassable or costed).
- These live in the **ruleset** (ADR-0005), so different editions/house rules
  carry different scales and rates without touching the engine.

Phase 1 uses only the *display scale + scale bar + advisory ruler*; the movement
table is consumed first as **advisory range rings** (M4) and only later as
enforcement (M5).

## Alternatives considered

- **Adopt original 1:8000 rigidly, including a *pre-scaled* board.** Rejected:
  we adopt 1:8000 as the **play scale** (the decision), but keep metres as the
  stored substrate (ADR-0004) so we aren't locked to paper-era tooling and can
  still measure in real ground distance.
- **Pick our own metres-per-pixel scale instead of 1:8000.** Rejected — 1:8000
  is the period-authentic choice the project is emulating; a bespoke scale would
  trade authenticity for no real gain.
- **Hex/square grid overlay with movement points.** Rejected for the default —
  it abstracts the terrain the whole project exists to show; a free-movement,
  measured model is truer to map Kriegsspiel. (An optional grid overlay could be
  a later ruleset variant.)
- **Hard-code rates in the engine.** Rejected — couples play-balance to code and
  to one edition; the data-table approach mirrors ADR-0005/0006.

## Consequences

- Distance/scale code is trivial because the board is already metric.
- The turn-length and rate defaults are **guesses to be tuned by playtesting**;
  storing them as ruleset data makes tuning a config edit, not a code change.
- Free movement (no grid) means LOS and ranges (ADR-0005) work in continuous
  space — more realistic, slightly more math; acceptable and aligned with the
  measured-ruler heritage.
- A future grid variant or a strict-1:8000 "purist" ruleset are both reachable
  without contradicting this ADR.
