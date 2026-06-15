"""Command-line entry point for the Krieg map pipeline (ADR-0003).

    krieg-pipeline build --scenario scenarios/waterloo.yaml --out out/waterloo
    krieg-pipeline build --bbox 4.38,50.66,4.43,50.70 --year 1880 --out out/demo
"""

from __future__ import annotations

import argparse
import logging
import sys
from pathlib import Path

from .config import BBox, ScenarioConfig
from .pipeline import build


def _config_from_args(args: argparse.Namespace) -> ScenarioConfig:
    if args.scenario:
        config = ScenarioConfig.from_yaml(Path(args.scenario))
        # CLI flags override the file when given.
        overrides = {}
        if args.year is not None:
            overrides["target_year"] = args.year
        if args.contour_interval is not None:
            overrides["contour_interval_m"] = args.contour_interval
        if args.ruleset is not None:
            overrides["ruleset_path"] = Path(args.ruleset)
        if overrides:
            from dataclasses import replace

            config = replace(config, **overrides)
        return config
    if not args.bbox:
        raise SystemExit("error: provide --scenario or --bbox")
    return ScenarioConfig(
        name=args.name or "untitled",
        bbox=BBox.parse(args.bbox),
        target_year=args.year if args.year is not None else 1880,
        contour_interval_m=args.contour_interval if args.contour_interval is not None else 10.0,
        cluster_buildings=not args.no_cluster,
        ruleset_path=Path(args.ruleset) if args.ruleset else None,
    )


def cmd_build(args: argparse.Namespace) -> int:
    config = _config_from_args(args)
    logging.info("Building scenario %r → %s", config.name, args.out)
    result = build(config, Path(args.out), work_dir=Path(args.work) if args.work else None)
    print(f"\n✓ {result.scenario_path}")
    print(f"  {result.feature_count} board features")
    print(f"  {result.report.summary()}")
    if args.preview:
        from .preview import render

        preview_path = render(result.scenario_path, Path(args.out) / "preview.png")
        print(f"  preview: {preview_path}")
    return 0


def cmd_preview(args: argparse.Namespace) -> int:
    from .preview import render

    scenario = Path(args.scenario)
    if scenario.is_dir():
        scenario = scenario / "scenario.json"
    out = Path(args.out) if args.out else scenario.parent / "preview.png"
    render(scenario, out)
    print(f"✓ {out}")
    return 0


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(prog="krieg-pipeline", description=__doc__)
    p.add_argument("-v", "--verbose", action="store_true", help="debug logging")
    sub = p.add_subparsers(dest="command", required=True)

    b = sub.add_parser("build", help="build a scenario package from a bbox")
    b.add_argument("--scenario", help="scenario YAML config")
    b.add_argument("--bbox", help="min_lon,min_lat,max_lon,max_lat (WGS84)")
    b.add_argument("--name", help="scenario name (with --bbox)")
    b.add_argument("--year", type=int, help="target year (1860–1917)")
    b.add_argument("--contour-interval", type=float, help="contour interval, metres")
    b.add_argument("--ruleset", help="period ruleset YAML (default: packaged)")
    b.add_argument("--no-cluster", action="store_true", help="disable building clustering")
    b.add_argument("--work", help="intermediate working dir (default: temp)")
    b.add_argument("--preview", action="store_true", help="also render preview.png")
    b.add_argument("--out", required=True, help="output scenario package directory")
    b.set_defaults(func=cmd_build)

    pv = sub.add_parser("preview", help="render a quick-look PNG of a package")
    pv.add_argument("scenario", help="scenario.json (or its package directory)")
    pv.add_argument("--out", help="output PNG (default: <package>/preview.png)")
    pv.set_defaults(func=cmd_preview)
    return p


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv if argv is not None else sys.argv[1:])
    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.INFO,
        format="%(levelname)s %(name)s: %(message)s",
    )
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
