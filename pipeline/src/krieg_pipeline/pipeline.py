"""Pipeline orchestrator: chains the stages (ADR-0003).

acquire → clip → filter → reproject → contour → classify → emit
"""

from __future__ import annotations

import logging
import tempfile
from dataclasses import dataclass
from pathlib import Path

from .config import ScenarioConfig
from .ruleset import Ruleset
from .stages import acquire as acquire_stage
from .stages import clip as clip_stage
from .stages import emit as emit_stage
from .stages import filter as filter_stage
from .stages import reproject as reproject_stage
from .stages.classify import classify
from .stages.contour import contour

log = logging.getLogger(__name__)


@dataclass
class BuildResult:
    scenario_path: Path
    feature_count: int
    report: "filter_stage.FilterReport"


def build(config: ScenarioConfig, out_dir: Path, work_dir: Path | None = None) -> BuildResult:
    out_dir = Path(out_dir)
    ruleset = Ruleset.load(config.ruleset_path)

    tmp = None
    if work_dir is None:
        tmp = tempfile.TemporaryDirectory(prefix="krieg-")
        work_dir = Path(tmp.name)
    work_dir = Path(work_dir)
    work_dir.mkdir(parents=True, exist_ok=True)

    try:
        log.info("[1/7] acquire")
        acquired = acquire_stage.acquire(config.bbox, ruleset, work_dir)

        log.info("[2/7] clip")
        clipped = clip_stage.clip(acquired.features, config.bbox)

        log.info("[3/7] filter")
        filtered, report = filter_stage.filter_features(
            clipped, ruleset, config.target_year
        )

        log.info("[4/7] reproject")
        projected, proj = reproject_stage.reproject(filtered, config.bbox)

        log.info("[5/7] contour")
        relief = contour(
            acquired.dem_path, proj, config.contour_interval_m, out_dir / "assets"
        )

        log.info("[6/7] classify")
        board = classify(projected, relief.contours, config.cluster_buildings)

        log.info("[7/7] emit")
        scenario_path = emit_stage.emit(board, config, proj, relief, out_dir)

        return BuildResult(
            scenario_path=scenario_path, feature_count=len(board), report=report
        )
    finally:
        if tmp is not None:
            tmp.cleanup()
