#!/usr/bin/env bash
# Test runner for the `loopy` CLI. Uses only bash + stdlib Python.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLI="$HERE/../loopy"
FIX="$HERE/fixtures"

pass=0
fail=0
failures=()

assert() {
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then
    pass=$((pass + 1))
    echo "  ok: $desc"
  else
    fail=$((fail + 1))
    failures+=("$desc")
    echo "  FAIL: $desc"
  fi
}

assert_not() {
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then
    fail=$((fail + 1))
    failures+=("$desc")
    echo "  FAIL: $desc (expected non-zero exit)"
  else
    pass=$((pass + 1))
    echo "  ok: $desc"
  fi
}

assert_contains() {
  local desc="$1"; local needle="$2"; shift 2
  local out
  out="$("$@" 2>&1 || true)"
  if grep -qF -- "$needle" <<<"$out"; then
    pass=$((pass + 1))
    echo "  ok: $desc"
  else
    fail=$((fail + 1))
    failures+=("$desc (needle: $needle)")
    echo "  FAIL: $desc — expected substring not found: $needle"
    echo "        output was: $out" | head -c 500
    echo
  fi
}

section() {
  echo
  echo "== $1 =="
}

# --- validate ---
section "validate prd"
assert "valid PRD passes"    "$CLI" validate prd "$FIX/prd-valid.md"
assert_not "invalid PRD fails" "$CLI" validate prd "$FIX/prd-invalid.md"
assert_contains "invalid PRD reports duplicate IDs" "duplicate ID" "$CLI" validate prd "$FIX/prd-invalid.md"
assert_contains "invalid PRD reports bad priority"  "must be one of" "$CLI" validate prd "$FIX/prd-invalid.md"
assert_contains "invalid PRD reports missing Boundaries" "Boundaries" "$CLI" validate prd "$FIX/prd-invalid.md"
assert_contains "invalid PRD reports untagged open question" "Affects" "$CLI" validate prd "$FIX/prd-invalid.md"
assert_contains "valid PRD JSON has no errors" '"errors": []' "$CLI" validate prd "$FIX/prd-valid.md" --json

section "validate plan"
assert "valid plan passes"     "$CLI" validate plan "$FIX/plan-valid.md"
assert_not "invalid plan fails" "$CLI" validate plan "$FIX/plan-invalid.md"
assert_contains "reports numbering gap" "numbering has gaps" "$CLI" validate plan "$FIX/plan-invalid.md"
assert_contains "reports unknown dep"   "unknown subtask" "$CLI" validate plan "$FIX/plan-invalid.md"
assert_contains "reports cycle"         "dependency cycle" "$CLI" validate plan "$FIX/plan-invalid.md"
assert_contains "reports missing test scenarios" "missing **Test scenarios" "$CLI" validate plan "$FIX/plan-invalid.md"
assert_contains "reports missing PRD header" "missing header: **PRD:**" "$CLI" validate plan "$FIX/plan-invalid.md"

# --- state, verify-tests, review-save, budget: use a throwaway git repo ---
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

section "state subcommand"
(
  cd "$TMP"
  git init -q
  git config user.email t@example.com
  git config user.name tester
  git commit --allow-empty -q -m init
)

assert "state show empty" env -C "$TMP" "$CLI" state show
assert_contains "state set writes" "stage = 'build'" env -C "$TMP" "$CLI" state set stage build
assert_contains "state show reflects set" "stage: build" env -C "$TMP" "$CLI" state show
assert "state section-baseline writes" env -C "$TMP" "$CLI" state section-baseline 1 abc123
assert_contains "state baseline stored" "abc123" env -C "$TMP" "$CLI" state show
assert "state review-add writes" env -C "$TMP" "$CLI" state review-add section-1 docs/reviews/x.md
assert_contains "state review stored" "section-1" env -C "$TMP" "$CLI" state show

# Dotted key set (nested)
assert "state set dotted key" env -C "$TMP" "$CLI" state set plan.path docs/plans/foo.md
assert_contains "dotted key shown" "path: docs/plans/foo.md" env -C "$TMP" "$CLI" state show

# State file should round-trip: write then re-parse via show --json.
assert_contains "state json has stage" '"stage": "build"' env -C "$TMP" "$CLI" state show --json

section "verify-tests"
# Set up a fake plan + test file inside the temp repo.
mkdir -p "$TMP/docs/plans" "$TMP/app/services"
cp "$FIX/plan-valid.md" "$TMP/docs/plans/plan.md"
# (Plan paths are already relative; no rewriting needed.)

# Create test file WITHOUT enough tests — should fail.
cat > "$TMP/app/services/audit_exporter.test.ts" <<'EOF'
// too few tests
it("one", () => {});
EOF
# Non-test source file
cat > "$TMP/app/services/audit_exporter.ts" <<'EOF'
export function x() {}
EOF
assert_not "verify-tests fails when test count < scenarios" env -C "$TMP" "$CLI" verify-tests docs/plans/plan.md 1.1

# Add enough tests (3 scenarios in plan for 1.1):
cat > "$TMP/app/services/audit_exporter.test.ts" <<'EOF'
it("a", () => {});
it("b", () => {});
it("c", () => {});
EOF
assert "verify-tests passes when test count >= scenarios" env -C "$TMP" "$CLI" verify-tests docs/plans/plan.md 1.1

# Missing test file entirely for 1.2
mkdir -p "$TMP/app/controllers"
cat > "$TMP/app/controllers/audit_controller.ts" <<'EOF'
// stub
EOF
assert_not "verify-tests fails when test file missing" env -C "$TMP" "$CLI" verify-tests docs/plans/plan.md 1.2

# Non-existent subtask id
assert_not "verify-tests errors on unknown subtask" env -C "$TMP" "$CLI" verify-tests docs/plans/plan.md 9.9

# Python test style
mkdir -p "$TMP/pkg"
cat > "$TMP/pkg/mod.py" <<'EOF'
def foo(): return 1
EOF
cat > "$TMP/pkg/test_mod.py" <<'EOF'
def test_one(): assert True
def test_two(): assert True
def test_three(): assert True
EOF
# Craft a minimal plan for this:
cat > "$TMP/docs/plans/py.md" <<'EOF'
# Py plan
**Date:** 2026-04-20
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
- c → d
- e → f

**Verify:** pytest
EOF
assert "verify-tests works for Python tests" env -C "$TMP" "$CLI" verify-tests docs/plans/py.md 1.1

section "review-save"
REVIEW_OUT="$(env -C "$TMP" "$CLI" review-save section-1 --content "hello review" --plan docs/plans/plan.md --base-sha deadbeef)"
assert "review-save returns a path"    test -n "$REVIEW_OUT"
assert "review file was written"        test -f "$TMP/$REVIEW_OUT"
assert_contains "review file contains header" "**Scope:** section-1" cat "$TMP/$REVIEW_OUT"
assert_contains "plan gained Reviews section" "## Reviews" cat "$TMP/docs/plans/plan.md"
assert_contains "state recorded review"        "section-1" env -C "$TMP" "$CLI" state show

# Stdin variant + collision suffixing (same scope same day)
echo "another round" | env -C "$TMP" "$CLI" review-save section-1 --stdin --plan docs/plans/plan.md > "$TMP/second.txt"
SECOND="$(cat "$TMP/second.txt")"
assert "second review-save returned different path" test "$SECOND" != "$REVIEW_OUT"
assert "second review file exists" test -f "$TMP/$SECOND"

section "review-save --attach"
# Prepare two attachment files (one image-like by extension, one text log).
mkdir -p "$TMP/attachments"
# Minimal 67-byte PNG (8x1 transparent) — enough bytes to copy and keep markdown happy.
printf '\x89PNG\r\n\x1a\n' > "$TMP/attachments/before.png"
dd if=/dev/urandom of="$TMP/attachments/before.png" bs=1 count=128 conv=notrunc 2>/dev/null
cp "$TMP/attachments/before.png" "$TMP/attachments/after.png"
echo "lighthouse score: 92" > "$TMP/attachments/metrics.txt"

ATTACH_OUT="$(env -C "$TMP" "$CLI" review-save section-2 --content "frontend review" \
    --plan docs/plans/plan.md --base-sha cafebabe \
    --attach attachments/before.png --attach attachments/after.png --attach attachments/metrics.txt)"
assert "attach: review-save returned a path"   test -n "$ATTACH_OUT"
assert "attach: output is a directory-mode index" test "${ATTACH_OUT##*/}" = "index.md"
assert "attach: index.md exists"                test -f "$TMP/$ATTACH_OUT"
ATTACH_DIR="$(dirname "$TMP/$ATTACH_OUT")"
assert "attach: before.png copied"              test -f "$ATTACH_DIR/before.png"
assert "attach: after.png copied"               test -f "$ATTACH_DIR/after.png"
assert "attach: metrics.txt copied"             test -f "$ATTACH_DIR/metrics.txt"
assert_contains "attach: image embedded as markdown image" "![before](before.png)" cat "$TMP/$ATTACH_OUT"
assert_contains "attach: non-image linked"       "[metrics.txt](metrics.txt)"      cat "$TMP/$ATTACH_OUT"
assert_contains "attach: Evidence heading present" "## Evidence" cat "$TMP/$ATTACH_OUT"
assert_contains "attach: state records attachment names" "before.png" env -C "$TMP" "$CLI" state show
assert_contains "attach: plan link points into review directory" "section-2/index.md" cat "$TMP/docs/plans/plan.md"

# Missing attachment should fail cleanly.
assert_not "attach: missing file rejected" env -C "$TMP" "$CLI" review-save bad --content x --attach nope.png

# Attachment filename collision inside the review directory.
cp "$TMP/attachments/before.png" "$TMP/attachments/dupe.png"
ATTACH2_OUT="$(env -C "$TMP" "$CLI" review-save section-3 --content "dupes" --attach attachments/dupe.png --attach attachments/dupe.png)"
ATTACH2_DIR="$(dirname "$TMP/$ATTACH2_OUT")"
assert "attach: first collision kept as-is"  test -f "$ATTACH2_DIR/dupe.png"
assert "attach: second copy got a suffix"     test -f "$ATTACH2_DIR/dupe-2.png"

section "browser-capture"

# Helper: assert exit code exactly equals $1 when running the rest.
assert_rc() {
  local want="$1"; local desc="$2"; shift 2
  local out rc
  out="$("$@" 2>&1)"; rc=$?
  if [ "$rc" = "$want" ]; then
    pass=$((pass + 1))
    echo "  ok: $desc"
  else
    fail=$((fail + 1))
    failures+=("$desc (want rc=$want got rc=$rc)")
    echo "  FAIL: $desc  want rc=$want got rc=$rc"
    echo "        output: $out" | head -c 400
    echo
  fi
}

# Without agent-browser on PATH: should exit 3 with a helpful message.
assert_rc 3 "browser-capture exits 3 when agent-browser missing" \
  env -i PATH=/usr/bin:/bin HOME="$TMP" "$CLI" browser-capture https://example.com "$TMP/shot.png"
assert_contains "browser-capture error message mentions not installed" "not installed" \
  env -i PATH=/usr/bin:/bin HOME="$TMP" "$CLI" browser-capture https://example.com "$TMP/shot.png"

# With a fake agent-browser on PATH: simulate a successful screenshot.
FAKEBIN="$TMP/fakebin"
mkdir -p "$FAKEBIN"
cat > "$FAKEBIN/agent-browser" <<'EOS'
#!/usr/bin/env bash
# Minimal stand-in for agent-browser: on 'screenshot <path>' write a png-ish file.
if [ "$1" = "--session" ]; then shift 2; fi
case "$1" in
  open)       echo "opened $2" ;;
  wait)       echo "waited" ;;
  screenshot)
    out="$2"
    # Drop --full if present.
    [ "$out" = "--full" ] && out="$3"
    printf '\x89PNG\r\n\x1a\nfake' > "$out"
    echo "screenshot $out"
    ;;
  *)          echo "unknown: $*" >&2; exit 1 ;;
esac
EOS
chmod +x "$FAKEBIN/agent-browser"

PATH="$FAKEBIN:$PATH" assert_rc 0 "browser-capture succeeds with fake agent-browser" \
  env PATH="$FAKEBIN:$PATH" "$CLI" browser-capture https://example.com "$TMP/shot.png"
assert "browser-capture produced screenshot file" test -f "$TMP/shot.png"

assert_rc 0 "browser-capture --full works" \
  env PATH="$FAKEBIN:$PATH" "$CLI" browser-capture https://example.com "$TMP/shot-full.png" --full
assert "browser-capture --full produced file" test -f "$TMP/shot-full.png"

# Output being a directory should fail with exit 2.
mkdir -p "$TMP/shotdir"
assert_rc 2 "browser-capture rejects directory output (exit 2)" \
  env PATH="$FAKEBIN:$PATH" "$CLI" browser-capture https://example.com "$TMP/shotdir"

section "budget"
assert "budget add tokens"  env -C "$TMP" "$CLI" budget add tokens 12345 --stage build --note "batch 1"
assert "budget add seconds" env -C "$TMP" "$CLI" budget add seconds 42.5 --stage review
assert_contains "budget summary shows tokens" "tokens: 12345" env -C "$TMP" "$CLI" budget summary
assert_contains "budget summary shows seconds" "seconds: 42.5" env -C "$TMP" "$CLI" budget summary
assert_contains "budget summary per-stage" "build:" env -C "$TMP" "$CLI" budget summary
assert_not "budget rejects bad kind" env -C "$TMP" "$CLI" budget add garbage 1 --stage build
assert_not "budget rejects bad amount" env -C "$TMP" "$CLI" budget add tokens notanumber --stage build
assert_contains "budget summary JSON" '"totals"' env -C "$TMP" "$CLI" budget summary --json

echo
echo "Summary: $pass passed, $fail failed"
if [ "$fail" -gt 0 ]; then
  echo "Failures:"
  for f in "${failures[@]}"; do echo "  - $f"; done
  exit 1
fi
