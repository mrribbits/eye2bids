"""Scully Center OPM-MEG eye-tracker metadata, bundled with this install.

eye2bids reads the metadata from the bundled eyelink_MEG_metadata.yml unless
--metadata_file is given. --task sets TaskName, and each field can be
overridden with its own command-line flag (e.g. --screen_distance 0.9).
Only fields in BIDS 1.11 (BEP 020 as merged) have flags.
"""

from __future__ import annotations

import argparse
import re
from importlib.resources import files
from pathlib import Path
from typing import Any

import yaml
from rich.markup import escape

FILENAME = "eyelink_MEG_metadata.yml"

# Metadata fields that can be overridden on the command line: flag -> BIDS field
OVERRIDE_FLAGS: dict[str, str] = {
    "sample_coordinate_system": "SampleCoordinateSystem",
    "screen_origin": "ScreenOrigin",
    "units": "Units",
    "software_version": "SoftwareVersion",
    "screen_refresh_rate": "ScreenRefreshRate",
    "screen_size": "ScreenSize",
    "screen_distance": "ScreenDistance",
    "eye_tracker_distance": "EyeTrackerDistance",
    "raw_data_filters": "RawDataFilters",
    "institution_name": "InstitutionName",
    "institution_address": "InstitutionAddress",
}


def bundled_metadata_file() -> Path:
    """Return the path of the bundled Scully metadata file."""
    return Path(str(files("eye2bids.scully") / FILENAME))


def load_metadata(metadata_file: str | Path | None = None) -> dict[str, Any]:
    """Load a metadata file, or the bundled Scully one if none is given."""
    path = Path(metadata_file) if metadata_file else bundled_metadata_file()
    with path.open() as f:
        return yaml.safe_load(f) or {}


def _yaml_value(text: str) -> Any:
    """Parse a flag value as YAML: 0.9 -> float, [a, b] -> list, {k: v} -> dict."""
    try:
        return yaml.safe_load(text)
    except yaml.YAMLError as e:
        raise argparse.ArgumentTypeError(f"not a valid value: {text!r} ({e})") from e


def _task_label(text: str) -> str:
    """Check that the task name is a valid BIDS label."""
    if not re.fullmatch(r"[A-Za-z0-9]+", text):
        raise argparse.ArgumentTypeError(
            f"{text!r} is not a valid task name: use letters and digits only "
            "(the task- label in your filenames, e.g. oddball)"
        )
    return text


def _show(value: Any) -> str:
    """Format a metadata value on one line, as it would be typed on the command line."""
    text = yaml.safe_dump(value, default_flow_style=True, sort_keys=False, width=1000)
    return text.strip().removesuffix("...").strip()


def add_metadata_arguments(parser: argparse.ArgumentParser) -> None:
    """Add --task and the metadata override flags to the parser."""
    parser.add_argument(
        "--task",
        type=_task_label,
        required=True,
        help="Task name, written as TaskName (the task- label in your filenames).",
    )
    try:
        defaults = load_metadata()
    except FileNotFoundError:
        defaults = {}
    group = parser.add_argument_group(
        "metadata overrides",
        "Replace one value from the metadata file (by default the Scully MEG "
        "lab's file bundled with this install). Values are read as YAML, "
        'e.g. 0.9 or "[0.606, 0.341]". '
        "Distances and sizes are in meters.",
    )
    for flag, field in OVERRIDE_FLAGS.items():
        default = defaults.get(field)
        shown = "not set" if default is None else _show(default)
        group.add_argument(
            f"--{flag}",
            type=_yaml_value,
            default=None,
            metavar="VALUE",
            help=escape(f"{field} (Scully default: {shown})"),
        )


def build_metadata(args: argparse.Namespace) -> dict[str, Any]:
    """Return the metadata file's values with the command-line overrides applied."""
    metadata = load_metadata(args.metadata_file)
    for flag, field in OVERRIDE_FLAGS.items():
        value = getattr(args, flag)
        if value is not None:
            metadata[field] = value
    metadata["TaskName"] = args.task
    return metadata
