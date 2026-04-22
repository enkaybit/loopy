#!/usr/bin/env bash
set -euo pipefail

if ! command -v temporal >/dev/null 2>&1; then
  echo "MISSING: temporal CLI" >&2
  exit 1
fi

temporal server start-dev
