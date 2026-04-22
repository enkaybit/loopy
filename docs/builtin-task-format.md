# Built-in Task Format

When Temporal is not available, `/loopy-build` falls back to "built-in tasks".
Built-in tasks are stored inside `.loopy/state.yml` — the same file that tracks
branch / stage / section baselines / reviews / budget. This keeps the workflow
state consolidated in one place and allows `loopy state show` to act as a
single source of truth for a branch.

## Location

`.loopy/state.yml` (at the repo root). The file is created on demand by skills
and the `loopy` CLI. Committing it is optional — teams that want shared
pipeline history can commit it; teams that prefer to keep it local can add it
to `.gitignore`.

## Schema (YAML subset)

```yaml
schema_version: 1
branch: feature/audit-log-export
feature: audit-log-export
prd: docs/prd/2026-04-20-audit-log-export-prd.md
plan: docs/plans/2026-04-20-audit-log-export-tech-plan.md
stage: build                 # requirements | plan | build | review | wrapup | complete
last_updated: "2026-04-20T09:12:00Z"

section_baselines:
  "1": abc1234
  "2": def5678

tasks:                       # built-in task list (used when Temporal is absent)
  - id: "1.1"
    title: "Add CSV exporter service"
    depends_on: []
    files:
      - app/services/audit_exporter.ts
      - app/services/audit_exporter.test.ts
    test_file: app/services/audit_exporter.test.ts
    status: done             # pending | ready | in_progress | done | blocked
    commit: 1a2b3c4
    started_at: "2026-04-20T08:00:00Z"
    completed_at: "2026-04-20T08:42:00Z"
  - id: "1.2"
    title: "Add controller endpoint"
    depends_on: ["1.1"]
    files:
      - app/controllers/audit_controller.ts
      - app/controllers/audit_controller.test.ts
    test_file: app/controllers/audit_controller.test.ts
    status: in_progress

reviews:
  - scope: section-1
    path: docs/reviews/2026-04-20-section-1.md
    recorded_at: "2026-04-20T08:50:00Z"
    plan: docs/plans/2026-04-20-audit-log-export-tech-plan.md
    base_sha: abc1234

budget:
  totals:
    tokens: 152340
    seconds: 842.0
  entries:
    - kind: tokens
      amount: 84000
      stage: plan
      note: "planning conversation"
      at: "2026-04-20T06:30:00Z"
    - kind: seconds
      amount: 421.0
      stage: build
      note: "batch 1 task-worker"
      at: "2026-04-20T08:42:00Z"
```

## Field reference

### Top level

| Key | Type | Notes |
|-----|------|-------|
| `schema_version` | int | `1`. Bumped when the schema changes incompatibly. |
| `branch` | string | git branch the pipeline is running on. |
| `feature` | string (optional) | Short label for this feature. |
| `prd` | string (optional) | Path to the PRD markdown, relative to repo root. |
| `plan` | string (optional) | Path to the tech plan markdown, relative to repo root. |
| `stage` | string | Current pipeline stage. |
| `last_updated` | RFC3339 UTC | Set automatically by the `loopy` CLI on every write. |

### `section_baselines`

Maps plan-section number (the parent number like `"1"`, `"2"`) to the commit
SHA captured at the start of that section. Used by `loopy-build` to scope
review diffs (`git diff <baseline>..HEAD`).

### `tasks` (built-in task list)

Each entry corresponds to one subtask from the tech plan.

| Field | Required | Notes |
|-------|----------|-------|
| `id` | yes | `"Parent.Subtask"`, matches plan numbering. |
| `title` | yes | Free text. |
| `depends_on` | yes | List of subtask ids (may be empty). |
| `files` | yes | List of repo-relative paths. Mirrors the plan's `**Files:**`. |
| `test_file` | no | Path from `**Test scenarios:** (…)`. Required for feature subtasks. |
| `status` | yes | `pending` → `ready` → `in_progress` → `done` / `blocked`. |
| `commit` | no | SHA of the commit produced by the subtask (set on `done`). |
| `started_at` / `completed_at` | no | RFC3339 UTC timestamps. |
| `notes` | no | Free-form list of strings — e.g., reasons for `blocked`. |

### `reviews`

Appended by `loopy review-save`. Each entry:

| Field | Notes |
|-------|-------|
| `scope` | Label such as `section-1` / `final` / `branch`. |
| `path` | Repo-relative path to the saved review markdown. |
| `recorded_at` | RFC3339 UTC. |
| `plan` | Plan path the review was against (optional). |
| `base_sha` | Baseline SHA the review was scoped to (optional). |

### `budget`

Free-form cost counters. `totals` is a flat map from `kind` (`tokens` /
`seconds` / `usd`) to a running total. `entries` records each individual
contribution.

## Status transitions

```
pending  ->  ready          (all depends_on are done)
ready    ->  in_progress    (task-worker claimed it)
in_progress -> done          (commit landed + tests verified)
in_progress -> blocked       (external blocker; record reason in notes)
blocked  ->  ready          (blocker resolved)
```

Skills manipulate this lifecycle through the `loopy state` subcommands
(`set`, `section-baseline`, `review-add`). When Temporal is available, the
same fields are mirrored from Temporal state; the built-in list is still
useful as a local cache.

## Compatibility with Temporal

When Temporal is used:
- The `tasks` list in `.loopy/state.yml` is optional — Temporal is the system
  of record. Skills may still write a light summary here for offline review.
- `section_baselines`, `reviews`, and `budget` are always recorded in state
  (they are not Temporal-native concepts).

## CLI touch-points

- `loopy state show` — pretty-print the full state.
- `loopy state show --json` — machine-readable form, for dashboards/CI.
- `loopy state set <key> <value>` — update scalar fields (supports
  dotted paths like `plan.path`).
- `loopy state section-baseline <section> <sha>` — record a baseline.
- `loopy state review-add <scope> <path>` — record a review reference.
- `loopy review-save <scope> --stdin --plan <path>` — persist a review report
  to `docs/reviews/` **and** append it to state and the plan. Supports
  repeatable `--attach` for screenshots/logs (switches to directory mode).
- `loopy verify-tests <plan> <subtask>` — count leaf test functions in the
  subtask's declared test file and compare with its scenarios. See the note
  on shared test files below.
- `loopy browser-capture <url> <out>` — wrapper over `agent-browser`. Exits
  `3` if `agent-browser` isn't installed so callers can degrade gracefully.
- `loopy budget add <kind> <amount> --stage <stage>` / `loopy budget summary` —
  track spend.

All writes update `last_updated` automatically.

### `verify-tests` accuracy note

`verify-tests` counts leaf test functions (`it(...)`, `test(...)`,
`def test_*`, `func Test*`, `#[test]`) in the test file declared by the
subtask's `**Test scenarios:** (path/to/test)` parenthetical, and compares
with the count of scenario bullets in the plan.

**It does not attribute tests to specific subtasks.** When multiple subtasks
share one test file, the gate can pass for a subtask even though its own
scenarios weren't covered — as long as the file's total test count exceeds
that subtask's scenario count. The gate becomes precise when each feature
subtask has its own test file (the recommended pattern in the plan
template). Treat `verify-tests OK` as a floor check, not proof of coverage.
