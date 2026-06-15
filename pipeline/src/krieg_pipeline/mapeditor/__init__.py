"""Graphical map selector — the seed of the future map editor (PLAN §8).

A small local web tool that shows an OpenStreetMap slippy map, lets you draw the
scenario bounding box and set the period knobs, and writes a scenario YAML that
the pipeline (``krieg-pipeline build``) consumes. It deliberately owns only the
*selection* step today; the Leaflet draw/edit surface is the foundation for the
later phase that edits individual board features.
"""

from __future__ import annotations

from .server import serve

__all__ = ["serve"]
