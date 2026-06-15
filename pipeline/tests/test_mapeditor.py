"""Tests for the map selector GUI's native half (no browser, no network)."""

from __future__ import annotations

import json
import urllib.request
from pathlib import Path

import pytest

from krieg_pipeline.config import BBox, ScenarioConfig
from krieg_pipeline.mapeditor.server import (
    config_from_request,
    list_scenarios,
    make_handler,
    save_scenario,
    scenario_yaml,
    slugify,
)

BBOX = BBox(4.38, 50.66, 4.43, 50.70)


def test_slugify():
    assert slugify("Quatre Bras") == "quatre-bras"
    assert slugify("  La Haye-Sainte!! ") == "la-haye-sainte"
    assert slugify("") == "scenario"
    assert slugify("***") == "scenario"


def test_scenario_yaml_roundtrips_through_config(tmp_path: Path):
    config = ScenarioConfig(name="quatre-bras", bbox=BBOX, target_year=1815 + 65)
    text = scenario_yaml(config)
    path = tmp_path / "qb.yaml"
    path.write_text(text)
    back = ScenarioConfig.from_yaml(path)
    assert back.name == "quatre-bras"
    assert back.bbox.as_tuple() == BBOX.as_tuple()
    assert back.target_year == 1880
    assert back.cluster_buildings is True


def test_config_from_request_validates():
    cfg = config_from_request(
        {"name": "x", "bbox": [4.38, 50.66, 4.43, 50.70], "target_year": 1900}
    )
    assert cfg.target_year == 1900
    # degenerate bbox -> ValueError (surfaced as 400 by the handler)
    with pytest.raises(ValueError):
        config_from_request({"name": "x", "bbox": [4.43, 50.66, 4.38, 50.70]})
    # out-of-range year -> ValueError
    with pytest.raises(ValueError):
        config_from_request({"name": "x", "bbox": list(BBOX.as_tuple()), "target_year": 1700})
    # missing bbox -> KeyError
    with pytest.raises(KeyError):
        config_from_request({"name": "x"})


def test_save_scenario_never_clobbers(tmp_path: Path):
    config = ScenarioConfig(name="Mont St Jean", bbox=BBOX)
    p1 = save_scenario(tmp_path, config, overwrite=False)
    p2 = save_scenario(tmp_path, config, overwrite=False)
    assert p1.name == "mont-st-jean.yaml"
    assert p2.name == "mont-st-jean-2.yaml"
    # overwrite reuses the base name
    p3 = save_scenario(tmp_path, config, overwrite=True)
    assert p3 == p1


def test_list_scenarios_skips_unreadable(tmp_path: Path):
    save_scenario(tmp_path, ScenarioConfig(name="good", bbox=BBOX), overwrite=False)
    (tmp_path / "broken.yaml").write_text("name: broken\nbbox: nonsense\n")
    items = list_scenarios(tmp_path)
    assert [i["name"] for i in items] == ["good"]
    assert items[0]["bbox"] == list(BBOX.as_tuple())


def test_http_save_and_list(tmp_path: Path):
    from http.server import ThreadingHTTPServer
    import threading

    httpd = ThreadingHTTPServer(("127.0.0.1", 0), make_handler(tmp_path))
    threading.Thread(target=httpd.handle_request).start()  # serve the POST
    base = f"http://127.0.0.1:{httpd.server_address[1]}"

    body = json.dumps(
        {"name": "Ligny", "bbox": list(BBOX.as_tuple()), "target_year": 1880}
    ).encode()
    req = urllib.request.Request(
        base + "/api/scenario", data=body, headers={"Content-Type": "application/json"}
    )
    with urllib.request.urlopen(req) as resp:
        data = json.loads(resp.read())
    assert data["file"] == "ligny.yaml"
    assert "krieg-pipeline build" in data["build_cmd"]
    assert (tmp_path / "ligny.yaml").exists()
    httpd.server_close()


def test_http_rejects_bad_bbox(tmp_path: Path):
    from http.server import ThreadingHTTPServer
    import threading

    httpd = ThreadingHTTPServer(("127.0.0.1", 0), make_handler(tmp_path))
    threading.Thread(target=httpd.handle_request).start()
    base = f"http://127.0.0.1:{httpd.server_address[1]}"

    body = json.dumps({"name": "bad", "bbox": [4.43, 50.66, 4.38, 50.70]}).encode()
    req = urllib.request.Request(
        base + "/api/scenario", data=body, headers={"Content-Type": "application/json"}
    )
    with pytest.raises(urllib.error.HTTPError) as exc:
        urllib.request.urlopen(req)
    assert exc.value.code == 400
    httpd.server_close()
