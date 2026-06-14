# ADR-0005: Rules approach — sandbox first, pluggable engine later

- **Status:** Proposed
- **Date:** 2026-06-14
- **Deciders:** project owner

## Context

Historical Kriegsspiel was **umpire-adjudicated**: a referee applied movement
rates, line-of-sight, and combat-resolution tables (with dice) while players
gave orders. Reisswitz's 1824 rules and Totten's *Strategos* (1880) differ in
detail; there is no single canonical ruleset, and "rigid" vs "free"
(umpire-judgement) Kriegsspiel is a long-standing split in the hobby.

If we hard-code one ruleset into the game now, we (a) delay the genuinely useful
first deliverable — a board you can play on — and (b) marry the codebase to one
debatable interpretation.

## Decision

**Phase 1 ships no enforced rules at all.** The game client is a *sandbox*: it
moves pieces, measures distance, and saves state, exactly like a physical table
where the players are their own umpire (PLAN Phase 1).

Rules arrive in **Phase 2 as a pluggable engine** behind a narrow interface,
introduced **advisory before enforced**:

1. *Advisory overlays* first (movement-range rings, LOS shading) that suggest
   but never prevent a move.
2. *Enforced resolution* later (combat tables, seeded dice, turn structure),
   still optional per game.

The rules engine operates on **plain game-state data**, independent of the Godot
renderer (per ADR-0001), so rulesets are testable in isolation and swappable.
A ruleset is a module providing, at minimum: legal-move/range queries, LOS &
visibility, and combat resolution — each pure functions of `(state, action,
seed)`.

## Alternatives considered

- **Implement full Kriegsspiel rules up front.** Rejected — large, contested,
  and blocks the MVP; the map+sandbox is valuable on its own and de-risks the
  rest.
- **Pick exactly one edition (e.g. strict Reisswitz) and bake it in.** Rejected
  — forecloses *Strategos* and house rules; ADR cost of reversal is high.
- **No rules ever (pure sandbox forever).** Rejected as the *ceiling* — but it is
  deliberately the *floor*, and a perfectly valid place to stop if Phase 2 never
  ships.

## Consequences

- Determinism requirement: all randomness goes through a **single seeded RNG**
  with a logged stream, so games are replayable and umpire decisions auditable
  (also needed for ADR-0008 agents).
- The Phase-1 game-state schema must already be rich enough (unit type, facing,
  strength) for Phase-2 rules to attach to it, even though nothing reads those
  fields yet — design the state for the umpire we don't have yet.
- The edition question (PLAN §7) is resolved (2026-06-14): the **first ruleset
  targets *Strategos* (1880)**. The pluggable interface keeps Reisswitz and
  house variants reachable in the near future as additional ruleset modules,
  without re-architecting — the edition is a per-ruleset choice, not a global one.
- Keeping rules engine-agnostic constrains how tightly the client may couple
  selection/animation to game logic.
