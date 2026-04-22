#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

UNINSTALL=0
SKIP_CLAUDE=0
SKIP_CODEX=0
SKIP_GEMINI=0

echo "Note: This will overwrite existing loopy files in the target locations."

for arg in "$@"; do
  case "$arg" in
    --uninstall) UNINSTALL=1 ;;
    --no-claude) SKIP_CLAUDE=1 ;;
    --no-codex) SKIP_CODEX=1 ;;
    --no-gemini) SKIP_GEMINI=1 ;;
    *)
      echo "Unknown option: $arg" >&2
      echo "Usage: $0 [--uninstall] [--no-claude] [--no-codex] [--no-gemini]" >&2
      exit 1
      ;;
  esac
  shift || true
 done

CLAUDE_HOME="${CLAUDE_HOME:-$HOME/.claude}"
CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
GEMINI_HOME="${GEMINI_HOME:-$HOME/.gemini}"
LOOPY_TASK_BIN_DIR="${LOOPY_TASK_BIN_DIR:-$HOME/.local/bin}"

CLAUDE_PLUGIN_DIR="$CLAUDE_HOME/plugins/loopy"
CODEX_SKILLS_DIR="$CODEX_HOME/skills"
GEMINI_SKILLS_DIR="$GEMINI_HOME/skills"
GEMINI_COMMANDS_DIR="$GEMINI_HOME/commands"

sync_dir() {
  local src="$1"
  local dst="$2"

  if command -v rsync >/dev/null 2>&1; then
    mkdir -p "$dst"
    rsync -a --delete "$src/" "$dst/"
  else
    rm -rf "$dst"
    mkdir -p "$dst"
    cp -R "$src/." "$dst/"
  fi
}

install_claude() {
  if [ "$UNINSTALL" -eq 1 ]; then
    rm -rf "$CLAUDE_PLUGIN_DIR"
    echo "Removed Claude Code plugin: $CLAUDE_PLUGIN_DIR"
    return
  fi

  mkdir -p "$CLAUDE_PLUGIN_DIR"
  sync_dir "$ROOT/.claude-plugin" "$CLAUDE_PLUGIN_DIR/.claude-plugin"
  sync_dir "$ROOT/agents" "$CLAUDE_PLUGIN_DIR/agents"
  sync_dir "$ROOT/skills" "$CLAUDE_PLUGIN_DIR/skills"
  echo "Installed Claude Code plugin to: $CLAUDE_PLUGIN_DIR"
}

install_codex() {
  if [ "$UNINSTALL" -eq 1 ]; then
    for dir in "$ROOT/skills"/*; do
      [ -d "$dir" ] || continue
      rm -rf "$CODEX_SKILLS_DIR/$(basename "$dir")"
    done
    echo "Removed Codex skills from: $CODEX_SKILLS_DIR"
    return
  fi

  mkdir -p "$CODEX_SKILLS_DIR"
  for dir in "$ROOT/skills"/*; do
    [ -d "$dir" ] || continue
    sync_dir "$dir" "$CODEX_SKILLS_DIR/$(basename "$dir")"
  done
  echo "Installed Codex skills to: $CODEX_SKILLS_DIR"
}

install_gemini() {
  if [ "$UNINSTALL" -eq 1 ]; then
    for dir in "$ROOT/skills"/*; do
      [ -d "$dir" ] || continue
      rm -rf "$GEMINI_SKILLS_DIR/$(basename "$dir")"
    done
    rm -f "$GEMINI_COMMANDS_DIR/browse.toml"
    echo "Removed Gemini skills from: $GEMINI_SKILLS_DIR"
    return
  fi

  mkdir -p "$GEMINI_SKILLS_DIR"
  for dir in "$ROOT/skills"/*; do
    [ -d "$dir" ] || continue
    sync_dir "$dir" "$GEMINI_SKILLS_DIR/$(basename "$dir")"
  done

  mkdir -p "$GEMINI_COMMANDS_DIR"
  cat > "$GEMINI_COMMANDS_DIR/browse.toml" <<EOF
description = "Use agent-browser for browser-grounded browsing, extraction, screenshots, and web app interaction."
prompt = """
Use \`agent-browser\` as your browser automation layer for this task.

Follow this installed guide:
@{$GEMINI_SKILLS_DIR/loopy-browse/SKILL.md}

Execution rules:
- Ground your work in live page state rather than model memory.
- Prefer \`snapshot -i\`, refs like \`@e1\`, and explicit waits.
- Re-snapshot after navigation or significant DOM changes.
- Use screenshots when visual confirmation matters.
- Summarize the important results instead of dumping large raw snapshots verbatim.

If the user invoked /browse with arguments, the raw command text is appended below. Treat that appended text as the specific browser task to carry out.
"""
EOF
  echo "Installed Gemini skills to: $GEMINI_SKILLS_DIR"
}

install_loopy_cli() {
  # The `loopy` helper CLI is pure-Python stdlib — installed as a symlink/copy
  # into LOOPY_TASK_BIN_DIR so it is on PATH alongside the task binaries.
  if [ "$UNINSTALL" -eq 1 ]; then
    rm -f "$LOOPY_TASK_BIN_DIR/loopy"
    echo "Removed loopy CLI from: $LOOPY_TASK_BIN_DIR"
    return
  fi

  if ! command -v python3 >/dev/null 2>&1; then
    echo "WARN: python3 not found; skipping loopy CLI install"
    return
  fi

  mkdir -p "$LOOPY_TASK_BIN_DIR"
  # Copy (not symlink) so the binary keeps working if the checkout moves.
  cp "$ROOT/tools/loopy-cli/loopy" "$LOOPY_TASK_BIN_DIR/loopy"
  chmod +x "$LOOPY_TASK_BIN_DIR/loopy"
  echo "Installed loopy CLI to: $LOOPY_TASK_BIN_DIR/loopy"
}

install_temporal_tools() {
  if [ "$UNINSTALL" -eq 1 ]; then
    rm -f "$LOOPY_TASK_BIN_DIR/loopy-taskd" "$LOOPY_TASK_BIN_DIR/loopy-tasks"
    echo "Removed loopy task binaries from: $LOOPY_TASK_BIN_DIR"
    return
  fi

  if ! command -v go >/dev/null 2>&1; then
    echo "WARN: go not found; skipping loopy-taskd/loopy-tasks build"
    return
  fi

  mkdir -p "$LOOPY_TASK_BIN_DIR"
  (cd "$ROOT/tools/loopy-taskd" && go build -o "$LOOPY_TASK_BIN_DIR/loopy-taskd" ./cmd/loopy-taskd)
  (cd "$ROOT/tools/loopy-taskd" && go build -o "$LOOPY_TASK_BIN_DIR/loopy-tasks" ./cmd/loopy-tasks)
  echo "Installed loopy task binaries to: $LOOPY_TASK_BIN_DIR"
}

if [ "$SKIP_CLAUDE" -eq 0 ]; then
  install_claude
fi

if [ "$SKIP_CODEX" -eq 0 ]; then
  install_codex
fi

if [ "$SKIP_GEMINI" -eq 0 ]; then
  install_gemini
fi

install_loopy_cli
install_temporal_tools

if [ "$UNINSTALL" -eq 1 ]; then
  echo "Uninstall complete."
else
  echo "Install complete."
fi
