#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

TMP_ROOT="$(mktemp -d)"
cleanup() {
  rm -rf "$TMP_ROOT"
}
trap cleanup EXIT

export CLAUDE_HOME="$TMP_ROOT/.claude"
export CODEX_HOME="$TMP_ROOT/.codex"
export GEMINI_HOME="$TMP_ROOT/.gemini"
export LOOPY_TASK_BIN_DIR="$TMP_ROOT/.local/bin"
GEMINI_COMMAND_FILE="$GEMINI_HOME/commands/browse.toml"

# Install into temp homes
"$ROOT/scripts/install.sh"

# Verify install (should pass; gh/agent-browser are optional)
"$ROOT/scripts/verify.sh"

# Uninstall
"$ROOT/scripts/install.sh" --uninstall

# Confirm removal
if [ -d "$CLAUDE_HOME/plugins/loopy" ]; then
  echo "FAILED: Claude plugin still present after uninstall" >&2
  exit 1
fi

for dir in "$ROOT/skills"/*; do
  [ -d "$dir" ] || continue
  name="$(basename "$dir")"
  if [ -d "$CODEX_HOME/skills/$name" ]; then
    echo "FAILED: Codex skill $name still present after uninstall" >&2
    exit 1
  fi
  if [ -d "$GEMINI_HOME/skills/$name" ]; then
    echo "FAILED: Gemini skill $name still present after uninstall" >&2
    exit 1
  fi
 done

if [ -f "$GEMINI_COMMAND_FILE" ]; then
  echo "FAILED: Gemini browse command still present after uninstall" >&2
  exit 1
fi

# Test SKIP flag parsing (comma-separated)
SKIP=claude,codex make install

if [ -d "$CLAUDE_HOME/plugins/loopy" ]; then
  echo "FAILED: Claude plugin installed despite SKIP=claude,codex" >&2
  exit 1
fi

for dir in "$ROOT/skills"/*; do
  [ -d "$dir" ] || continue
  name="$(basename "$dir")"
  if [ -d "$CODEX_HOME/skills/$name" ]; then
    echo "FAILED: Codex skill $name installed despite SKIP=claude,codex" >&2
    exit 1
  fi
  if [ ! -d "$GEMINI_HOME/skills/$name" ]; then
    echo "FAILED: Gemini skill $name missing with SKIP=claude,codex" >&2
    exit 1
  fi
done

if [ ! -f "$GEMINI_COMMAND_FILE" ]; then
  echo "FAILED: Gemini browse command missing with SKIP=claude,codex" >&2
  exit 1
fi

SKIP=claude,codex make uninstall

for dir in "$ROOT/skills"/*; do
  [ -d "$dir" ] || continue
  name="$(basename "$dir")"
  if [ -d "$GEMINI_HOME/skills/$name" ]; then
    echo "FAILED: Gemini skill $name still present after SKIP=claude,codex uninstall" >&2
    exit 1
  fi
done

if [ -f "$GEMINI_COMMAND_FILE" ]; then
  echo "FAILED: Gemini browse command still present after SKIP=claude,codex uninstall" >&2
  exit 1
fi

# Run the loopy CLI's own test suite (uses only stdlib + bash).
if command -v python3 >/dev/null 2>&1; then
  echo
  echo "Running loopy-cli unit tests…"
  "$ROOT/tools/loopy-cli/tests/run_tests.sh"
  echo
  echo "Running loopy-cli end-to-end demo…"
  "$ROOT/tools/loopy-cli/tests/e2e_demo.sh"
  echo
  echo "Running loopy-cli deep / edge-case tests…"
  "$ROOT/tools/loopy-cli/tests/deep_tests.sh"
else
  echo "WARN: python3 not found; skipping loopy-cli tests" >&2
fi

echo "Tests PASSED"
