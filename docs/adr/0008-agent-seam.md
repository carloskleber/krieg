# ADR-0008: AI agent integration seam (future)

- **Status:** Proposed
- **Date:** 2026-06-14
- **Deciders:** project owner

## Context

A stated future phase (PLAN Phase 3) is to let **AI agents** play a part —
occupying the chair of a player or, intriguingly, the **umpire**. We are not
building this now. But the cost of *designing for it now* is near zero, and the
cost of retrofitting it later into an engine-coupled codebase is high. This ADR
records the **seam**, not an implementation.

The original three-room, double-blind Kriegsspiel maps unusually well onto an
agent setup: each player sees only their own information; the umpire sees all
and adjudicates. An agent can plausibly sit in any of those three seats.

## Decision

Reserve a clean boundary now, realise it later:

- **Game state and rules are engine-independent plain data** (ADR-0001, ADR-0005)
  and all randomness is **seeded and logged** (ADR-0005). This makes the game
  programmatically drivable and replayable — the prerequisite for any agent.
- Define (later) an **agent interface** with two roles:
  - **Player agent:** given a *role-filtered* view of state (fog of war from a
    future double-blind mode), returns **orders/actions**. It must only receive
    what its seat can legally see.
  - **Umpire agent:** given full state + a proposed action, returns an
    **adjudication** (legality, resolution outcome) — the automatable form of
    the human referee.
- The interface is **transport-agnostic** (in-process function calls; or a
  local protocol / MCP-style tool surface for an LLM-backed agent). No transport
  is chosen now.
- LLM-backed agents, if used, are an Anthropic-Claude-first integration
  consistent with this project's environment, but the seam stays
  model-agnostic.

## Alternatives considered

- **Design nothing now, retrofit later.** Rejected — the specific risk is rules
  logic entangling with the renderer or with un-seeded randomness, which would
  make agents very expensive to add. The mitigation (state-as-data, seeded RNG)
  is cheap and already required by ADR-0004/0005.
- **Build the agent API now.** Rejected — premature; no rules engine yet to act
  on, and the interface shape depends on the double-blind model (M6).
- **Hard-wire a single LLM/provider into the core.** Rejected — keep the core
  game agnostic; provider choice belongs in an adapter behind the interface.

## Consequences

- Three constraints become **binding on earlier phases**: (1) state is plain,
  serialisable data; (2) one seeded, logged RNG; (3) rules are pure functions of
  state — all already implied by ADR-0004/0005, now justified additionally by
  agents.
- Fog-of-war / role-filtered views (M6) are a **prerequisite** for a fair player
  agent; until then only full-information or umpire agents are feasible.
- This ADR will be **superseded** by a concrete "agent interface" ADR when
  Phase 3 work actually begins; today it only forbids us from painting ourselves
  into a corner.
