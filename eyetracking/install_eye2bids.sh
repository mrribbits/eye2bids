#!/usr/bin/env bash
# install_eye2bids.sh
# Installs eye2bids (patched fork) plus SR Research's edf2asc, without sudo.
# Works on Linux (x86_64 or arm64) and macOS.
#
#   Linux: edf2asc is downloaded from SR Research's apt repository.
#   macOS: SR Research's downloads need a forum login, so install the
#          EyeLink Developers Kit for macOS yourself first (it provides
#          edf2asc). This script then finds it.
#
# Usage:
#   bash install_eye2bids.sh
#   source <INSTALL_DIR>/eye2bids_env.sh   # every new shell, before running eye2bids
#
# Everything is installed under INSTALL_DIR; delete that folder to uninstall.

set -euo pipefail

# ============================================================
# Settings: edit these
# ============================================================

# Where everything gets installed
INSTALL_DIR="${INSTALL_DIR:-$HOME/software/eye2bids}"

# Python >= 3.9 to build the virtual environment from
# (on the cluster you may need e.g. "module load anacondapy" first)
PYTHON="${PYTHON:-python3}"

# eye2bids source: a pinned commit of the fork's scully-eye2bids branch,
# which combines the official eye2bids with fixes submitted upstream but not
# yet merged:
#   PR #143 (Remote-mode RECCFG fix), PR #144 (target sticker columns,
#   eye2 n/a fix), PR #145 (ScreenResolution off-by-one).
# EYE2BIDS_REF is a full commit SHA, not a branch name, so installs only
# change when this line is edited. To update: push to scully-eye2bids, run
#   git rev-parse scully-eye2bids
# and paste the 40-character SHA here.
# Switch to bids-standard/eye2bids (and a release tag or commit) once all
# fixes are merged upstream.
EYE2BIDS_REPO="https://github.com/mrribbits/eye2bids.git"
EYE2BIDS_REF="2f048446a301cf569a4db328feaae2206a2847b6"

# URL of the Scully MEG metadata file (scully-config branch of the fork);
# set METADATA_URL="" to skip this step
METADATA_URL="${METADATA_URL-https://raw.githubusercontent.com/mrribbits/eye2bids/scully-config/eyetracking/eyelink_MEG_metadata.yml}"

# macOS only: full path to edf2asc, if it isn't on your PATH
EDF2ASC="${EDF2ASC:-}"

# Linux only: SR Research apt repository (edf2asc lives here)
SR_REPO="https://apt.sr-research.com"
SR_PACKAGES="eyelink-edf2asc eyelink-edfapi"   # edf2asc needs the EDF Access API library

# ============================================================

# Refuse anything but a full commit SHA, so installs are reproducible
if [[ ! "$EYE2BIDS_REF" =~ ^[0-9a-f]{40}$ ]]; then
    echo "ERROR: EYE2BIDS_REF must be a full 40-character commit SHA (got '$EYE2BIDS_REF')" >&2
    exit 1
fi

OS="$(uname -s)"
case "$OS" in
    Linux|Darwin) ;;
    *) echo "ERROR: unsupported system '$OS' (Linux or macOS only)" >&2; exit 1 ;;
esac

# ------------------------------------------------------------
# 1a. macOS: find the edf2asc from the EyeLink Developers Kit
# ------------------------------------------------------------
# Checked first, so nothing is installed if it's missing.
if [[ "$OS" == "Darwin" ]]; then
    if [[ -z "$EDF2ASC" ]]; then
        EDF2ASC="$(command -v edf2asc || true)"
    fi
    if [[ -z "$EDF2ASC" || ! -x "$EDF2ASC" ]]; then
        cat >&2 <<'MSG'
ERROR: edf2asc not found.

On macOS, install the EyeLink Developers Kit first:
  1. Log in to the SR Research support forum (https://www.sr-research.com/support/)
  2. Download and run the EyeLink Developers Kit installer for macOS
  3. Open a new terminal and check:  which edf2asc

If edf2asc is installed but not on your PATH, give its location:
  EDF2ASC=/path/to/edf2asc bash install_eye2bids.sh
MSG
        exit 1
    fi
    echo "==> Using edf2asc at $EDF2ASC"
fi

mkdir -p "$INSTALL_DIR"/{bin,lib,tmp}
cd "$INSTALL_DIR/tmp"

# ------------------------------------------------------------
# 1b. Linux: EyeLink edf2asc from the Developers Kit apt repo
# ------------------------------------------------------------
# SR Research only ships .deb packages. Instead of apt/sudo, we download
# the .debs and unpack them into INSTALL_DIR.
if [[ "$OS" == "Linux" ]]; then
    case "$(uname -m)" in
        x86_64)        ARCH=amd64 ;;
        aarch64|arm64) ARCH=arm64 ;;
        *) echo "ERROR: unsupported CPU '$(uname -m)'" >&2; exit 1 ;;
    esac

    # Read the repo layout (suite and component) from SR Research's own
    # apt config file, so this keeps working if they rename things.
    echo "==> Reading SR Research repo configuration"
    curl -fsSL "$SR_REPO/SR_Research_repo.sources" -o repo.sources
    SR_SUITE=$(awk '/^Suites:/ {print $2; exit}' repo.sources)
    SR_COMPONENT=$(awk '/^Components:/ {print $2; exit}' repo.sources)
    INDEX_URL="$SR_REPO/dists/$SR_SUITE/$SR_COMPONENT/binary-$ARCH"

    echo "==> Downloading EyeLink package index ($INDEX_URL)"
    if curl -fsSL "$INDEX_URL/Packages.gz" -o Packages.gz; then
        gunzip -f Packages.gz
    else
        curl -fsSL "$INDEX_URL/Packages" -o Packages
    fi

    for pkg in $SR_PACKAGES; do
        # Find this package's .deb path in the index, picking the highest version
        deb_path=$(awk -v p="$pkg" '
            /^Package: /  { cur = $2 }
            /^Version: /  && cur == p { ver = $2 }
            /^Filename: / && cur == p { print ver, $2 }' Packages \
            | sort -V | tail -1 | cut -d" " -f2)
        if [[ -z "$deb_path" ]]; then
            echo "ERROR: package '$pkg' not found in the SR Research index" >&2
            exit 1
        fi

        echo "==> Downloading $pkg ($deb_path)"
        curl -fsSL "$SR_REPO/$deb_path" -o "$pkg.deb"

        # A .deb is an 'ar' archive; the files are inside data.tar.*
        mkdir -p "unpack_$pkg" && cd "unpack_$pkg"
        ar x "../$pkg.deb"
        tar -xf data.tar.*          # .zst needs zstd; xz/gz work with plain tar
        cd ..
    done

    # Copy the executable and shared libraries into INSTALL_DIR
    find unpack_* -type f -name edf2asc -exec cp {} "$INSTALL_DIR/bin/" \;
    find unpack_* \( -type f -o -type l \) -name "*.so*" -exec cp -P {} "$INSTALL_DIR/lib/" \;
    chmod +x "$INSTALL_DIR/bin/edf2asc"
else
    # macOS: link the Developers Kit's edf2asc into INSTALL_DIR/bin, so
    # eye2bids finds it even if the kit's folder isn't on PATH
    ln -sf "$EDF2ASC" "$INSTALL_DIR/bin/edf2asc"
fi

# ------------------------------------------------------------
# 2. eye2bids from the fork, into its own virtual environment
# ------------------------------------------------------------
echo "==> Creating Python environment"
"$PYTHON" -m venv "$INSTALL_DIR/venv"
"$INSTALL_DIR/venv/bin/pip" install --quiet --upgrade pip
echo "==> Installing eye2bids from $EYE2BIDS_REPO@$EYE2BIDS_REF"
"$INSTALL_DIR/venv/bin/pip" install --quiet "git+$EYE2BIDS_REPO@$EYE2BIDS_REF"

# ------------------------------------------------------------
# 3. Facility metadata file
# ------------------------------------------------------------
if [[ -n "$METADATA_URL" ]]; then
    echo "==> Downloading metadata file"
    curl -fsSL "$METADATA_URL" -o "$INSTALL_DIR/eyelink_MEG_metadata.yml"
else
    echo "==> METADATA_URL not set; skipping metadata download"
fi

# ------------------------------------------------------------
# Environment file: puts eye2bids and edf2asc on PATH
# ------------------------------------------------------------
cat > "$INSTALL_DIR/eye2bids_env.sh" <<EOF
# Source this file before using eye2bids:  source $INSTALL_DIR/eye2bids_env.sh
export PATH="$INSTALL_DIR/bin:$INSTALL_DIR/venv/bin:\$PATH"
EOF
if [[ "$OS" == "Linux" ]]; then
    cat >> "$INSTALL_DIR/eye2bids_env.sh" <<EOF
export LD_LIBRARY_PATH="$INSTALL_DIR/lib\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}"
EOF
fi

cd "$INSTALL_DIR"            # step out of tmp before deleting it
rm -rf "$INSTALL_DIR/tmp"

# ------------------------------------------------------------
# Quick check
# ------------------------------------------------------------
echo "==> Checking install"
source "$INSTALL_DIR/eye2bids_env.sh"
if [[ "$OS" == "Linux" ]] && ldd "$INSTALL_DIR/bin/edf2asc" | grep -q "not found"; then
    echo "WARNING: edf2asc is missing libraries:" >&2
    ldd "$INSTALL_DIR/bin/edf2asc" | grep "not found" >&2
fi
edf2asc 2>&1 | head -2 || true   # prints version; exits non-zero without input
eye2bids --version

echo
echo "Done. In each new shell run:"
echo "  source $INSTALL_DIR/eye2bids_env.sh"
