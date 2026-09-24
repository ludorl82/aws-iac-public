#!/usr/bin/env bash
# Build the numeriseur Lambda package.
#
# Must run before `tofu plan` -- the archive_file data source zips .build/pkg,
# and a missing directory is a plan-time error rather than a helpful message.
# Both GitHub Actions workflows run this; from the console shell, run it by hand.
#
# Pillow is the only dependency and the only reason this script exists: the
# wheel has to match Lambda's platform, not the machine doing the build, hence
# --platform/--only-binary. Everything else the handler needs (urllib, boto3) is
# in the runtime already.
set -euo pipefail

cd "$(dirname "$0")"

RUNTIME_PYTHON=3.13
PLATFORM=manylinux2014_aarch64 # matches architectures = ["arm64"] in numeriseur.tf

rm -rf .build/pkg
mkdir -p .build/pkg

# `python3 -m pip`, not `pip`: the GitHub runner and the console shell do not
# agree on whether a bare `pip` is on PATH. The flags below mean the build
# machine's own Python and architecture are irrelevant — only the wheel tags
# matter — so this produces an identical package on the Pi and on the runner.
python3 -m pip install \
  --quiet \
  --platform "$PLATFORM" \
  --python-version "$RUNTIME_PYTHON" \
  --implementation cp \
  --only-binary=:all: \
  --target .build/pkg \
  -r requirements.txt

cp handler.py .build/pkg/

# Trim what the runtime will never read. Not about the 250 MB unzipped limit --
# the package is nowhere near it -- but a smaller artifact makes the plan diff
# on a dependency bump readable.
find .build/pkg -name '__pycache__' -type d -prune -exec rm -rf {} +
find .build/pkg -name '*.dist-info' -type d -prune -exec rm -rf {} +

# Normalise permissions so the zip is reproducible.
#
# This matters more than it looks. archive_file normalises mtimes but bakes the
# permission bits of every file into the archive, so the package hash depends on
# the umask of whoever ran pip. A build here (umask 002 -> 664) and a build on
# the GitHub runner (umask 022 -> 644) would otherwise produce different
# source_code_hash values for identical code, and whichever machine did not
# apply last would see `tofu plan` propose a code update forever. That is how
# a drift check ends up permanently red, which teaches you nothing.
#
# deadman has exactly this problem today -- see README.
find .build/pkg -type f -exec chmod 0644 {} +
find .build/pkg -type d -exec chmod 0755 {} +

echo "built .build/pkg ($(du -sh .build/pkg | cut -f1))"
