# ADR-0006: 19th-century adaptation as declarative filters

- **Status:** Proposed
- **Date:** 2026-06-14
- **Deciders:** project owner

## Context

The defining feature of Krieg is that a *modern* OSM map is transformed to read
like a *19th-century* battlefield. Motorways, railways, power lines, industrial
estates, and modern suburban sprawl must go; relief, woods, water, fields,
country roads, villages, and tactically-significant buildings (farms, churches,
mills as strongpoints) must remain and be emphasised. This transformation is
opinionated and will be tuned often — it must not be buried in code.

OSM tagging is messy and inconsistent worldwide, so the rules also need to be
forgiving and overridable per scenario.

## Decision

Express the adaptation as **declarative filter/reclassification rules** —
configuration data consumed by the pipeline (ADR-0003), not imperative code.
Conceptually a ruleset mapping OSM tags → action:

- **Drop** (anachronistic): `highway=motorway|trunk`, `railway=*` (unless target
  year permits), `power=*`, modern `landuse=industrial|retail|garages`, etc.
- **Demote/keep** (period roads): `highway=primary|secondary|tertiary|
  unclassified|track` → reclassified into a small set of period road classes
  (chaussée / country road / track / path).
- **Keep & categorise** (period terrain): water, wood/forest, scrub/heath,
  farmland/meadow → board categories (ADR-0004).
- **Keep & emphasise** (tactical points): individual `building=*`, `bridge`,
  `ford`, named hamlets/villages, churches, walls/hedgerows where tagged.
- **Synthesise**: contour lines & hillshade from the DEM (ADR-0002), since OSM
  has no native relief.

Rules are **parameterised by target year** — a configurable year in the valid
range **1860–1917** (PLAN §7) — and **overridable per scenario**, so authors can
hand-correct (e.g. force-keep a historic road). Within that range the chosen
year decides borderline anachronisms (notably which railways already existed).

**Buildings** (PLAN §7): standalone tactically-significant buildings (farms,
churches, mills) are kept individually; dense/small footprints are **clustered
into period village blocks where convenient for the game scale** (1:8000,
ADR-0007), avoiding a 21st-century street grid. The clustering threshold is a
ruleset knob, off-able per scenario.

## Alternatives considered

- **Imperative filtering in pipeline code.** Rejected — every aesthetic tweak
  becomes a code change; rules are exactly the kind of thing that should be data
  (testable, diffable, shareable).
- **Manual GIS editing per scenario (QGIS by hand).** Rejected as the default —
  not reproducible, not scalable; but kept as an *escape hatch* via per-scenario
  overrides.
- **ML/heuristic "make it look old" image filter on rendered tiles.** Rejected —
  loses vector semantics needed for rules/LOS and is non-deterministic.
- **Ignore the problem (use modern map as-is).** Rejected — defeats the core
  concept; the modern road grid is exactly what breaks the illusion.

## Consequences

- A documented **default ruleset** ships with the tool; its choices (what counts
  as anachronistic) are explicit and reviewable, and tied to ADR-0007's period.
- Worldwide OSM tag inconsistency means the ruleset needs sensible fallbacks and
  a "log unclassified tags" mode so authors can spot gaps.
- The building-density question (PLAN §7) is resolved here: a **clustering**
  rule collapses dense modern blocks into period-village footprints when it
  suits the 1:8000 scale, while standalone strongpoints stay individual — a
  tunable knob, disable-able per scenario.
- Because period adaptation is config, the same OSM extract can yield different
  eras by swapping rulesets — a nice property for future scope.
