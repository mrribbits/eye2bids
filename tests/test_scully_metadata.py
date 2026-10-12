"""Tests for --task, the bundled Scully metadata and the override flags."""

from __future__ import annotations

import pytest
import yaml

import eye2bids._cli as cli_module
from eye2bids.scully.metadata import load_metadata


@pytest.fixture
def run_cli(monkeypatch, tmp_path):
    """Run the CLI with edf2bids replaced, returning the metadata it receives."""
    received = {}

    def fake_edf2bids(metadata_file, **kwargs):
        received.update(yaml.safe_load(metadata_file.read_text()))

    monkeypatch.setattr(cli_module, "edf2bids", fake_edf2bids)

    def run(*args):
        received.clear()
        cli_module.cli(["eye2bids", "--input_file", "x.edf", *args])
        return dict(received)

    return run


def test_bundled_metadata_is_packaged():
    assert "SampleCoordinateSystem" in load_metadata()


def test_task_is_required(run_cli):
    with pytest.raises(SystemExit):
        run_cli()


@pytest.mark.parametrize("task", ["odd-ball", "odd_ball", "odd ball", ""])
def test_invalid_task_is_rejected(run_cli, task):
    with pytest.raises(SystemExit):
        run_cli("--task", task)


def test_bundled_metadata_used_by_default(run_cli):
    metadata = run_cli("--task", "oddball")
    expected = load_metadata()
    expected["TaskName"] = "oddball"
    assert metadata == expected


def test_overrides(run_cli):
    metadata = run_cli(
        "--task",
        "oddball",
        "--screen_distance",
        "0.9",
        "--screen_size",
        "[0.5, 0.3]",
        "--eye_camera_settings",
        "{Lens: 25 mm}",
        "--institution_name",
        "Somewhere Else",
    )
    assert metadata["ScreenDistance"] == 0.9
    assert metadata["ScreenSize"] == [0.5, 0.3]
    assert metadata["EyeCameraSettings"] == {"Lens": "25 mm"}
    assert metadata["InstitutionName"] == "Somewhere Else"
    # untouched fields keep the bundled values
    assert metadata["Units"] == load_metadata()["Units"]


def test_other_metadata_file(run_cli, tmp_path):
    other = tmp_path / "other.yml"
    other.write_text("Units: deg\nScreenDistance: 0.5\n")
    metadata = run_cli("--task", "rest", "--metadata_file", str(other))
    assert metadata == {"Units": "deg", "ScreenDistance": 0.5, "TaskName": "rest"}


@pytest.mark.parametrize("flag", ["--screen_distanc", "--not_a_flag"])
def test_unknown_or_abbreviated_flag_is_an_error(run_cli, flag):
    with pytest.raises(SystemExit):
        run_cli("--task", "oddball", flag, "1")
