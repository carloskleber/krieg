"""Krieg map pipeline — Phase 0 offline tooling (see ../../docs/PLAN.md §2)."""

__version__ = "0.2.0"

# The scenario package format version this generator emits (ADR-0004). The game
# client checks this and refuses unknown majors. 0.2 adds the optional
# `heightmap` asset for the 3D board view (ADR-0009); it is additive, so 0.1
# consumers keep working and 0.2 consumers treat the asset as optional.
SCENARIO_FORMAT_VERSION = "0.2"
