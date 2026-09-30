#!/usr/bin/env bash
# install_eye2bids.sh
# Installs eye2bids (patched fork) plus SR Research's edf2asc, without sudo.
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

# eye2bids source: the fork with the remote-mode RECCFG fix.
# Replace the branch name with a commit SHA to pin an exact version.
# Switch to bids-standard/eye2bids once the fix is merged upstream.
EYE2BIDS_REPO="https://github.com/mrribbits/eye2bids.git"
EYE2BIDS_REF="fix-remote-reccfg-eye"

# URL of the Scully MEG metadata file (scully-config branch of the fork);
# set METADATA_URL="" to skip this step
METADATA_URL="${METADATA_URL-https://raw.githubusercontent.com/mrribbits/eye2bids/scully-config/eyetracking/eyelink_MEG_metadata.yml}"

# SR Research apt repository (edf2asc lives here)
SR_REPO="https://apt.sr-research.com"
SR_PACKAGES="eyelink-edf2asc eyelink-edfapi"   # edf2asc needs the EDF Access API library

# ============================================================

mkdir -p "$INSTALL_DIR"/{bin,lib,tmp}
cd "$INSTALL_DIR/tmp"

# ------------------------------------------------------------
# 1. EyeLink edf2asc (from the Developers Kit apt repo)
# ------------------------------------------------------------
# SR Research only ships .deb packages. Instead of apt/sudo, we download
# the .debs and unpack them into INSTALL_DIR.

# Read the repo layout (suite and component) from SR Research's own
# apt config file, so this keeps working if they rename things.
echo "==> Reading SR Research repo configuration"
curl -fsSL "$SR_REPO/SR_Research_repo.sources" -o repo.sources
SR_SUITE=$(awk '/^Suites:/ {print $2; exit}' repo.sources)
SR_COMPONENT=$(awk '/^Components:/ {print $2; exit}' repo.sources)
INDEX_URL="$SR_REPO/dists/$SR_SUITE/$SR_COMPONENT/binary-amd64"

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
export LD_LIBRARY_PATH="$INSTALL_DIR/lib\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}"
EOF

rm -rf "$INSTALL_DIR/tmp"

# ------------------------------------------------------------
# Quick check
# ------------------------------------------------------------
echo "==> Checking install"
source "$INSTALL_DIR/eye2bids_env.sh"
if ldd "$INSTALL_DIR/bin/edf2asc" | grep -q "not found"; then
    echo "WARNING: edf2asc is missing libraries:" >&2
    ldd "$INSTALL_DIR/bin/edf2asc" | grep "not found" >&2
fi
edf2asc 2>&1 | head -2 || true   # prints version; exits non-zero without input
eye2bids --version

echo
echo "Done. In each new shell run:"
echo "  source $INSTALL_DIR/eye2bids_env.sh"
