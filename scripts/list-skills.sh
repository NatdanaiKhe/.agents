#!/usr/bin/env bash
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"

cd "$REPO"
find -L skills -mindepth 2 -maxdepth 2 -name SKILL.md \
  -not -path '*/node_modules/*' |
  sed 's|/SKILL.md$||' |
  sort
