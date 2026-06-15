"""Declarative period ruleset loader & matcher (ADR-0006).

The ruleset is the heart of the 19th-century adaptation, kept as data so the
"period look" is tunable without code changes. This module just *interprets* it.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from importlib import resources
from pathlib import Path
from typing import Any

import yaml

# Board categories the renderer understands (ADR-0004).
CATEGORIES = {
    "relief",
    "water",
    "wood",
    "field",
    "road",
    "bridge",
    "ford",
    "settlement",
    "building",
}


@dataclass(frozen=True)
class Rule:
    name: str
    when: dict[str, Any]
    action: str  # "drop" | "keep"
    category: str | None = None
    props: dict[str, Any] = field(default_factory=dict)
    years: tuple[int, int] | None = None

    def active_for(self, year: int) -> bool:
        if self.years is None:
            return True
        lo, hi = self.years
        return lo <= year <= hi

    def matches(self, tags: dict[str, Any]) -> bool:
        for key, want in self.when.items():
            have = tags.get(key)
            if have is None:
                return False
            if want == "*":
                continue
            if isinstance(want, (list, tuple)):
                if have not in want:
                    return False
            elif have != want:
                return False
        return True


# Keys the rules dispatch on — only attach these to props (everything else is
# OSM cruft we don't want in the package).
_PROP_KEYS = ("road_class", "water_class", "building_role")


@dataclass
class Ruleset:
    version: int
    fetch: list[str]
    rules: list[Rule]

    @classmethod
    def load(cls, path: Path | None) -> "Ruleset":
        if path is None:
            text = (
                resources.files("krieg_pipeline.rules")
                .joinpath("default.yaml")
                .read_text()
            )
        else:
            text = Path(path).read_text()
        data = yaml.safe_load(text)
        rules: list[Rule] = []
        for raw in data["rules"]:
            props = {k: raw[k] for k in _PROP_KEYS if k in raw}
            years = tuple(raw["years"]) if "years" in raw else None
            cat = raw.get("category")
            if cat is not None and cat not in CATEGORIES:
                raise ValueError(
                    f"rule {raw['name']!r}: unknown category {cat!r} "
                    f"(allowed: {sorted(CATEGORIES)})"
                )
            rules.append(
                Rule(
                    name=raw["name"],
                    when=raw["when"],
                    action=raw["action"],
                    category=cat,
                    props=props,
                    years=years,  # type: ignore[arg-type]
                )
            )
        return cls(version=int(data["version"]), fetch=list(data["fetch"]), rules=rules)

    def classify(self, tags: dict[str, Any], year: int) -> Rule | None:
        """Return the first active, matching rule, or None (=> unclassified)."""
        for rule in self.rules:
            if rule.active_for(year) and rule.matches(tags):
                return rule
        return None
