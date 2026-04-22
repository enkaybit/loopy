#!/usr/bin/env bash
# Live walkthrough: take a small Python calculator from requirements to wrapup
# using ONLY the installed `loopy` CLI. Unlike run_tests.sh / e2e_demo.sh /
# deep_tests.sh, this script is narrative: it prints commentary between
# commands so a reader (or stakeholder) can follow the workflow end-to-end.
#
# Designed to be safe to run on any machine: everything lives in a throwaway
# temp directory, and cleanup is automatic.
#
# Exits non-zero if any stage fails, so it also serves as a live smoke test.
set -euo pipefail

CLI_FROM_REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/loopy"
# Prefer the installed CLI (closer to how a real user runs it). Fall back to
# the repo copy if not installed.
if command -v loopy >/dev/null 2>&1; then
  LOOPY="$(command -v loopy)"
  LOOPY_SRC="PATH"
else
  LOOPY="$CLI_FROM_REPO"
  LOOPY_SRC="repo checkout"
fi

CYAN=$'\033[0;36m'; YELLOW=$'\033[0;33m'; GREEN=$'\033[0;32m'; RESET=$'\033[0m'
step()     { printf "\n${CYAN}== %s ==${RESET}\n" "$*"; }
note()     { printf "${YELLOW}   %s${RESET}\n" "$*"; }
say()      { printf "${GREEN}-> %s${RESET}\n" "$*"; }
show()     { printf "   $ %s\n" "$*"; }
run()      { show "$*"; eval "$@"; }

cat <<EOF
${GREEN}Loopy calculator walkthrough${RESET}

Using loopy CLI: $LOOPY  (from $LOOPY_SRC)

This script builds a tiny Python calculator module end-to-end:
  1. requirements  -> PRD
  2. plan          -> tech plan with subtasks and test scenarios
  3. build         -> three TDD subtasks in two sections
  4. review        -> scoped section review + frontend review with screenshots
  5. wrapup        -> state summary and budget

Everything lives in a temp directory (printed below). python3 must be on PATH.
EOF

DEMO="$(mktemp -d)/calc-demo"
mkdir -p "$DEMO"
trap 'rm -rf "$(dirname "$DEMO")"' EXIT
cd "$DEMO"
say "Working directory: $DEMO"

git init -q && git config user.email demo@example.com && git config user.name "demo user"
git commit -q --allow-empty -m "init"

# ---------------------------------------------------------------------------
step "Stage 1 — Requirements"
# ---------------------------------------------------------------------------

mkdir -p docs/prd
cat > docs/prd/2026-04-21-calculator-prd.md <<'EOF'
# Pocket Calculator - PRD

**Date:** 2026-04-21
**Status:** Requirements

## Goal
Provide a tiny Python calculator module suitable for embedding in demos,
smoke tests, and REPL sessions. Pure functions, no I/O.

## Scope

### In Scope
- Binary arithmetic: add, sub, mul, div over ints and floats.
- A top-level `evaluate(expr)` helper that parses simple `a op b` strings.

### Boundaries
- No arbitrary expression parsing (no operator precedence, no parens).
- No symbolic math, big integers, complex numbers.
- No CLI, no UI, no persistence.

## Requirements

| ID | Priority | Requirement |
|----|----------|-------------|
| R1 | Core | Module exposes add, sub, mul, div functions |
| R2 | Must | div raises ZeroDivisionError when divisor == 0 |
| R3 | Must | evaluate("3 + 4") returns 7; supports +, -, *, / |
| R4 | Nice | Functions accept ints or floats interchangeably |
| R5 | Out | Complex numbers, precedence-aware expressions |

## Open Questions
- **[Affects R3]** Should evaluate() trim whitespace aggressively or require single-space tokens?

## Next Steps
→ Create technical plan.
EOF

note "PRD written. Validate it:"
run "$LOOPY validate prd docs/prd/2026-04-21-calculator-prd.md"

note "Record pipeline state so future skills / resume logic can find it:"
run "$LOOPY state set stage requirements"
run "$LOOPY state set prd docs/prd/2026-04-21-calculator-prd.md"
run "$LOOPY state set feature calculator"
git add -A && git commit -q -m "requirements: initial PRD"

note "Deliberately inject a duplicate requirement ID so you can see the validator catch it:"
cp docs/prd/2026-04-21-calculator-prd.md /tmp/prd_backup.$$.md
sed -i.bak 's/| R3 | Must |/| R1 | Must |/' docs/prd/2026-04-21-calculator-prd.md
rm -f docs/prd/2026-04-21-calculator-prd.md.bak
if "$LOOPY" validate prd docs/prd/2026-04-21-calculator-prd.md; then
  echo "ERROR: validator did not catch duplicate ID"; exit 1
fi
cp /tmp/prd_backup.$$.md docs/prd/2026-04-21-calculator-prd.md
rm -f /tmp/prd_backup.$$.md
note "Validator exited non-zero; restored the good PRD."

# ---------------------------------------------------------------------------
step "Stage 2 — Tech plan"
# ---------------------------------------------------------------------------

mkdir -p docs/plans
cat > docs/plans/2026-04-21-calculator-tech-plan.md <<'EOF'
# Pocket Calculator - Technical Plan

**Date:** 2026-04-21
**Status:** Planning
**PRD:** docs/prd/2026-04-21-calculator-prd.md

## Overview
Implement `src/calculator.py` (pure functions) with pytest coverage in
`tests/test_calculator.py`. Two parent tasks: core arithmetic, then the
`evaluate()` string helper.

## Architecture
Single-file module. No state. `evaluate()` tokenises on whitespace and
dispatches to the four arithmetic functions.

## Subtasks

### Parent 1: Core arithmetic

#### 1.1 Implement add and sub

**Depends on:** none
**Files:** `src/calculator.py`, `tests/test_add_sub.py`

Add `add(a, b)` and `sub(a, b)`. Satisfies R1, R4.

**Test scenarios:** (`tests/test_add_sub.py`)
- add(2, 3) → 5
- add(-1, 1) → 0
- add(0.5, 0.25) → 0.75
- sub(10, 4) → 6

**Verify:** `pytest -q tests/test_add_sub.py`.

#### 1.2 Implement mul and div with zero-guard

**Depends on:** 1.1
**Files:** `src/calculator.py`, `tests/test_mul_div.py`

Add `mul(a, b)` and `div(a, b)`. `div` raises `ZeroDivisionError` when
`b == 0`. Satisfies R1, R2, R4.

**Test scenarios:** (`tests/test_mul_div.py`)
- mul(3, 4) → 12
- mul(2.5, 4) → 10.0
- div(10, 2) → 5
- div(1, 0) → ZeroDivisionError

**Verify:** `pytest -q tests/test_mul_div.py`.

### Parent 2: String evaluate()

#### 2.1 Implement evaluate() dispatch

**Depends on:** 1.2
**Files:** `src/calculator.py`, `tests/test_evaluate.py`

Parse "a op b" (single spaces), dispatch to add/sub/mul/div by operator
symbol. Raise ValueError on malformed input. Satisfies R3.

**Test scenarios:** (`tests/test_evaluate.py`)
- evaluate("3 + 4") → 7
- evaluate("10 - 5") → 5
- evaluate("6 * 7") → 42
- evaluate("8 / 2") → 4.0
- evaluate("8 / 0") → ZeroDivisionError
- evaluate("garbage") → ValueError

**Verify:** `pytest -q tests/test_evaluate.py`.

## Testing Strategy
Pytest only. No integration tests. Coverage target: 100% of `calculator.py`.

## Risks and Mitigations
| Risk | Mitigation |
|------|------------|
| Float precision surprises in evaluate() | Document; do not introduce epsilon comparisons in v1 |
| User passes multi-token expressions | evaluate() raises ValueError; scope boundary documented in PRD |
EOF

note "Each feature subtask has its OWN test file. This lets verify-tests"
note "attribute test counts precisely to each subtask (see README troubleshooting)."
note ""
note "Validate the plan:"
run "$LOOPY validate plan docs/plans/2026-04-21-calculator-tech-plan.md"
run "$LOOPY state set stage plan"
run "$LOOPY state set plan docs/plans/2026-04-21-calculator-tech-plan.md"
git add -A && git commit -q -m "plan: tech plan"

note "Inject a dependency cycle to prove the validator reports the exact path:"
cp docs/plans/2026-04-21-calculator-tech-plan.md /tmp/plan_backup.$$.md
sed -i.bak 's/^\*\*Depends on:\*\* none$/**Depends on:** 2.1/' docs/plans/2026-04-21-calculator-tech-plan.md
rm -f docs/plans/2026-04-21-calculator-tech-plan.md.bak
if "$LOOPY" validate plan docs/plans/2026-04-21-calculator-tech-plan.md; then
  echo "ERROR: validator did not catch cycle"; exit 1
fi
cp /tmp/plan_backup.$$.md docs/plans/2026-04-21-calculator-tech-plan.md
rm -f /tmp/plan_backup.$$.md
note "Cycle caught; plan restored."

# ---------------------------------------------------------------------------
step "Stage 3 — Build (section 1: arithmetic)"
# ---------------------------------------------------------------------------

run "$LOOPY state set stage build"
SEC1=$(git rev-parse HEAD)
say "Section 1 baseline SHA: $SEC1"
run "$LOOPY state section-baseline 1 $SEC1"

mkdir -p src tests
touch src/__init__.py tests/__init__.py

# ---- Subtask 1.1 ----
note "Subtask 1.1: RED (write failing tests first)"
cat > tests/test_add_sub.py <<'PY'
from src.calculator import add, sub

def test_add_positive():    assert add(2, 3) == 5
def test_add_to_zero():     assert add(-1, 1) == 0
def test_add_floats():      assert add(0.5, 0.25) == 0.75
def test_sub():             assert sub(10, 4) == 6
PY
note "Confirm tests fail (no module yet):"
if python3 -m pytest -q tests/test_add_sub.py >/dev/null 2>&1; then
  echo "ERROR: tests passed before implementation existed"; exit 1
fi
say "RED confirmed."

note "Subtask 1.1: GREEN (minimal implementation)"
cat > src/calculator.py <<'PY'
def add(a, b): return a + b
def sub(a, b): return a - b
PY
run "python3 -m pytest -q tests/test_add_sub.py 2>&1 | tail -1"

note "Run the verify-tests gate \u2014 4 scenarios declared, 4 tests present:"
run "$LOOPY verify-tests docs/plans/2026-04-21-calculator-tech-plan.md 1.1"
run "$LOOPY budget add tokens 4200 --stage build --note 'subtask 1.1'"
git add -A && git commit -q -m "feat(calc): add and sub (R1, R4)"
say "Subtask 1.1 committed: $(git rev-parse --short HEAD)"

# ---- Subtask 1.2 ----
note "Subtask 1.2: commit only 2 of 4 scenarios to show the gate catching it"
cat >> src/calculator.py <<'PY'

def mul(a, b): return a * b

def div(a, b):
    if b == 0:
        raise ZeroDivisionError("divide by zero")
    return a / b
PY
cat > tests/test_mul_div.py <<'PY'
from src.calculator import mul, div

def test_mul():       assert mul(3, 4) == 12
def test_div_basic(): assert div(10, 2) == 5
PY
note "verify-tests should FAIL now (2 tests vs 4 scenarios):"
if "$LOOPY" verify-tests docs/plans/2026-04-21-calculator-tech-plan.md 1.2; then
  echo "ERROR: verify-tests did not catch under-coverage"; exit 1
fi
say "Gate fired; add the missing scenarios:"

cat > tests/test_mul_div.py <<'PY'
import pytest
from src.calculator import mul, div

def test_mul():         assert mul(3, 4) == 12
def test_mul_float():   assert mul(2.5, 4) == 10.0
def test_div_basic():   assert div(10, 2) == 5
def test_div_by_zero():
    with pytest.raises(ZeroDivisionError):
        div(1, 0)
PY
run "python3 -m pytest -q tests/test_mul_div.py 2>&1 | tail -1"
run "$LOOPY verify-tests docs/plans/2026-04-21-calculator-tech-plan.md 1.2"
run "$LOOPY budget add tokens 5100 --stage build --note 'subtask 1.2'"
git add -A && git commit -q -m "feat(calc): mul, div + zero guard (R1, R2, R4)"
say "Subtask 1.2 committed: $(git rev-parse --short HEAD)"

# ---------------------------------------------------------------------------
step "Stage 3 — Build (section 2: evaluate)"
# ---------------------------------------------------------------------------

SEC2=$(git rev-parse HEAD)
say "Section 2 baseline SHA: $SEC2"
run "$LOOPY state section-baseline 2 $SEC2"

note "Subtask 2.1: evaluate() dispatcher"
cat >> src/calculator.py <<'PY'

_OPS = {"+": add, "-": sub, "*": mul, "/": div}

def evaluate(expr):
    parts = expr.strip().split()
    if len(parts) != 3:
        raise ValueError(f"expected 'a op b', got: {expr!r}")
    a_str, op, b_str = parts
    if op not in _OPS:
        raise ValueError(f"unknown operator: {op!r}")
    def parse(s):
        try:
            return int(s)
        except ValueError:
            return float(s)
    return _OPS[op](parse(a_str), parse(b_str))
PY

cat > tests/test_evaluate.py <<'PY'
import pytest
from src.calculator import evaluate

def test_evaluate_add():  assert evaluate("3 + 4") == 7
def test_evaluate_sub():  assert evaluate("10 - 5") == 5
def test_evaluate_mul():  assert evaluate("6 * 7") == 42
def test_evaluate_div():  assert evaluate("8 / 2") == 4.0

def test_evaluate_div_zero():
    with pytest.raises(ZeroDivisionError):
        evaluate("8 / 0")

def test_evaluate_garbage():
    with pytest.raises(ValueError):
        evaluate("garbage")
PY
run "python3 -m pytest -q tests/test_evaluate.py 2>&1 | tail -1"
run "$LOOPY verify-tests docs/plans/2026-04-21-calculator-tech-plan.md 2.1"
run "$LOOPY budget add tokens 6800 --stage build --note 'subtask 2.1'"
run "$LOOPY budget add seconds 142 --stage build --note 'total batch time'"
git add -A && git commit -q -m "feat(calc): evaluate() dispatcher (R3)"
say "Subtask 2.1 committed: $(git rev-parse --short HEAD)"

# ---------------------------------------------------------------------------
step "Stage 4 — Section review (text only)"
# ---------------------------------------------------------------------------

note "Scoped diff since section 2 baseline:"
run "git diff --stat $SEC2..HEAD"

REVIEW_BODY="### Strengths
- Clear dispatch table in \`_OPS\` \u2014 easy to extend.
- evaluate() surfaces ValueError with context.

### Testing reviewer
| # | Location | Issue | Fix | Severity |
|---|----------|-------|-----|----------|
| 1 | tests/test_evaluate.py | No test for surrounding whitespace. PRD open question was specifically whitespace handling. | Add evaluate(\"  3 + 4  \") -> 7. | Medium |

---

**Verdict:** Ready with fixes"

printf "%s\n" "$REVIEW_BODY" | "$LOOPY" review-save section-2 --stdin \
  --plan docs/plans/2026-04-21-calculator-tech-plan.md --base-sha "$SEC2"

note "Fix the Medium finding (tied to the PRD's open question):"
cat >> tests/test_evaluate.py <<'PY'

def test_evaluate_trims_whitespace():
    # PRD R3 open question resolved: strip aggressively.
    assert evaluate("  3 + 4  ") == 7
PY
run "python3 -m pytest -q tests/test_evaluate.py 2>&1 | tail -1"
git add -A && git commit -q -m "fix(calc): evaluate() tolerates surrounding whitespace"

# ---------------------------------------------------------------------------
step "Stage 4b — Frontend review with visual evidence"
# ---------------------------------------------------------------------------

note "Simulate a frontend change with a stubbed agent-browser. A real review"
note "would point at a dev-server URL and capture before/after genuine pages."

FAKEBIN="$(mktemp -d)"
cat > "$FAKEBIN/agent-browser" <<'EOS'
#!/usr/bin/env bash
if [ "$1" = "--session" ]; then shift 2; fi
case "$1" in
  open|wait) ;;
  screenshot)
    out="$2"; [ "$out" = "--full" ] && out="$3"
    # Valid 1x1 red PNG.
    printf '\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x02\x00\x00\x00\x90wS\xde\x00\x00\x00\x0cIDATx\x9cc\xf8\xcf\xc0\xc0\xc0\x00\x00\x00\x07\x00\x01\xa7z\xbc\xd3\x00\x00\x00\x00IEND\xaeB\x60\x82' > "$out"
    ;;
esac
EOS
chmod +x "$FAKEBIN/agent-browser"

mkdir -p /tmp/fake_shots_$$
PATH="$FAKEBIN:$PATH" "$LOOPY" browser-capture http://localhost:3000 /tmp/fake_shots_$$/before.png
PATH="$FAKEBIN:$PATH" "$LOOPY" browser-capture http://localhost:3000 /tmp/fake_shots_$$/after.png --full
echo "FCP: 1.2s -> 0.9s
LCP: 2.1s -> 1.6s" > /tmp/fake_shots_$$/lighthouse.txt
say "Captured before.png, after.png, lighthouse.txt"

FE_REVIEW="### Strengths
- Render time improved on the calc demo page.

### Performance reviewer
| # | Location | Issue | Fix | Severity |
|---|----------|-------|-----|----------|
| 1 | web/calc.tsx | FCP 1.2s -> 0.9s (see lighthouse.txt) | none | Info |

---

**Verdict:** Ready to merge"

printf "%s\n" "$FE_REVIEW" | "$LOOPY" review-save frontend-section-2 --stdin \
  --plan docs/plans/2026-04-21-calculator-tech-plan.md \
  --attach /tmp/fake_shots_$$/before.png \
  --attach /tmp/fake_shots_$$/after.png \
  --attach /tmp/fake_shots_$$/lighthouse.txt

note "The review is a directory containing index.md plus the copied evidence:"
run "ls docs/reviews/2026-04-21-frontend-section-2/"
note "The plan now links to both reviews:"
run "grep -A5 '^## Reviews' docs/plans/2026-04-21-calculator-tech-plan.md"

rm -rf "$FAKEBIN" /tmp/fake_shots_$$
git add -A && git commit -q -m "docs: persist section + frontend reviews"

# ---------------------------------------------------------------------------
step "Stage 5 — Wrapup"
# ---------------------------------------------------------------------------

run "$LOOPY state set stage complete"

note "Final pipeline state:"
run "$LOOPY state show"

note "Budget summary:"
run "$LOOPY budget summary"

note "git history end-to-end:"
run "git log --oneline"

note "All pytest suites still green:"
run "python3 -m pytest -q 2>&1 | tail -1"

cat <<EOF

${GREEN}Walkthrough complete.${RESET}
  - PRD          ${DEMO#$(dirname "$DEMO")/}/docs/prd/...
  - Tech plan    ${DEMO#$(dirname "$DEMO")/}/docs/plans/...
  - Reviews      ${DEMO#$(dirname "$DEMO")/}/docs/reviews/... (flat + directory)
  - State        ${DEMO#$(dirname "$DEMO")/}/.loopy/state.yml
  - Commits      $(git log --oneline | wc -l | tr -d ' ')

All artifacts are under: $DEMO
This directory is auto-deleted on exit.
EOF
