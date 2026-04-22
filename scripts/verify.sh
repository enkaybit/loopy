#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

SKIP_CLAUDE=0
SKIP_CODEX=0
SKIP_GEMINI=0

for arg in "$@"; do
  case "$arg" in
    --no-claude) SKIP_CLAUDE=1 ;;
    --no-codex) SKIP_CODEX=1 ;;
    --no-gemini) SKIP_GEMINI=1 ;;
    *)
      echo "Unknown option: $arg" >&2
      echo "Usage: $0 [--no-claude] [--no-codex] [--no-gemini]" >&2
      exit 1
      ;;
  esac
  shift || true
 done

CLAUDE_HOME="${CLAUDE_HOME:-$HOME/.claude}"
CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
GEMINI_HOME="${GEMINI_HOME:-$HOME/.gemini}"

CLAUDE_PLUGIN_DIR="$CLAUDE_HOME/plugins/loopy"
CODEX_SKILLS_DIR="$CODEX_HOME/skills"
GEMINI_SKILLS_DIR="$GEMINI_HOME/skills"
GEMINI_COMMANDS_DIR="$GEMINI_HOME/commands"

fail=0

check_cmd() {
  local cmd="$1"
  local required="$2"

  if command -v "$cmd" >/dev/null 2>&1; then
    echo "OK: $cmd"
  else
    if [ "$required" = "required" ]; then
      echo "MISSING: $cmd (required)" >&2
      fail=1
    else
      echo "WARN: $cmd (optional)" >&2
    fi
  fi
}

check_dir() {
  local path="$1"
  local label="$2"

  if [ -d "$path" ]; then
    echo "OK: $label at $path"
  else
    echo "MISSING: $label at $path" >&2
    fail=1
  fi
}

check_file() {
  local path="$1"
  local label="$2"

  if [ -f "$path" ]; then
    echo "OK: $label at $path"
  else
    echo "MISSING: $label at $path" >&2
    fail=1
  fi
}

check_cmd git required
check_cmd gh optional
check_cmd agent-browser optional
check_cmd temporal optional
check_cmd loopy-taskd optional
check_cmd loopy-tasks optional
check_cmd loopy optional

# Smoke test: validator runs on bundled fixtures (if CLI is present).
if command -v loopy >/dev/null 2>&1; then
  if loopy validate prd "$ROOT/tools/loopy-cli/tests/fixtures/prd-valid.md" >/dev/null 2>&1 \
     && loopy validate plan "$ROOT/tools/loopy-cli/tests/fixtures/plan-valid.md" >/dev/null 2>&1; then
    echo "OK: loopy validator smoke test"
  else
    echo "WARN: loopy validator smoke test failed" >&2
  fi
fi

declare -a expected_skills
for dir in "$ROOT/skills"/*; do
  [ -d "$dir" ] || continue
  expected_skills+=("$(basename "$dir")")
 done

if [ "$SKIP_CLAUDE" -eq 0 ]; then
  check_dir "$CLAUDE_PLUGIN_DIR" "Claude plugin"
  check_file "$CLAUDE_PLUGIN_DIR/.claude-plugin/marketplace.json" "Claude marketplace.json"
  check_dir "$CLAUDE_PLUGIN_DIR/agents" "Claude agents"
  check_dir "$CLAUDE_PLUGIN_DIR/skills" "Claude skills"
  for skill in "${expected_skills[@]}"; do
    if [ ! -d "$CLAUDE_PLUGIN_DIR/skills/$skill" ]; then
      echo "MISSING: Claude skill $skill" >&2
      fail=1
    fi
  done
fi

if [ "$SKIP_CODEX" -eq 0 ]; then
  check_dir "$CODEX_SKILLS_DIR" "Codex skills directory"
  for skill in "${expected_skills[@]}"; do
    if [ ! -d "$CODEX_SKILLS_DIR/$skill" ]; then
      echo "MISSING: Codex skill $skill" >&2
      fail=1
    fi
  done
fi

if [ "$SKIP_GEMINI" -eq 0 ]; then
  check_dir "$GEMINI_SKILLS_DIR" "Gemini skills directory"
  check_dir "$GEMINI_COMMANDS_DIR" "Gemini commands directory"
  check_file "$GEMINI_COMMANDS_DIR/browse.toml" "Gemini browse command"
  for skill in "${expected_skills[@]}"; do
    if [ ! -d "$GEMINI_SKILLS_DIR/$skill" ]; then
      echo "MISSING: Gemini skill $skill" >&2
      fail=1
    fi
  done
fi

if [ "$fail" -eq 1 ]; then
  echo "Verify FAILED" >&2
  exit 1
fi

echo "Verify PASSED"
echo "Next: try /loopy-requirements or /loopy-plan in your CLI"
