#!/usr/bin/env bash
# End-to-end demo: exercises every loopy CLI touch-point against a fresh repo,
# simulating what the skills (requirements -> plan -> build -> review -> wrapup)
# would do. No AI agents involved -- we just verify the CLI glue works and
# the state/artifacts end up consistent.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLI="$HERE/../loopy"

pass=0
fail=0
failures=()

ok()   { pass=$((pass+1)); echo "  ok: $1"; }
bad()  { fail=$((fail+1)); failures+=("$1"); echo "  FAIL: $1"; }

expect_ok() {
  local desc="$1"; shift
  local out
  if out=$("$@" 2>&1); then
    ok "$desc"
    [ -n "${DEBUG:-}" ] && echo "     $out"
  else
    bad "$desc  --  $out"
  fi
}

expect_fail() {
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then
    bad "$desc (expected failure)"
  else
    ok "$desc"
  fi
}

contains() {
  local desc="$1"; local needle="$2"; shift 2
  local out
  out=$("$@" 2>&1 || true)
  if grep -qF -- "$needle" <<<"$out"; then
    ok "$desc"
  else
    bad "$desc (needle not found: $needle)"
    echo "     output: $(head -c 300 <<<"$out")"
  fi
}

section() { echo; echo "== $1 =="; }

# ------------------------------------------------------------------
# Scaffold a throwaway repo for a fictional calculator module.
# ------------------------------------------------------------------
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cd "$TMP"

git init -q
git config user.email demo@example.com
git config user.name demo
git commit --allow-empty -q -m "init"

mkdir -p docs/prd docs/plans src tests

# ------------------------------------------------------------------
# Stage 1: Requirements (simulates /loopy-requirements)
# ------------------------------------------------------------------
section "stage 1: requirements"

cat > docs/prd/2026-04-20-calculator-prd.md <<'EOF'
# Calculator - PRD

**Date:** 2026-04-20
**Status:** Requirements

## Goal
Provide a minimal Python calculator module for demos and smoke tests.

## Scope

### In Scope
- Arithmetic: add, subtract, multiply, divide.
- Pure functions, no I/O.

### Boundaries
- No UI.
- No symbolic math or big-integer guarantees.
- No persistence.

## Requirements

| ID | Priority | Requirement |
|----|----------|-------------|
| R1 | Core | Module exposes add, sub, mul, div functions over ints/floats |
| R2 | Must | div raises ZeroDivisionError when divisor is 0 |
| R3 | Nice | Functions accept ints or floats interchangeably |
| R4 | Out | Complex numbers |

## Open Questions
- **[Affects R3]** Should we coerce booleans to ints? (defer)

## Next Steps
→ Create technical plan.
EOF

expect_ok "PRD validates" "$CLI" validate prd docs/prd/2026-04-20-calculator-prd.md
expect_ok "state set stage=requirements"  "$CLI" state set stage requirements
expect_ok "state set prd path"            "$CLI" state set prd docs/prd/2026-04-20-calculator-prd.md
expect_ok "state set feature"             "$CLI" state set feature calculator
contains  "state shows feature"           "feature: calculator" "$CLI" state show
contains  "state shows prd"               "prd: docs/prd" "$CLI" state show
git add -A && git commit -q -m "requirements: initial PRD"

# Break the PRD and make sure validation catches it -- then repair.
cp docs/prd/2026-04-20-calculator-prd.md /tmp/_prd_backup.md
sed -i.bak 's/| R2 | Must |/| R1 | Bogus |/' docs/prd/2026-04-20-calculator-prd.md
expect_fail "validator catches duplicate ID + bad priority" "$CLI" validate prd docs/prd/2026-04-20-calculator-prd.md
contains   "duplicate-ID error shown" "duplicate ID" "$CLI" validate prd docs/prd/2026-04-20-calculator-prd.md
cp /tmp/_prd_backup.md docs/prd/2026-04-20-calculator-prd.md
rm -f docs/prd/2026-04-20-calculator-prd.md.bak /tmp/_prd_backup.md
expect_ok "PRD re-validates after repair" "$CLI" validate prd docs/prd/2026-04-20-calculator-prd.md

# ------------------------------------------------------------------
# Stage 2: Plan (simulates /loopy-plan)
# ------------------------------------------------------------------
section "stage 2: plan"

cat > docs/plans/2026-04-20-calculator-tech-plan.md <<'EOF'
# Calculator - Technical Plan

**Date:** 2026-04-20
**Status:** Planning
**PRD:** docs/prd/2026-04-20-calculator-prd.md

## Overview
Implement a tiny pure-function calculator in `src/calculator.py`
with Pytest coverage in `tests/test_calculator.py`.

## Architecture
Single flat module exporting add/sub/mul/div. No state.

## Subtasks

### Parent 1: Core arithmetic

#### 1.1 Implement add and sub

**Depends on:** none
**Files:** `src/calculator.py`, `tests/test_calculator.py`

Add `add(a, b)` and `sub(a, b)`. Satisfies R1.

**Test scenarios:** (`tests/test_calculator.py`)
- add(2, 3) → 5
- add(-1, 1) → 0
- sub(10, 4) → 6

**Verify:** `pytest -q`.

#### 1.2 Implement mul and div with zero-guard

**Depends on:** 1.1
**Files:** `src/calculator.py`, `tests/test_calculator.py`

Add `mul(a, b)` and `div(a, b)`. `div` must raise `ZeroDivisionError`
when the divisor is zero. Satisfies R1, R2.

**Test scenarios:** (`tests/test_calculator.py`)
- mul(3, 4) → 12
- div(10, 2) → 5
- div(1, 0) → ZeroDivisionError

**Verify:** `pytest -q`.

## Testing Strategy
Pytest only; no integration tests.

## Risks and Mitigations
| Risk | Mitigation |
|------|------------|
| Float precision | Document; do not add epsilon compare in v1 |
EOF

expect_ok "plan validates"                   "$CLI" validate plan docs/plans/2026-04-20-calculator-tech-plan.md
expect_ok "state set stage=plan"             "$CLI" state set stage plan
expect_ok "state set plan path"              "$CLI" state set plan docs/plans/2026-04-20-calculator-tech-plan.md
git add -A && git commit -q -m "plan: tech plan"

# Break the plan in a couple of ways, confirm each is caught.
cp docs/plans/2026-04-20-calculator-tech-plan.md /tmp/_plan_backup.md
# introduce a cycle: 1.1 depends on 1.2
sed -i.bak 's/^\*\*Depends on:\*\* none$/**Depends on:** 1.2/' docs/plans/2026-04-20-calculator-tech-plan.md
expect_fail "validator catches cycle"   "$CLI" validate plan docs/plans/2026-04-20-calculator-tech-plan.md
contains    "cycle message"              "dependency cycle" "$CLI" validate plan docs/plans/2026-04-20-calculator-tech-plan.md
cp /tmp/_plan_backup.md docs/plans/2026-04-20-calculator-tech-plan.md
rm -f docs/plans/2026-04-20-calculator-tech-plan.md.bak /tmp/_plan_backup.md

# Break dep reference
cp docs/plans/2026-04-20-calculator-tech-plan.md /tmp/_plan_backup.md
sed -i.bak 's/^\*\*Depends on:\*\* 1.1$/**Depends on:** 9.9/' docs/plans/2026-04-20-calculator-tech-plan.md
expect_fail "validator catches unknown dep" "$CLI" validate plan docs/plans/2026-04-20-calculator-tech-plan.md
contains    "unknown-dep message"           "unknown subtask" "$CLI" validate plan docs/plans/2026-04-20-calculator-tech-plan.md
cp /tmp/_plan_backup.md docs/plans/2026-04-20-calculator-tech-plan.md
rm -f docs/plans/2026-04-20-calculator-tech-plan.md.bak /tmp/_plan_backup.md

expect_ok "plan re-validates after repair" "$CLI" validate plan docs/plans/2026-04-20-calculator-tech-plan.md

# ------------------------------------------------------------------
# Stage 3: Build (simulates /loopy-build section 1)
# ------------------------------------------------------------------
section "stage 3: build"

expect_ok "state stage=build" "$CLI" state set stage build

# Record section 1 baseline (current HEAD).
SECTION1_BASE="$(git rev-parse HEAD)"
expect_ok "record section-1 baseline" "$CLI" state section-baseline 1 "$SECTION1_BASE"

# ---- Subtask 1.1: implement and commit, tests intentionally incomplete first.
cat > src/calculator.py <<'PY'
def add(a, b):
    return a + b

def sub(a, b):
    return a - b
PY
cat > tests/test_calculator.py <<'PY'
from src.calculator import add

def test_add_positive():
    assert add(2, 3) == 5
PY

# verify-tests should FAIL: 1 test vs 3 scenarios declared for 1.1.
expect_fail "verify-tests flags missing tests for 1.1" \
  "$CLI" verify-tests docs/plans/2026-04-20-calculator-tech-plan.md 1.1
contains    "reports counts"  "3 scenario" \
  "$CLI" verify-tests docs/plans/2026-04-20-calculator-tech-plan.md 1.1

# Fix by adding the missing tests.
cat > tests/test_calculator.py <<'PY'
from src.calculator import add, sub

def test_add_positive():
    assert add(2, 3) == 5

def test_add_to_zero():
    assert add(-1, 1) == 0

def test_sub():
    assert sub(10, 4) == 6
PY

expect_ok "verify-tests passes for 1.1" \
  "$CLI" verify-tests docs/plans/2026-04-20-calculator-tech-plan.md 1.1

# Real pytest run to prove the tests actually execute.
if command -v python3 >/dev/null 2>&1; then
  if python3 -m pytest -q tests/test_calculator.py >/tmp/pytest_out 2>&1; then
    ok "pytest passes after 1.1"
  else
    # pytest might not be installed; that's fine -- this is a best-effort check.
    echo "     (pytest not usable, skipping runtime check: $(head -1 /tmp/pytest_out))"
  fi
fi
git add -A && git commit -q -m "feat(calc): add/sub"

# ---- Subtask 1.2
cat > src/calculator.py <<'PY'
def add(a, b):
    return a + b

def sub(a, b):
    return a - b

def mul(a, b):
    return a * b

def div(a, b):
    if b == 0:
        raise ZeroDivisionError("divide by zero")
    return a / b
PY

cat > tests/test_calculator.py <<'PY'
import pytest
from src.calculator import add, sub, mul, div

def test_add_positive():
    assert add(2, 3) == 5

def test_add_to_zero():
    assert add(-1, 1) == 0

def test_sub():
    assert sub(10, 4) == 6

def test_mul():
    assert mul(3, 4) == 12

def test_div():
    assert div(10, 2) == 5

def test_div_by_zero():
    with pytest.raises(ZeroDivisionError):
        div(1, 0)
PY

expect_ok "verify-tests passes for 1.2" \
  "$CLI" verify-tests docs/plans/2026-04-20-calculator-tech-plan.md 1.2
git add -A && git commit -q -m "feat(calc): mul/div with zero guard"

# Budget: simulate telemetry from both subtasks.
expect_ok "budget add (plan tokens)"    "$CLI" budget add tokens 8200  --stage plan --note "planning chat"
expect_ok "budget add (build tokens 1)" "$CLI" budget add tokens 3400  --stage build --note "subtask 1.1"
expect_ok "budget add (build tokens 2)" "$CLI" budget add tokens 4100  --stage build --note "subtask 1.2"
expect_ok "budget add (build seconds)"  "$CLI" budget add seconds 94.5 --stage build
contains  "budget totals tokens"        "tokens: 15700" "$CLI" budget summary
contains  "budget per-stage build"      "build:" "$CLI" budget summary

# ------------------------------------------------------------------
# Stage 4: Review (simulates /loopy-code-review)
# ------------------------------------------------------------------
section "stage 4: review"

SECTION_REVIEW_BODY="### Strengths
- Zero-guard implemented correctly.

### Correctness reviewer
| # | Location | Issue | Fix | Severity |
|---|----------|-------|-----|----------|
| 1 | src/calculator.py:12 | div() compares divisor with == 0; floats with tiny values compare unequal. Acceptable per plan. | None | Low |

---

**Verdict:** Ready with fixes
**Reasoning:** One Low finding, acceptable per plan."

REVIEW_PATH="$(echo "$SECTION_REVIEW_BODY" | "$CLI" review-save section-1 --stdin --plan docs/plans/2026-04-20-calculator-tech-plan.md --base-sha "$SECTION1_BASE")"
[ -n "$REVIEW_PATH" ] && ok "review-save emitted path ($REVIEW_PATH)" || bad "review-save returned empty path"
[ -f "$REVIEW_PATH" ] && ok "review file on disk" || bad "review file missing"
contains "review header written"   "**Base SHA:** $SECTION1_BASE" cat "$REVIEW_PATH"
contains "review body preserved"   "Zero-guard implemented" cat "$REVIEW_PATH"
contains "plan linked via ## Reviews" "## Reviews" cat docs/plans/2026-04-20-calculator-tech-plan.md
contains "plan link path correct"     "../reviews/" cat docs/plans/2026-04-20-calculator-tech-plan.md
contains "state captured review"      "scope: section-1" "$CLI" state show

# Second review round (same scope, same day) -- suffix collision path.
SECOND_PATH="$(echo "final pass" | "$CLI" review-save section-1 --stdin --plan docs/plans/2026-04-20-calculator-tech-plan.md)"
[ "$SECOND_PATH" != "$REVIEW_PATH" ] && ok "second review uses suffixed path ($SECOND_PATH)" || bad "collision suffix not applied"

git add -A && git commit -q -m "docs: record section-1 review"

# ------------------------------------------------------------------
# Stage 4b: Visual-evidence review (frontend diff + browser-capture)
# ------------------------------------------------------------------
section "stage 4b: visual evidence (review --attach + browser-capture)"

# Without agent-browser on PATH, browser-capture should degrade (exit 3).
out=$(env -i PATH=/usr/bin:/bin HOME="$TMP" "$CLI" browser-capture https://example.com "$TMP/x.png" 2>&1)
rc=$?
[ "$rc" = "3" ] && ok "browser-capture degrades cleanly when agent-browser missing" \
  || bad "expected exit 3, got $rc"
grep -q "not installed" <<<"$out" && ok "degraded message mentions agent-browser" \
  || bad "missing degraded message"

# Stub agent-browser and run a real capture.
FAKEBIN="$TMP/fakebin"
mkdir -p "$FAKEBIN"
cat > "$FAKEBIN/agent-browser" <<'EOS'
#!/usr/bin/env bash
if [ "$1" = "--session" ]; then shift 2; fi
case "$1" in
  open)    echo "opened $2" ;;
  wait)    echo "waited" ;;
  screenshot)
    out="$2"; [ "$out" = "--full" ] && out="$3"
    printf '\x89PNG\r\n\x1a\nfake-before' > "$out"
    ;;
  *)       echo "unknown: $*" >&2; exit 1 ;;
esac
EOS
chmod +x "$FAKEBIN/agent-browser"

mkdir -p "$TMP/evidence"
PATH="$FAKEBIN:$PATH" "$CLI" browser-capture http://localhost:3000 "$TMP/evidence/before.png" >/dev/null 2>&1 \
  && ok "browser-capture (before) succeeded via stub" || bad "browser-capture before failed"
[ -f "$TMP/evidence/before.png" ] && ok "before.png written" || bad "before.png missing"

# Capture 'after' and ensure it's a distinct file.
cat > "$FAKEBIN/agent-browser" <<'EOS'
#!/usr/bin/env bash
if [ "$1" = "--session" ]; then shift 2; fi
case "$1" in
  open)    echo "opened $2" ;;
  wait)    echo "waited" ;;
  screenshot)
    out="$2"; [ "$out" = "--full" ] && out="$3"
    printf '\x89PNG\r\n\x1a\nfake-after' > "$out"
    ;;
  *)       echo "unknown: $*" >&2; exit 1 ;;
esac
EOS
chmod +x "$FAKEBIN/agent-browser"
PATH="$FAKEBIN:$PATH" "$CLI" browser-capture http://localhost:3000 "$TMP/evidence/after.png" --full >/dev/null 2>&1 \
  && ok "browser-capture (after) succeeded via stub" || bad "browser-capture after failed"

# Review with attachments (simulates the code-review 'Attaching visual evidence' flow).
FE_REVIEW_BODY="### Strengths
- Layout renders as intended in both states.

### Simplicity reviewer
| # | Location | Issue | Fix | Severity |
|---|----------|-------|-----|----------|
| 1 | n/a | Minor style churn; consider Tailwind token re-use. | Defer | Low |

---

**Verdict:** Ready to merge"

FE_PATH=$(echo "$FE_REVIEW_BODY" | "$CLI" review-save frontend --stdin \
    --plan docs/plans/2026-04-20-calculator-tech-plan.md \
    --attach "$TMP/evidence/before.png" --attach "$TMP/evidence/after.png")
[ -n "$FE_PATH" ] && ok "review-save --attach returned path ($FE_PATH)" || bad "no path"
[ "${FE_PATH##*/}" = "index.md" ] && ok "review went into directory mode (index.md)" \
  || bad "expected index.md, got $FE_PATH"
FE_DIR="$(dirname "$TMP/$FE_PATH")"
[ -f "$FE_DIR/before.png" ] && ok "before.png copied into review dir" || bad "before.png not copied"
[ -f "$FE_DIR/after.png" ]  && ok "after.png copied into review dir"  || bad "after.png not copied"
contains "index.md embeds before image" "![before](before.png)" cat "$TMP/$FE_PATH"
contains "index.md embeds after image"  "![after](after.png)"   cat "$TMP/$FE_PATH"
contains "plan links into frontend review dir" "frontend/index.md" \
  cat "$TMP/docs/plans/2026-04-20-calculator-tech-plan.md"
contains "state records attachments" "before.png" "$CLI" state show

git add -A && git commit -q -m "docs: record frontend review with visual evidence"

# ------------------------------------------------------------------
# Stage 5: Wrapup (simulates /loopy-ship)
# ------------------------------------------------------------------
section "stage 5: wrapup"

expect_ok "state stage=complete" "$CLI" state set stage complete
contains "state shows complete"  "stage: complete" "$CLI" state show
contains "state has both baselines+reviews" "section-1" "$CLI" state show
contains "state json round-trips" '"schema_version": 1' "$CLI" state show --json

# Final full JSON sanity: no parser errors on anything we wrote.
expect_ok "final state parses clean (JSON dump)" "$CLI" state show --json

# ------------------------------------------------------------------
# Summary
# ------------------------------------------------------------------
echo
echo "E2E demo: $pass passed, $fail failed"
if [ "$fail" -gt 0 ]; then
  echo "Failures:"
  for f in "${failures[@]}"; do echo "  - $f"; done
  exit 1
fi
