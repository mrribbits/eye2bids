"""physioevents.json declares OnsetSource, as required by BIDS 1.11 (BEP 020)."""

from __future__ import annotations

from eye2bids._base import BasePhysioEventsJson


def test_physioevents_json_onset_source():
    sidecar = BasePhysioEventsJson()
    assert sidecar["OnsetSource"] == "timestamp"
    assert "ForeignIndexColumn" not in sidecar
