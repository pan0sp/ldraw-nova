#!/bin/bash
# Setup script for a Claude Code cloud environment (claude.ai/code).
# Paste this file's contents into: environment menu in the session title bar > Edit > Setup script.
# Also add  LDRAW_DIR=/opt/ldraw  under Environment variables, and allow library.ldraw.org
# in Network access.
#
# It installs pdftotext, LeoCAD and Xvfb, and downloads the LDraw parts library to /opt/ldraw.
# It does not depend on the repository, so it works whether or not the clone exists yet.
set -euo pipefail

apt-get update -q
DEBIAN_FRONTEND=noninteractive apt-get install -y -q poppler-utils leocad xvfb unzip

if [ ! -f /opt/ldraw/parts/3001.dat ]; then
  tmp=$(mktemp -d)
  curl -fsSL --retry 3 -o "$tmp/complete.zip" https://library.ldraw.org/library/updates/complete.zip
  unzip -q "$tmp/complete.zip" -d "$tmp"
  rm -rf /opt/ldraw
  mv "$tmp/ldraw" /opt/ldraw
  rm -rf "$tmp"
fi

# Fallback for shells that don't get the environment variable.
grep -qsF 'export LDRAW_DIR=/opt/ldraw' ~/.bashrc || echo 'export LDRAW_DIR=/opt/ldraw' >> ~/.bashrc

# If the repository is already cloned, install its Python packages too.
# Otherwise run ./setup.sh once in the session; it takes about ten seconds.
for repo in /home/user/ldraw-nova "$PWD"; do
  if [ -x "$repo/setup.sh" ] && [ -f "$repo/pyproject.toml" ]; then
    (cd "$repo" && LDRAW_DIR=/opt/ldraw ./setup.sh >/dev/null) && echo "Python environment ready in $repo"
    break
  fi
done
