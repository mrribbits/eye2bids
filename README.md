# eye2bids for the Scully Center OPM-MEG eye tracker

This branch has what you need to convert EyeLink `.edf` recordings from the
Scully Center OPM-MEG lab to [BIDS](https://bids-specification.readthedocs.io/)
eye-tracking format:

- `install_eye2bids.sh`: installs eye2bids and SR Research's `edf2asc` on the cluster (no sudo needed)
- `eyelink_MEG_metadata.yml`: the MEG lab's eye-tracker settings (screen, distances, camera, filters)

The installer uses a patched eye2bids from this fork, which fixes a crash with
EyeLink remote-mode recordings. The fix has been submitted upstream to
[bids-standard/eye2bids](https://github.com/bids-standard/eye2bids).

## 1. Download the install script

Download it into your jukebox partition. Replace `[...]` with your own path,
e.g. `/jukebox/yourlab/software`.

```bash
cd /jukebox/[...]
curl -fsSLO https://raw.githubusercontent.com/mrribbits/eye2bids/scully-config/eyetracking/install_eye2bids.sh
```

## 2. Run the installer

```bash
INSTALL_DIR=/jukebox/[...]/eye2bids bash install_eye2bids.sh
```

Everything goes into `INSTALL_DIR`. To uninstall, delete that folder.

eye2bids needs Python 3.9 or newer. If `python3` on your system is older, load a
newer Python first or point the installer at one:

```bash
INSTALL_DIR=/jukebox/[...]/eye2bids PYTHON=/path/to/python3.11 bash install_eye2bids.sh
```

## 3. Get the Scully MEG metadata file

The installer downloads it automatically to
`/jukebox/[...]/eye2bids/eyelink_MEG_metadata.yml`. To download it separately:

```bash
curl -fsSLO https://raw.githubusercontent.com/mrribbits/eye2bids/scully-config/eyetracking/eyelink_MEG_metadata.yml
```

Copy the file into your project and change **`TaskName`** to match your task
(the `task-` label in your filenames). The other settings describe the MEG
lab's eye-tracking setup and shouldn't need changing.

## 4. Run eye2bids

Load the environment in each new shell (or Slurm job), then check that it works:

```bash
source /jukebox/[...]/eye2bids/eye2bids_env.sh
eye2bids -h
```

Example:

```bash
eye2bids --input_file sub-001_ses-001_task-oddballftcued.edf \
         --metadata_file eyelink_MEG_metadata.yml
```

Output goes to the current folder unless you add `--output_dir <folder>`.

## Outputs

For `sub-001_ses-001_task-oddballftcued.edf` you get:

| File | What it is |
|---|---|
| `…_recording-eye1_physio.tsv.gz` | Continuous gaze data, one row per sample: timestamp, x, y, pupil size. No header row; the column names are in the `.json`. |
| `…_recording-eye1_physio.json` | Describes the gaze data: your metadata settings plus values read from the EDF (sampling rate, recorded eye, calibration type and errors, pupil fit method). |
| `…_recording-eye1_physioevents.tsv.gz` | Events detected by EyeLink (fixations, saccades, blinks) and every message your experiment sent to the tracker (e.g. trial markers). Columns: onset, duration, trial_type, blink, message. |
| `…_recording-eye1_physioevents.json` | Describes the physioevents columns. |
| `…_events.json` | Stimulus display details (screen size, distance, refresh rate, resolution) plus task and institution. |
| `…_samples.asc`, `…_events.asc` | Temporary text versions of the EDF made by `edf2asc`. Not BIDS files: delete them or keep them in `sourcedata/` with the EDF. |

Notes:

- **The `recording-eye1` label doesn't mean the left eye.** It's used for any single recorded eye. Check `RecordedEye` in `_physio.json` for which eye it was.
- **eye2bids doesn't create an `_events.tsv`** of task trials. Supply it from your experiment log or MEG events; `_events.json` describes it.
- **Change `ScreenResolution` in `_events.json` to `[1920, 1080]`.** eye2bids writes `[1919, 1079]`, a known off-by-one.
- **Multiple recording blocks in one EDF end up in one continuous file.** The log prints a note about multiple start/stop times; this is expected.
- **Put the outputs in the `meg/` folder of the matching session.** BIDS has no `physio/` folder: eye-tracking files go in the same datatype folder as the recording they accompany, e.g. `sub-001/ses-001/meg/`. Their `sub-`, `ses-`, `task-` (and `run-`, if used) labels should match the MEG run's.
