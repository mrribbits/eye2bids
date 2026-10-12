# eye2bids for the Scully Center OPM-MEG eye tracker

This branch has what you need to convert EyeLink `.edf` recordings from the
Scully Center OPM-MEG lab to [BIDS](https://bids-specification.readthedocs.io/)
eye-tracking format.

## Which eye2bids to use

**Install the patched eye2bids from this fork** (a pinned commit of branch
`scully-eye2bids`, see [Installation](#installation)), not the official
[bids-standard/eye2bids](https://github.com/bids-standard/eye2bids) release.
It differs from the official release in a few ways, listed in
[Changes from the official eye2bids](#changes-from-the-official-eye2bids).

## Installation

eye2bids needs two things: 
1- The `eye2bids` Python package
2- SR Research's `edf2asc` program, which eye2bids runs to read the `.edf` files.

### 1. Install eye2bids with pip

Install it into your Python or conda environment (Python 3.9 or newer) straight
from GitHub, pinned to the tested commit:

```bash
pip install "git+https://github.com/mrribbits/eye2bids.git@e2e4b304c3bc579cb8cf6f0589e293d0291fac6d"
```

This installs `numpy`, `pandas` (2.0 or newer), `pyaml`, `rich` and
`rich-argparse` if they're missing, and adds an `eye2bids` command. The MEG
lab's eye-tracker settings come with it as well (see [Metadata](#metadata)).

The commit ID pins exactly the version the Scully Center tested, so a later
push to the fork can't change what you install.

### 2. Install edf2asc

**On Linux** (e.g. the cluster), fetch the install script and run it:

```bash
curl -fsSLO https://raw.githubusercontent.com/mrribbits/eye2bids/scully-config/eyetracking/install_edf2asc.sh
INSTALL_DIR=/jukebox/[yourpath]/edf2asc bash install_edf2asc.sh
```

Then add it to your PATH, e.g. in `~/.bashrc` (the script prints the line for you to add).

**On a Mac**, install SR Research's EyeLink Developers Kit, which includes
`edf2asc`. Its download needs a login:

1. Log in to the [SR Research support forum](https://www.sr-research.com/support/),
   then download and run the **EyeLink Developers Kit** installer for macOS.
2. Open a new terminal and check that `which edf2asc` prints a path.

### 3. Check

```bash
which edf2asc
eye2bids --version
```

## Run eye2bids

`--task` is required: it's your task label, written as `TaskName` (use the
`task-` label in your BIDS filenames, letters and digits only).

```bash
eye2bids --input_file sub-001_ses-001_task-oddballftcued.edf \
         --task oddballftcued
```

Output goes to the current folder unless you add `--output_dir <folder>`.
Run `eye2bids -h` for all options.

## Metadata

eye2bids needs metadata describing the eye-tracking setup (screen size and
distance, eye-tracker distance, filters). The MEG lab's settings are bundled
with the install and used automatically, so there's no file to download or edit.
Only fields defined in BIDS 1.11 are written.

To change a single value for your recordings, add its flag. Values are read as
YAML: numbers, or lists in `[...]`. Distances and sizes are in meters.

```bash
eye2bids --input_file sub-001_task-oddball.edf --task oddball \
         --screen_distance 0.9 --screen_size "[0.5, 0.3]"
```

`eye2bids -h` lists every flag with the MEG lab's default value:

| Flag | BIDS field |
|---|---|
| `--sample_coordinate_system` | `SampleCoordinateSystem` |
| `--screen_origin` | `ScreenOrigin` |
| `--units` | `Units` |
| `--software_version` | `SoftwareVersion` |
| `--screen_refresh_rate` | `ScreenRefreshRate` |
| `--screen_size` | `ScreenSize` |
| `--screen_distance` | `ScreenDistance` |
| `--eye_tracker_distance` | `EyeTrackerDistance` |
| `--raw_data_filters` | `RawDataFilters` |
| `--institution_name` | `InstitutionName` |
| `--institution_address` | `InstitutionAddress` |

For a different setup altogether, pass your own file with
`--metadata_file my_metadata.yml`; the flags and `--task` still apply on top of it.

## Outputs

For `sub-001_ses-001_task-oddballftcued.edf` you get:

| File | What it is |
|---|---|
| `…_recording-eye1_physio.tsv.gz` | Continuous gaze data, one row per sample: timestamp, x, y, pupil size, then the target sticker columns (`target_x`, `target_y`, `target_distance`, `target_flags`). No header row; the column names are in the `.json`. In `target_flags`, `0` means no warnings and `1` means the target was missing; the `.json` lists the other values. |
| `…_recording-eye1_physio.json` | Describes the gaze data: your metadata settings plus values read from the EDF (sampling rate, recorded eye, calibration type and errors, pupil fit method). |
| `…_recording-eye1_physioevents.tsv.gz` | Events detected by EyeLink (fixations, saccades, blinks) and every message your experiment sent to the tracker (e.g. trial markers). Columns: onset, duration, trial_type, blink, message. |
| `…_recording-eye1_physioevents.json` | Describes the physioevents columns. |
| `…_events.json` | Stimulus display details (screen size, distance, refresh rate, resolution) plus task and institution. |
| `…_samples.asc`, `…_events.asc` | Temporary text versions of the EDF made by `edf2asc`. Not BIDS files: delete them or keep them in `sourcedata/` with the EDF. |

Notes:

- **The `recording-eye1` label doesn't mean the left eye.** It's used for any single recorded eye. Check `RecordedEye` in `_physio.json` for which eye it was.
- **eye2bids doesn't create an `_events.tsv`** of task trials. Supply it from your experiment log or MEG events; `_events.json` describes it.
- **Multiple recording blocks in one EDF end up in one continuous file.** The log prints a note about multiple start/stop times; this is expected.
- **Put the outputs in the `meg/` folder of the matching session.** BIDS has no `physio/` folder: eye-tracking files go in the same datatype folder as the recording they accompany, e.g. `sub-001/ses-001/meg/`. Their `sub-`, `ses-`, `task-` (and `run-`, if used) labels should match the MEG run's.

## Changes from the official eye2bids

### Fixes and additions submitted to the eye2bids developers

The first two only affect Remote-mode recordings. The MEG lab's EyeLink 1000
Plus uses the **OPM mount in Remote mode**: it tracks a target sticker on the
forehead instead of relying on a stabilized head (OPM (Remote) - Target
Sticker - Monocular).

**1. Fix: Remote-mode files no longer crash.** In Remote mode, the tracker writes
its recording settings to the EDF in a slightly different format than in
head-stabilized mode, with two extra fields before the recorded eye:

```
RECCFG CR 500 2 2 2 2 R     <- OPM mount, Remote mode (target sticker)
RECCFG CR 1000 2 1 R        <- head-stabilized mode
```

The official eye2bids expects the head-stabilized format. With Remote-mode files it
can't tell which eye was recorded, and the conversion crashes partway through
(`UnboundLocalError: ... 'data_to_save'`). The patched version reads the eye
correctly from both formats.
([pull request #143](https://github.com/bids-standard/eye2bids/pull/143))

**2. New: target sticker data is kept.** In Remote mode, every sample also
records where the target sticker is. The official eye2bids discards this; the
patched version adds it to `_physio.tsv.gz` as four extra columns:
`target_x`, `target_y` (sticker position in the camera image), `target_distance`
(sticker-to-camera distance, mm) and `target_flags` (tracker warnings, e.g. target
missing). This gives a continuous record of head movement during the MEG run.
The same pull request also fixes two-eye recordings, where missing samples for
the second eye were written as `.` instead of `n/a`.
([pull request #144](https://github.com/bids-standard/eye2bids/pull/144))

**3. Fix: correct screen resolution.** The official eye2bids writes
`ScreenResolution` in `_events.json` as `[1919, 1079]` for a 1920 x 1080 screen
(it copies the last pixel's coordinates instead of the pixel count). The
patched version writes `[1920, 1080]`. This affects all recordings.
([pull request #145](https://github.com/bids-standard/eye2bids/pull/145))

**4. Fix: sidecar fields match BIDS 1.11.** The eye-tracking part of BIDS
changed during review, before it was released in BIDS 1.11.0, and the official
eye2bids still follows the earlier draft. The patched version writes
`"OnsetSource": "timestamp"` in `_physioevents.json` (the official release writes
the draft name `ForeignIndexColumn`, so the BIDS validator reports the required
`OnsetSource` as missing). It also no longer writes fields that were dropped
from the specification: `EyeCameraSettings`, `FeatureDetectionSettings`,
`GazeMappingSettings`, `ScreenAOIDefinition` and `StopTime`. This affects all
recordings.
([pull request #146](https://github.com/bids-standard/eye2bids/pull/146))

### Scully Center additions (only in this fork)

These make the converter simpler to use for the MEG lab and aren't meant for
the official release:

- **Bundled MEG lab metadata, `--task` and override flags.** The MEG lab's
  eye-tracker settings come with the install and are used by default; `--task`
  (required) sets `TaskName`, and each setting can be overridden with its own
  flag. See [Metadata](#metadata).
- **Quieter output.** eye2bids no longer prints `edf2asc`'s usage text and
  file headers, or a pandas warning about mixed column types. `edf2asc`'s output
  still appears with `--verbosity 3`, and in full if a conversion fails.

### When the fixes are merged

Once the four pull requests are merged into the official eye2bids, the fork is
needed only for the Scully additions. Until then, install the pinned commit
above; this README will say when that changes.
