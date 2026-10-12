# eye2bids for the Scully Center OPM-MEG eye tracker

This branch has what you need to convert EyeLink `.edf` recordings from the
Scully Center OPM-MEG lab to [BIDS](https://bids-specification.readthedocs.io/)
eye-tracking format.

## Which eye2bids to use

**Install the patched eye2bids from this fork** (a pinned commit of branch
`scully-eye2bids`, see [Installation](#installation)), not the official
[bids-standard/eye2bids](https://github.com/bids-standard/eye2bids) release.
It has three changes that are detailed at the end of the README. 

## Installation

eye2bids needs two things: 
1- The `eye2bids` Python package
2- SR Research's `edf2asc` program, which eye2bids runs to read the `.edf` files.

### 1. Install eye2bids with pip

Install it into your Python or conda environment (Python 3.9 or newer) straight
from GitHub, pinned to the tested commit:

```bash
pip install "git+https://github.com/mrribbits/eye2bids.git@ea4a50ee19d891b88055f8d5466a4106eab72f38"
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
distance, camera, filters). The MEG lab's settings are bundled with the
install and used automatically, so there's no file to download or edit.

To change a single value for your recordings, add its flag. Values are read as
YAML: numbers, lists in `[...]`, and groups of settings in `{...}`. Distances
and sizes are in meters.

```bash
eye2bids --input_file sub-001_task-oddball.edf --task oddball \
         --screen_distance 0.9 \
         --eye_camera_settings "{Configuration: OPM (Remote), Lens: 25 mm}"
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
| `--screen_aoi_definition` | `ScreenAOIDefinition` |
| `--eye_camera_settings` | `EyeCameraSettings` |
| `--feature_detection_settings` | `FeatureDetectionSettings` |
| `--gaze_mapping_settings` | `GazeMappingSettings` |
| `--raw_data_filters` | `RawDataFilters` |
| `--institution_name` | `InstitutionName` |
| `--institution_address` | `InstitutionAddress` |

A flag replaces the whole value, so for a group like `--eye_camera_settings`,
give all of its settings, not just the one that changed.

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

## Three changes in this from the official eye2bids repo.

The first two only affect Remote-mode recordings;
head-stabilized recordings are otherwise converted exactly as by the official release.

The MEG lab's EyeLink 1000 Plus uses the **OPM mount in Remote mode**: it
tracks a target sticker on the forehead instead of relying on a stabilized head
(OPM (Remote) - Target Sticker - Monocular).

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
([pull request #<target>](https://github.com/bids-standard/eye2bids/pull/NNN))

**3. Fix: correct screen resolution.** The official eye2bids writes
`ScreenResolution` in `_events.json` as `[1919, 1079]` for a 1920 x 1080 screen
(it copies the last pixel's coordinates instead of the pixel count). The
patched version writes `[1920, 1080]`. This affects all recordings.
([pull request #<screenres>](https://github.com/bids-standard/eye2bids/pull/MMM))

All three changes have been submitted to the eye2bids developers. Once they're
merged, these instructions will switch to the official release and this fork will
no longer be needed; reinstall at that point to get the official version.
