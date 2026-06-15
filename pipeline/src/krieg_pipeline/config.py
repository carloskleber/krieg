"""Scenario build configuration (the input contract for the pipeline).

A scenario is fully described by a bounding box plus a few period knobs. The
config is hashed into the output metadata so a package is reproducible from
``inputs + tool version + config`` (ADR-0003).
"""

from __future__ import annotations

import hashlib
import json
from dataclasses import asdict, dataclass, field
from pathlib import Path

import yaml

# Valid target-year range for the period (PLAN §7, ADR-0006/0007).
MIN_YEAR = 1860
MAX_YEAR = 1917


@dataclass(frozen=True)
class BBox:
    """Geographic bounding box in WGS84 degrees."""

    min_lon: float
    min_lat: float
    max_lon: float
    max_lat: float

    def __post_init__(self) -> None:
        if not (self.min_lon < self.max_lon and self.min_lat < self.max_lat):
            raise ValueError(f"degenerate bbox: {self}")
        if not (-180 <= self.min_lon <= 180 and -180 <= self.max_lon <= 180):
            raise ValueError(f"longitude out of range: {self}")
        if not (-90 <= self.min_lat <= 90 and -90 <= self.max_lat <= 90):
            raise ValueError(f"latitude out of range: {self}")

    @classmethod
    def parse(cls, text: str) -> "BBox":
        """Parse ``min_lon,min_lat,max_lon,max_lat``."""
        parts = [float(p) for p in text.split(",")]
        if len(parts) != 4:
            raise ValueError("bbox must be 'min_lon,min_lat,max_lon,max_lat'")
        return cls(*parts)

    @property
    def centroid(self) -> tuple[float, float]:
        return ((self.min_lon + self.max_lon) / 2, (self.min_lat + self.max_lat) / 2)

    def as_tuple(self) -> tuple[float, float, float, float]:
        return (self.min_lon, self.min_lat, self.max_lon, self.max_lat)


@dataclass(frozen=True)
class ScenarioConfig:
    """Everything needed to build one scenario package."""

    name: str
    bbox: BBox
    target_year: int = 1880
    # Contour interval in metres (ADR-0002/0004 metadata).
    contour_interval_m: float = 10.0
    # Cluster dense building footprints into village blocks (ADR-0006 knob).
    cluster_buildings: bool = True
    # Path to the period ruleset; None => packaged default (ADR-0006).
    ruleset_path: Path | None = None

    def __post_init__(self) -> None:
        if not (MIN_YEAR <= self.target_year <= MAX_YEAR):
            raise ValueError(
                f"target_year {self.target_year} outside valid range "
                f"{MIN_YEAR}-{MAX_YEAR} (PLAN §7)"
            )
        if self.contour_interval_m <= 0:
            raise ValueError("contour_interval_m must be positive")

    @classmethod
    def from_yaml(cls, path: Path) -> "ScenarioConfig":
        data = yaml.safe_load(Path(path).read_text())
        bbox = data["bbox"]
        if isinstance(bbox, str):
            bbox = BBox.parse(bbox)
        elif isinstance(bbox, (list, tuple)):
            bbox = BBox(*bbox)
        else:
            bbox = BBox(**bbox)
        ruleset = data.get("ruleset_path")
        return cls(
            name=data["name"],
            bbox=bbox,
            target_year=int(data.get("target_year", 1880)),
            contour_interval_m=float(data.get("contour_interval_m", 10.0)),
            cluster_buildings=bool(data.get("cluster_buildings", True)),
            ruleset_path=Path(ruleset) if ruleset else None,
        )

    def hash(self) -> str:
        """Stable hash of the config, recorded in package metadata (ADR-0003)."""
        payload = asdict(self)
        payload["bbox"] = self.bbox.as_tuple()
        payload["ruleset_path"] = str(self.ruleset_path) if self.ruleset_path else None
        blob = json.dumps(payload, sort_keys=True).encode()
        return hashlib.sha256(blob).hexdigest()[:16]
