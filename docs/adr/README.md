# Architecture Decision Records

This directory records the significant design decisions for **Krieg**. Each ADR
captures one decision: its context, the choice, the alternatives weighed, and
the consequences. ADRs are immutable once *Accepted* — to change a decision,
write a new ADR that supersedes the old one.

Format: lightweight [MADR](https://adr.github.io/madr/)-style. Template:
[`0000-template.md`](0000-template.md).

| #    | Title                                          | Status   |
|------|------------------------------------------------|----------|
| 0001 | Game client engine: Godot 4                     | Accepted |
| 0002 | Map & elevation data sources and licensing      | Accepted |
| 0003 | Map ingestion pipeline in Python                | Accepted |
| 0004 | Scenario package format & coordinate system     | Accepted |
| 0005 | Rules approach: sandbox first, pluggable engine | Accepted |
| 0006 | 19th-century adaptation as declarative filters  | Accepted |
| 0007 | Game scale & movement model                     | Accepted |
| 0008 | AI agent integration seam (future)              | Proposed |

ADRs 0002/0003/0004/0006 were **Accepted** when the Phase 0 pipeline
([`../../pipeline/`](../../pipeline/)) implemented them (2026-06-14); **0001**
when the Phase 1 game client ([`../../client/`](../../client/)) realised it
(2026-06-14); **0005/0007** when Phase 2 / M4 brought up the advisory rules
engine ([`../../client/rules/`](../../client/rules/)) (2026-06-15). The rest
remain **Proposed** — they become *Accepted* when their milestone begins.
