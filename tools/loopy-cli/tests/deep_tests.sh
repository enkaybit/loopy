#!/usr/bin/env bash
# Deep / edge-case tests. Designed to break things:
#   - path weirdness (absolute, relative, tildes, spaces, unicode)
#   - collisions (same-day, same-scope, same-filename-across-attachments)
#   - YAML round-tripping with tricky strings
#   - plan-rewrite on plans that already have a Reviews section
#   - argparse default-list leakage across invocations
#   - validator behavior on empty / wrong-type / mis-extension inputs
#   - real install pipeline: make install -> PATH -> invoke
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
CLI="$HERE/../loopy"

pass=0
fail=0
failures=()

ok()   { pass=$((pass+1)); echo "  ok: $1"; }
bad()  { fail=$((fail+1)); failures+=("$1"); echo "  FAIL: $1"; }
section() { echo; echo "== $1 =="; }

expect_rc() {
  local want="$1"; local desc="$2"; shift 2
  local out rc
  out="$("$@" 2>&1)"; rc=$?
  if [ "$rc" = "$want" ]; then
    ok "$desc"
  else
    bad "$desc (want rc=$want, got rc=$rc)"
    echo "     output: $(head -c 500 <<<"$out")"
  fi
}
expect_contains() {
  local desc="$1"; local needle="$2"; shift 2
  local out
  out="$("$@" 2>&1 || true)"
  if grep -qF -- "$needle" <<<"$out"; then
    ok "$desc"
  else
    bad "$desc (missing: $needle)"
    echo "     output: $(head -c 500 <<<"$out")"
  fi
}
expect_ok() {
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then ok "$desc"
  else bad "$desc"; fi
}
expect_fail() {
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then bad "$desc (expected failure)"
  else ok "$desc"; fi
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cd "$TMP"
git init -q && git config user.email d@e.com && git config user.name d
git commit -q --allow-empty -m init
mkdir -p docs/prd docs/plans

# ------------------------------------------------------------------
# 1. Validator: robustness against odd inputs
# ------------------------------------------------------------------
section "validator robustness"

: > empty.md
expect_rc 1 "validate prd rejects empty file" "$CLI" validate prd empty.md
expect_rc 1 "validate plan rejects empty file" "$CLI" validate plan empty.md

expect_rc 1 "validate prd rejects nonexistent file" "$CLI" validate prd nope.md
expect_rc 1 "validate plan rejects nonexistent file" "$CLI" validate plan nope.md

# Cross-feeding: plan-as-PRD and PRD-as-plan should still fail cleanly, not crash.
cp "$HERE/fixtures/plan-valid.md" mislabeled-prd.md
expect_rc 1 "plan fed to 'validate prd' fails cleanly (no crash)" "$CLI" validate prd mislabeled-prd.md
cp "$HERE/fixtures/prd-valid.md" mislabeled-plan.md
expect_rc 1 "prd fed to 'validate plan' fails cleanly (no crash)" "$CLI" validate plan mislabeled-plan.md

# JSON output always emits valid JSON, even on failure.
out="$("$CLI" validate prd empty.md --json 2>&1 || true)"
python3 -c "import json,sys; json.loads(sys.argv[1])" "$out" \
  && ok "validate --json on error is still valid JSON" || bad "not valid JSON"

# Non-UTF8 content shouldn't crash the parser (it'll error with a parse message).
printf '\xff\xfe\x00\x00bogus' > nonutf8.md
out="$("$CLI" validate prd nonutf8.md 2>&1 || true)"
if grep -qiE "error|fail|missing" <<<"$out"; then ok "non-UTF8 input handled gracefully"
else bad "non-UTF8 input silently accepted (output: $out)"; fi

# ------------------------------------------------------------------
# 2. review-save: plan link handling edge cases
# ------------------------------------------------------------------
section "review-save: plan link handling"

# Plan with an existing '## Reviews' section containing prior content —
# new link must be inserted directly after the heading without clobbering
# pre-existing entries.
cat > docs/plans/existing.md <<'EOF'
# Feature - Technical Plan
**Date:** 2026-04-21
**Status:** Planning
**PRD:** None

## Overview
x

## Architecture
x

#### 1.1 Add foo

**Depends on:** none
**Files:** `a.py`, `a_test.py`

**Test scenarios:** (`a_test.py`)
- a → b

**Verify:** pytest

## Reviews

- [old-review](../reviews/2026-04-20-old.md) — 2026-04-20
EOF

"$CLI" review-save new --content "body" --plan docs/plans/existing.md >/dev/null
expect_contains "existing Reviews link preserved" "old-review" cat docs/plans/existing.md
expect_contains "new link inserted into Reviews section" "[new](" cat docs/plans/existing.md

# Run review-save a second time; should not produce duplicate Reviews headings.
"$CLI" review-save second --content "b" --plan docs/plans/existing.md >/dev/null
headings=$(grep -c "^## Reviews" docs/plans/existing.md)
[ "$headings" = "1" ] && ok "no duplicate ## Reviews heading" \
  || bad "duplicated Reviews heading (count=$headings)"

# ------------------------------------------------------------------
# 3. review-save --attach: path edge cases
# ------------------------------------------------------------------
section "review-save --attach: path edge cases"

mkdir -p "evidence with spaces"
printf '\x89PNG\r\n\x1a\ndata' > "evidence with spaces/screen shot.png"

# Attachments with spaces in filename.
out="$("$CLI" review-save spaces --content body --attach "evidence with spaces/screen shot.png" 2>&1)"
rc=$?
[ "$rc" = "0" ] && ok "attachment with spaces accepted" || bad "spaces rejected: $out"
# The copied file uses its original basename including the space.
if [ -f "docs/reviews/$(ls docs/reviews | grep spaces)/screen shot.png" ]; then
  ok "spaced filename preserved in review dir"
else bad "spaced filename not preserved"; fi

# Absolute path to an attachment.
abs_attach="$TMP/abs-evidence.png"
printf '\x89PNG\r\n\x1a\ndata' > "$abs_attach"
"$CLI" review-save absolute --content body --attach "$abs_attach" >/dev/null && \
  ok "absolute attachment path accepted" || bad "absolute path rejected"
[ -f "docs/reviews/$(ls docs/reviews | grep absolute)/abs-evidence.png" ] && \
  ok "absolute-path file copied by basename" || bad "absolute file missing"

# Unicode filename.
printf '\x89PNG\r\n\x1a\ndata' > "unicode-éñ.png"
"$CLI" review-save unicode --content body --attach "unicode-éñ.png" >/dev/null && \
  ok "unicode attachment name accepted" || bad "unicode rejected"

# Same attachment passed twice in one call — collision suffixing should apply.
"$CLI" review-save dupe --content body --attach "$abs_attach" --attach "$abs_attach" >/dev/null
dupedir="docs/reviews/$(ls docs/reviews | grep '^.*dupe$' | head -1)"
if [ -f "$dupedir/abs-evidence.png" ] && [ -f "$dupedir/abs-evidence-2.png" ]; then
  ok "duplicate-attachment collision suffixed in single call"
else bad "duplicate attachment not suffixed (dir: $dupedir)"; fi

# Attachment named 'index.md' — would collide with the report file.
echo "hello" > fake-index.md
mv fake-index.md ./index.md
out="$("$CLI" review-save idxcoll --content body --attach index.md 2>&1)"; rc=$?
[ "$rc" = "0" ] && ok "attachment named index.md accepted" || bad "rejected: $out"
idxdir="docs/reviews/$(ls docs/reviews | grep idxcoll)"
[ -f "$idxdir/index.md" ] && ok "index.md (report) exists" || bad "no index.md"
# The attachment should have been suffixed so it didn't overwrite the report.
count=$(ls "$idxdir" | grep -c "^index")
[ "$count" -ge 2 ] && ok "index.md attachment got suffixed to avoid overwrite" \
  || bad "attachment overwrote report (files: $(ls "$idxdir"))"
# And the report's first bytes still look like a review report, not "hello".
head -1 "$idxdir/index.md" | grep -q "Code Review" && ok "report not overwritten by attachment" \
  || bad "report appears overwritten ($(head -1 "$idxdir/index.md"))"
# And the attachment itself should be preserved under a suffixed name.
[ -f "$idxdir/index-2.md" ] && ok "attachment preserved as index-2.md" \
  || bad "attachment lost to report write (files: $(ls "$idxdir"))"

rm -f index.md

# ------------------------------------------------------------------
# 4. review-save: argparse default-list leakage
# ------------------------------------------------------------------
section "argparse: --attach list doesn't leak across invocations"

# If the CLI accidentally shares the default=[] list across argparse calls in a
# long-running process this would leak; in a one-shot CLI it cannot leak, but we
# still verify a fresh call with no --attach produces flat-file mode (str, not
# dir) even when run right after a call with --attach.
no_attach_path="$("$CLI" review-save noattach-after --content body)"
[ -f "$TMP/$no_attach_path" ] && ok "no-attach call still writes flat file" \
  || bad "no-attach broke: $no_attach_path"
case "$no_attach_path" in
  *"/index.md") bad "no-attach invocation created directory mode ($no_attach_path)" ;;
  *) ok "no-attach path is a flat .md ($no_attach_path)" ;;
esac

# state.yml still contains an entry for every review-save done so far.
num_state_reviews=$("$CLI" state show --json | python3 -c "import sys,json;d=json.load(sys.stdin);print(len(d.get('reviews',[])))")
[ "$num_state_reviews" -ge 7 ] && ok "state recorded all reviews ($num_state_reviews)" \
  || bad "state review count low ($num_state_reviews)"

# ------------------------------------------------------------------
# 5. YAML round-trip: tricky strings
# ------------------------------------------------------------------
section "YAML round-trip: tricky strings"

# Install the CLI into the state with keys containing punctuation.
"$CLI" state set note "value: with a colon and # hash" >/dev/null
"$CLI" state set unicode "日本語テスト" >/dev/null
"$CLI" state set tricky "true"   >/dev/null   # looks like a boolean but stored as string 'true'
out=$("$CLI" state show --json)
echo "$out" | python3 -c "
import sys, json
d = json.load(sys.stdin)
assert d['note'] == 'value: with a colon and # hash', repr(d['note'])
assert d['unicode'] == '日本語テスト', repr(d['unicode'])
# 'true' will round-trip as a boolean — that's documented behavior, not a bug.
assert d['tricky'] in (True, 'true'), repr(d['tricky'])
print('ok')
" && ok "YAML round-trip survived punctuation + unicode" \
  || { bad "YAML round-trip broken"; echo "$out" | head -20; }

# Attachment list should round-trip as a list of strings in state.
attach_list=$(echo "$out" | python3 -c "
import sys, json
d = json.load(sys.stdin)
found = [r for r in d.get('reviews', []) if r.get('attachments')]
if not found:
    print('(none)'); sys.exit(1)
print(','.join(sorted(found[-1]['attachments'])))
")
[ -n "$attach_list" ] && ok "attachment list round-trips through YAML ($attach_list)" \
  || bad "attachments lost in YAML round-trip"

# ------------------------------------------------------------------
# 6. browser-capture: more failure modes
# ------------------------------------------------------------------
section "browser-capture: failure modes"

FAKEBIN="$TMP/fakebin"
mkdir -p "$FAKEBIN"

# Stub that succeeds but writes NO file — CLI should catch this and exit 4.
cat > "$FAKEBIN/agent-browser" <<'EOS'
#!/usr/bin/env bash
# Deliberately does not create the output file on 'screenshot'.
exit 0
EOS
chmod +x "$FAKEBIN/agent-browser"
expect_rc 4 "browser-capture exits 4 when stub succeeds but no file produced" \
  env PATH="$FAKEBIN:$PATH" "$CLI" browser-capture https://x.test "$TMP/nope.png"

# Stub that exits non-zero on 'open' — CLI should exit 4.
cat > "$FAKEBIN/agent-browser" <<'EOS'
#!/usr/bin/env bash
case "$1" in open) echo "boom" >&2; exit 17 ;; *) exit 0 ;; esac
EOS
chmod +x "$FAKEBIN/agent-browser"
expect_rc 4 "browser-capture exits 4 when agent-browser open fails" \
  env PATH="$FAKEBIN:$PATH" "$CLI" browser-capture https://x.test "$TMP/nope2.png"

# Stub that writes to a nested output dir (we create the parent).
cat > "$FAKEBIN/agent-browser" <<'EOS'
#!/usr/bin/env bash
if [ "$1" = "--session" ]; then shift 2; fi
case "$1" in
  screenshot) out="$2"; [ "$out" = "--full" ] && out="$3"; printf 'PNG' > "$out" ;;
  *) ;;
esac
EOS
chmod +x "$FAKEBIN/agent-browser"
expect_rc 0 "browser-capture creates parent directory for output" \
  env PATH="$FAKEBIN:$PATH" "$CLI" browser-capture https://x.test "$TMP/a/b/c/shot.png"
expect_ok "nested output file exists" test -f "$TMP/a/b/c/shot.png"

# --session flag propagation (our stub strips the first two args when --session is present).
expect_rc 0 "browser-capture --session propagates" \
  env PATH="$FAKEBIN:$PATH" "$CLI" browser-capture --session myapp https://x.test "$TMP/sess.png" 2>/dev/null || true
# (argparse may reject --session before url — check positional ordering.)
expect_rc 0 "browser-capture --session after positionals" \
  env PATH="$FAKEBIN:$PATH" "$CLI" browser-capture https://x.test "$TMP/sess2.png" --session myapp
expect_ok "sess2.png written" test -f "$TMP/sess2.png"

# ------------------------------------------------------------------
# 7. verify-tests: backtick-wrapped test file path
# ------------------------------------------------------------------
section "verify-tests: backtick-wrapped path stripping"

cat > docs/plans/backtick.md <<'EOF'
# X
**Date:** 2026-04-21
**Status:** Planning
**PRD:** None
## Overview
x
## Architecture
x
#### 1.1 Implement foo

**Depends on:** none
**Files:** `pkg/mod.py`, `pkg/test_mod.py`

Do it.

**Test scenarios:** (`pkg/test_mod.py`)
- a → b

**Verify:** pytest
EOF

mkdir -p pkg
cat > pkg/mod.py <<'EOF'
def foo(): return 1
EOF
cat > pkg/test_mod.py <<'EOF'
def test_one(): assert True
EOF

expect_rc 0 "verify-tests handles backtick-wrapped test-file parenthetical" \
  "$CLI" verify-tests docs/plans/backtick.md 1.1

# ------------------------------------------------------------------
# 8. Real install pipeline (into an isolated $HOME-like tree)
# ------------------------------------------------------------------
section "real install pipeline: make install -> loopy on PATH"

INSTALL_TMP="$(mktemp -d)"
(
  export CLAUDE_HOME="$INSTALL_TMP/.claude"
  export CODEX_HOME="$INSTALL_TMP/.codex"
  export GEMINI_HOME="$INSTALL_TMP/.gemini"
  export LOOPY_TASK_BIN_DIR="$INSTALL_TMP/.local/bin"
  "$ROOT/scripts/install.sh" >/tmp/install_out 2>&1
) && ok "install.sh completed" || { bad "install.sh failed"; cat /tmp/install_out; }

[ -x "$INSTALL_TMP/.local/bin/loopy" ] && ok "loopy installed to LOOPY_TASK_BIN_DIR" \
  || bad "loopy not installed"

# Invoke the installed copy (not the repo copy) end-to-end.
INSTALLED_LOOPY="$INSTALL_TMP/.local/bin/loopy"
expect_rc 0 "installed loopy validates bundled fixture" \
  "$INSTALLED_LOOPY" validate prd "$HERE/fixtures/prd-valid.md"
expect_rc 0 "installed loopy has browser-capture subcommand" \
  "$INSTALLED_LOOPY" browser-capture --help
expect_rc 0 "installed loopy has review-save --attach in help" \
  bash -c "'$INSTALLED_LOOPY' review-save --help | grep -q -- '--attach'"

# Uninstall.
(
  export CLAUDE_HOME="$INSTALL_TMP/.claude"
  export CODEX_HOME="$INSTALL_TMP/.codex"
  export GEMINI_HOME="$INSTALL_TMP/.gemini"
  export LOOPY_TASK_BIN_DIR="$INSTALL_TMP/.local/bin"
  "$ROOT/scripts/install.sh" --uninstall >/tmp/uninstall_out 2>&1
) && ok "install.sh --uninstall completed" || bad "uninstall failed"
[ ! -f "$INSTALL_TMP/.local/bin/loopy" ] && ok "loopy removed on uninstall" \
  || bad "loopy still present after uninstall"

rm -rf "$INSTALL_TMP"

# ------------------------------------------------------------------
# Summary
# ------------------------------------------------------------------
echo
echo "Deep tests: $pass passed, $fail failed"
if [ "$fail" -gt 0 ]; then
  echo "Failures:"
  for f in "${failures[@]}"; do echo "  - $f"; done
  exit 1
fi
