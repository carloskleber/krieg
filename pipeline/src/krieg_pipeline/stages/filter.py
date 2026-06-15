"""Stage 3 — filter: apply the declarative period ruleset (ADR-0006).

Drops anachronisms, demotes roads to period classes, keeps & categorises period
terrain and tactical strongpoints. Everything that matches no rule is dropped and
counted, so authors can spot gaps in worldwide OSM tagging.
"""

from __future__ import annotations

import logging
from collections import Counter
from dataclasses import dataclass, field

import geopandas as gpd

from ..ruleset import Ruleset

log = logging.getLogger(__name__)

# OSM keys that meaningfully identify a feature's "kind" — used only to summarise
# what was dropped as unclassified, not for any decision.
_SUMMARY_KEYS = (
    "highway",
    "natural",
    "landuse",
    "leisure",
    "building",
    "amenity",
    "waterway",
    "railway",
    "man_made",
)


@dataclass
class FilterReport:
    kept: int = 0
    dropped: int = 0
    unclassified: Counter = field(default_factory=Counter)
    by_category: Counter = field(default_factory=Counter)

    def summary(self) -> str:
        cats = ", ".join(f"{c}={n}" for c, n in sorted(self.by_category.items()))
        top = ", ".join(f"{k}={n}" for k, n in self.unclassified.most_common(8))
        return (
            f"kept={self.kept} dropped={self.dropped} | {cats}"
            + (f"\n  unclassified: {top}" if top else "")
        )


def _summary_token(tags: dict) -> str:
    for key in _SUMMARY_KEYS:
        if key in tags:
            return f"{key}={tags[key]}"
    return "(other)"


def filter_features(
    features: gpd.GeoDataFrame, ruleset: Ruleset, year: int
) -> tuple[gpd.GeoDataFrame, FilterReport]:
    report = FilterReport()
    if features.empty:
        return features.assign(category=[], road_class=[]), report

    categories: list[str] = []
    name_col: list = []
    extra: dict[str, list] = {"road_class": [], "water_class": [], "building_role": []}
    keep_mask: list[bool] = []

    for tags in features["tags"]:
        tags = tags or {}
        rule = ruleset.classify(tags, year)
        if rule is None or rule.action == "drop":
            keep_mask.append(False)
            categories.append(None)
            name_col.append(None)
            for k in extra:
                extra[k].append(None)
            if rule is None:
                report.unclassified[_summary_token(tags)] += 1
            report.dropped += 1
            continue
        keep_mask.append(True)
        categories.append(rule.category)
        name_col.append(tags.get("name"))
        for k in extra:
            extra[k].append(rule.props.get(k))
        report.kept += 1
        report.by_category[rule.category] += 1

    out = features.copy()
    out["category"] = categories
    out["name"] = name_col
    for k, vals in extra.items():
        out[k] = vals
    out = out[keep_mask].reset_index(drop=True)
    out = out.drop(columns=["tags"])
    log.info("Filter: %s", report.summary())
    return out, report
