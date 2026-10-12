"""edf2asc runs quietly: its output is only shown if a conversion fails."""

from __future__ import annotations

import os

import pytest

from eye2bids.edf2bids import (
    _check_edf2asc_present,
    _convert_edf_to_asc_events,
    _convert_edf_to_asc_samples,
)


@pytest.fixture
def fake_edf2asc(tmp_path, monkeypatch):
    """Put a fake edf2asc on PATH that prints a banner and writes the .asc file."""
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    script = bin_dir / "edf2asc"
    script.write_text(
        "#!/bin/sh\n"
        'echo "EDF2ASC: EyeLink EDF file -> ASCII (text) file translator"\n'
        'if [ "$#" -eq 0 ]; then echo "USAGE: edf2asc [options] <input .edf file>"; '
        "exit 1; fi\n"
        'for a in "$@"; do out="$a"; done\n'  # last argument is the -o target
        '[ -n "$FAIL" ] || echo "MSG 1 TEST" > "$out.asc"\n'
    )
    script.chmod(0o755)
    monkeypatch.setenv("PATH", f"{bin_dir}{os.pathsep}{os.environ['PATH']}")
    return tmp_path


def test_check_edf2asc_present_is_silent(fake_edf2asc, capfd):
    assert _check_edf2asc_present()
    out, err = capfd.readouterr()
    assert "USAGE" not in out + err


def test_edf2asc_output_not_printed(fake_edf2asc, capfd):
    edf = fake_edf2asc / "sub-01.edf"
    edf.write_text("")
    asc = _convert_edf_to_asc_events(edf)
    assert asc.exists()
    out, err = capfd.readouterr()
    assert "EDF2ASC" not in out + err


def test_edf2asc_failure_is_reported(fake_edf2asc, monkeypatch, caplog):
    monkeypatch.setenv("FAIL", "1")
    edf = fake_edf2asc / "sub-01.edf"
    edf.write_text("")
    asc = _convert_edf_to_asc_samples(edf)
    assert not asc.exists()
    assert "could not convert" in caplog.text
    assert "EDF2ASC" in caplog.text  # edf2asc's own output is included
