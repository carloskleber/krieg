# Architecture Decision Records

This directory records the significant design decisions for **Krieg**. Each ADR
captures one decision: its context, the choice, the alternatives weighed, and
the consequences. ADRs are immutable once *Accepted* — to change a decision,
write a new ADR that supersedes the old one.

Format: lightweight [MADR](https://adr.github.io/madr/)-style. Template:
[`0000-template.md`](0000-template.md).

| #    | Title                                          | Status   |
|------|------------------------------------------------|----------|
| 0001 | Game client engine: Godot 4                     | Proposed |
| 0002 | Map & elevation data sources and licensing      | Proposed |
| 0003 | Map ingestion pipeline in Python                | Proposed |
| 0004 | Scenario package format & coordinate system     | Proposed |
| 0005 | Rules approach: sandbox first, pluggable engine | Proposed |
| 0006 | 19th-century adaptation as declarative filters  | Proposed |
| 0007 | Game scale & movement model                     | Proposed |
| 0008 | AI agent integration seam (future)              | Proposed |

All ADRs are currently **Proposed** — this is a planning snapshot. They become
*Accepted* when implementation on the corresponding milestone begins.
