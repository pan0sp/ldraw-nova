#!/usr/bin/env bash
# One-step install of the ldraw-nova toolkit (no Docker) on macOS or Linux.
#
#   scripts/bootstrap.sh [--library DIR] [--no-system] [--no-persist] [--update-library]
#
#   --library DIR      where the LDraw parts library lives (default: $LDRAW_HOME or ~/ldraw-lib)
#   --no-system        skip installing LeoCAD, pdftotext and Xvfb with brew/apt
#   --no-persist       don't add LDRAW_DIR to your shell profile
#   --update-library   re-download the parts library even if one is present
#
# Safe to run again: every step is skipped when it is already done.
set -euo pipefail

repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
lib_root=${LDRAW_HOME:-$HOME/ldraw-lib}
system=1 persist=1 update=0
while [ $# -gt 0 ]; do
  case "$1" in
    --library) lib_root=$2; shift ;;
    --no-system) system=0 ;;
    --no-persist) persist=0 ;;
    --update-library) update=1 ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done
library="$lib_root/ldraw"
say() { printf '\n==> %s\n' "$*"; }

# ---- 1. System tools: pdftotext (required), LeoCAD and Xvfb (for rendering) ----
if [ "$system" = 1 ]; then
  case "$(uname -s)" in
    Darwin)
      if ! command -v brew >/dev/null 2>&1; then
        echo 'Homebrew is needed for pdftotext and LeoCAD: https://brew.sh' >&2; exit 1
      fi
      say 'Installing pdftotext and LeoCAD with Homebrew'
      command -v pdftotext >/dev/null 2>&1 || brew install poppler
      [ -d /Applications/LeoCAD.app ] || brew install --cask leocad
      # The toolkit calls `leocad` from PATH; the cask only installs the app bundle.
      if ! command -v leocad >/dev/null 2>&1 && [ -x /Applications/LeoCAD.app/Contents/MacOS/LeoCAD ]; then
        ln -sf /Applications/LeoCAD.app/Contents/MacOS/LeoCAD "$(brew --prefix)/bin/leocad"
      fi
      ;;
    Linux)
      if command -v apt-get >/dev/null 2>&1; then
        sudo=''; [ "$(id -u)" -eq 0 ] || sudo='sudo'
        missing=''
        command -v pdftotext >/dev/null 2>&1 || missing="$missing poppler-utils"
        command -v leocad >/dev/null 2>&1 || missing="$missing leocad"
        command -v xvfb-run >/dev/null 2>&1 || missing="$missing xvfb"
        command -v unzip >/dev/null 2>&1 || missing="$missing unzip"
        if [ -n "$missing" ]; then
          say "Installing$missing with apt"
          $sudo apt-get update -q
          DEBIAN_FRONTEND=noninteractive $sudo apt-get install -y -q $missing
        fi
      else
        echo 'No apt-get: install pdftotext (poppler), unzip, LeoCAD and Xvfb with your package manager.' >&2
      fi
      ;;
  esac
fi
command -v pdftotext >/dev/null 2>&1 || { echo 'pdftotext is required (install poppler).' >&2; exit 1; }
command -v unzip >/dev/null 2>&1 || { echo 'unzip is required.' >&2; exit 1; }

# ---- 2. LDraw parts library (~150 MB download, ~500 MB unpacked) ----
if [ "$update" = 1 ] || [ ! -f "$library/parts/3001.dat" ]; then
  say "Downloading the LDraw parts library into $library"
  mkdir -p "$lib_root"
  work=$(mktemp -d "$lib_root/.download.XXXXXX")
  trap 'rm -rf "$work"' EXIT
  curl -fsSL --retry 3 -o "$work/complete.zip" https://library.ldraw.org/library/updates/complete.zip
  unzip -q "$work/complete.zip" -d "$work/unpacked"
  [ -f "$work/unpacked/ldraw/parts/3001.dat" ] || { echo 'Download did not contain ldraw/parts.' >&2; exit 1; }
  rm -rf "$library"
  mv "$work/unpacked/ldraw" "$library"
else
  say "LDraw parts library already at $library"
fi
export LDRAW_DIR="$library"

# ---- 3. Python environment, index and self-check (the repo's own setup.sh) ----
say 'Installing Python packages and indexing the library'
command -v uv >/dev/null 2>&1 || echo 'Tip: install uv (https://docs.astral.sh/uv/) for a faster, locked install. Falling back to python3 -m venv (needs Python 3.12+).'
"$repo/setup.sh" >/dev/null

# ---- 4. Remember LDRAW_DIR for new shells ----
if [ "$persist" = 1 ]; then
  line="export LDRAW_DIR=\"$library\""
  for profile in "$HOME/.bashrc" "$HOME/.zshrc"; do
    case "$profile" in */.zshrc) [ "$(uname -s)" = Darwin ] || [ -f "$profile" ] || continue ;; esac
    if ! grep -qsF "$line" "$profile"; then
      printf '\n# ldraw-nova parts library\n%s\n' "$line" >> "$profile"
      echo "Added LDRAW_DIR to $profile"
    fi
  done
fi

say 'Done'
echo "LDRAW_DIR=$library"
command -v leocad >/dev/null 2>&1 && echo 'Rendering: available (on a Linux server without a display, prefix commands with xvfb-run -a).' \
  || echo 'Rendering: LeoCAD not found, so ./ldraw-agent render will not work.'
echo "Try: cd \"$repo\" && ./ldraw-agent search parts \"brick 2 x 4\" --limit 3"
