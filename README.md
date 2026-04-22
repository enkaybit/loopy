# loopy> Plugin

An engineering execution workflow for Claude Code, Codex, and Gemini CLI — from discovery to plan to implementation, with built-in reviews, tests, iterative optimization, and GitHub pull request (PR) automation.

## Quickstart (5 Minutes)

1. **Install:** `make install`
2. **Launch:** `claude --plugin-dir ~/.claude/plugins/loopy`
3. **Start:** Run `/loopy-requirements` (new or unclear work) or `/loopy-plan` (requirements already clear).
4. **Build:** Run `/loopy-build`, then `/loopy-ship` to create the PR.

That’s it — the full workflow scales from small fixes to large features.

## Guiding Principles

- **Plan before build** — Clear scope and decisions prevent rework.
- **Evidence‑driven iteration** — Review, test, and refine until the outcome is correct.
- **User‑controlled flow** — You choose when to review, fix, or move forward.
- **Quality by default** — Reviews and tests are first‑class, with severity‑based decisions.
- **Modular skills** — Use the full workflow or run any skill standalone.

## Cross‑CLI Portability

All agents use `model: inherit` so Codex, Claude Code, and Gemini CLI each run the workflow on their own default model. This keeps behavior consistent across tools without hard‑coding a vendor‑specific model name.

## Installation (Best Practice)

Use the installer so paths, updates, and uninstalls are consistent across Claude Code, Codex, and Gemini CLI.

```bash
./scripts/install.sh
```

Uninstall:

```bash
./scripts/install.sh --uninstall
```

Skip a target:

```bash
./scripts/install.sh --no-claude
./scripts/install.sh --no-codex
./scripts/install.sh --no-gemini
```

### Make Targets

```bash
make install
make uninstall
make verify
make doctor
make test
```

Skip targets (comma-separated):

```bash
make install SKIP=codex
make doctor SKIP=claude,gemini
```

Run the full test suite in isolated temp directories (installer tests + `loopy`
CLI unit tests + end-to-end demo that walks requirements → plan → build → review →
wrapup against a throwaway repo):

```bash
make test
```

To watch the framework work end-to-end on a tiny real Python project, run the
narrated walkthrough (builds a calculator with real `pytest` runs, prints
commentary between each step):

```bash
tools/loopy-cli/tests/demo_calculator.sh
```

### Loading the Plugin (Claude Code)

After installing, launch Claude Code with the plugin directory:

```bash
claude --plugin-dir ~/.claude/plugins/loopy
```

This makes all `/loopy-*` skills available as slash commands in the session.

To register the plugin permanently so you don't need the flag every time, run this inside Claude Code:

```
/plugin marketplace add ~/.claude/plugins/loopy
```

### Verify

```bash
./scripts/verify.sh
```

Skip checks for a target:

```bash
./scripts/verify.sh --no-claude
./scripts/verify.sh --no-codex
./scripts/verify.sh --no-gemini
```

### Paths Used (Overrides First)

The installer follows tool-specific environment overrides, then falls back to standard user locations:

- **Claude Code**: `CLAUDE_HOME` → `~/.claude` (plugin installed to `~/.claude/plugins/loopy`)
- **Codex**: `CODEX_HOME` → `~/.codex` (skills installed to `~/.codex/skills`)
- **Gemini CLI**: `GEMINI_HOME` → `~/.gemini` (skills installed to `~/.gemini/skills`)

If your environment uses different locations, set the corresponding `*_HOME` variable before running the installer.

### Requirements

- `git`
- `python3` (stdlib only) — required for the `loopy` helper CLI (schema validator, state tracker, review persistence, budget)
- `gh` (GitHub CLI) optional — required only for PR creation and PR feedback workflows. **Auth before running wrapup** — see `docs/secrets.md` for token sources, required scopes, and agent secret-handling rules.
- `agent-browser` (optional, only for `loopy-browse`)
- `temporal` (optional, only for Temporal task system support). When Temporal is not installed, loopy falls back to built-in tasks stored in `.loopy/state.yml` (see `docs/builtin-task-format.md`).

### Temporal Task System (Optional)

Loopy can use Temporal OSS as a task system for multi-agent workflows. See
`docs/temporal-task-system.md` for setup and commands.

## `loopy` CLI (Helper)

Installed alongside the plugin at `~/.local/bin/loopy`. Provides the structural
checks that skills rely on for predictability:

| Command | Purpose |
|---------|---------|
| `loopy validate prd <path>` | Schema-check a PRD (headers, Requirements table, Scope subsections, open-question tags). |
| `loopy validate plan <path>` | Schema-check a tech plan (headers, subtask fields, numbering gaps, dependency references, cycles, test-file wiring for feature subtasks). |
| `loopy state show [--json]` | Dump `.loopy/state.yml` (branch / stage / section baselines / reviews / budget). |
| `loopy state set <key> <value>` | Update a scalar (supports dotted paths like `plan.path`). |
| `loopy state section-baseline <n> <sha>` | Record a plan section's baseline commit for scoped reviews. |
| `loopy review-save <scope> --stdin --plan <path> [--attach FILE]` | Persist a review to `docs/reviews/`, link it from the plan, and record it in state. `--attach` (repeatable) copies screenshots / logs into the review directory and auto-generates a `## Evidence` section with embedded images. |
| `loopy verify-tests <plan> <subtask>` | Count leaf test functions in the declared test file and compare with the plan's scenarios. |
| `loopy browser-capture <url> <out> [--full] [--session NAME]` | Thin wrapper over `agent-browser`: open URL, screenshot to `<out>`. Exits 3 if `agent-browser` isn't installed, so skills can degrade gracefully. Used by `/loopy-spike` and `/loopy-code-review` for visual evidence. |
| `loopy budget add <kind> <amount>` / `loopy budget summary` | Track `tokens` / `seconds` / `usd` across stages. |

All commands are pure Python (stdlib only), idempotent, and safe to run from
skills or CI. See `docs/builtin-task-format.md` for the state-file schema and
`docs/secrets.md` for secret handling.

## Versioning & Releases

This project uses SemVer. The current version lives in `.claude-plugin/marketplace.json`.

Release checklist:
- `docs/release-checklist.md`
- `docs/loopy-internals-architecture.md` (internals architecture + `/loopy-build` sequence)
- `docs/builtin-task-format.md` (state-file / built-in task schema)
- `docs/secrets.md` (auth & secret-handling rules for `gh`, registries, and agents)
- `CHANGELOG.md`

## FAQ

**Where does it install by default?**  
By default it installs to standard user locations:

- Claude Code: `~/.claude/plugins/loopy`
- Codex: `~/.codex/skills`
- Gemini CLI: `~/.gemini/skills`

**Can I override install paths?**  
Yes. Set the env vars before install:

```bash
CLAUDE_HOME=/path/to/claude \
CODEX_HOME=/path/to/codex \
GEMINI_HOME=/path/to/gemini \
make install
```

**Is it per‑user or per‑repo?**  
Per‑user. It installs into the developer’s user‑level CLI directories (e.g., `~/.claude`, `~/.codex`, `~/.gemini`) so it’s available across all projects.

**Can I use it across multiple repositories?**  
Yes. Because loopy> installs per‑user, not per‑repo, a developer can use it in any number of repositories without reinstalling. When they run the skills, artifacts are created inside the current repo: PRDs and plans under `docs/`, review reports under `docs/reviews/`, autoloop experiment logs under `docs/autoloop/`, and per-branch pipeline state under `.loopy/state.yml` (committing this file is optional — see `docs/builtin-task-format.md`).

**What happens when a new developer joins the same repo?**  
1. Install once on their machine: `make install` then `make verify`.  
2. Clone the repo as usual.  
3. Run `/loopy-requirements`, `/loopy-plan`, or `/loopy-build`; outputs go to `docs/` and commits go to their branch.  
4. PRDs and plans are committed, so everyone sees the same context.

The repo remains the shared source of truth, while the plugin is installed per‑developer.

**Can I use loopy> in Cursor?**  
Yes. Use the Cursor terminal to run Claude Code, Codex, or Gemini CLI and invoke the `/loopy-*` commands there.

## New Developer Workflow

### Without Temporal (built-in tasks)

1. Install loopy:

```bash
make install
```

2. Create requirements or plan:

```text
/loopy-requirements
/loopy-plan
```

3. Build (uses built-in tasks automatically):

```text
/loopy-build
```

4. Wrap up (tests + PR):

```text
/loopy-ship
```

### With Temporal (durable multi-agent tasks)

1. Install loopy + task binaries:

```bash
make install
```

2. Start Temporal (local dev) or point to team server:

Local:

```bash
make temporal-dev
```

Team:

```bash
export TEMPORAL_ADDRESS=temporal.company.net:7233
export TEMPORAL_NAMESPACE=team
export TEMPORAL_TASK_QUEUE=loopy-task-queue
export LOOPY_TASK_WORKER_ID="$USER@$(hostname)"
```

3. Start the worker:

```bash
make taskd
```

4. Create or update plan:

```text
/loopy-plan
```

5. Import plan tasks into Temporal:

```bash
loopy-tasks import --plan docs/plans/YYYY-MM-DD-<feature>-tech-plan.md
```

6. Build (Temporal used automatically if `loopy-tasks status` succeeds):

```text
/loopy-build
```

7. Wrap up:

```text
/loopy-ship
```


## The Workflow

```
1) /loopy-requirements
   - Output: PRD
   - Optional: /loopy-plan-review (1+ rounds)
   - Optional: /loopy-research, /loopy-spike

2) /loopy-plan
   - Output: Tech Plan
   - Optional: /loopy-plan-review (1+ rounds)

3) /loopy-build
   - Execute plan in dependency‑ordered batches
   - Optional: incremental /loopy-code-review between batches
   - Required: /loopy-code-review per plan section
   - Cleanup: code-simplifier pass
   - Final: /loopy-code-review (all changes)
   - Finish: /loopy-ship → verify tests → PR
```

Each stage produces an artifact, offers iterative review, and hands off when the user is ready. Re-entry is supported — run any skill again at any point.

### Artifacts

| Artifact | Path | Produced by |
|----------|------|-------------|
| PRD | `docs/prd/YYYY-MM-DD-<topic>-prd.md` | `/loopy-requirements` |
| Tech plan | `docs/plans/YYYY-MM-DD-<topic>-tech-plan.md` | `/loopy-plan` |
| Review report | `docs/reviews/YYYY-MM-DD-<scope>.md` | `/loopy-code-review` (via `loopy review-save`) |
| Spike doc | `docs/spikes/YYYY-MM-DD-<topic>-spike.md` | `/loopy-spike` |
| Experiment log | `docs/autoloop/<program>/log.md` | `/loopy-optimize` |
| Pipeline state | `.loopy/state.yml` | all stages (via `loopy state`) |
| Autoloop programs | `.loopy/autoloop/programs/<name>.md` | user / `/loopy-optimize` |

PRDs, plans, spike docs, review reports, and experiment logs are always committed. `.loopy/state.yml` is **optional to commit** — teams that want shared pipeline history can commit it; teams that prefer per-developer state can add it to `.gitignore`.

For the control-flow diagram (`/loopy-build` sequence, autoloop loop), see `docs/loopy-internals-architecture.md`.

## Use Case: Feature Delivery (Core Workflow)

**Goal:** Take a feature from idea → plan → code → PR with clear scope, tests, and reviews.

**What it does:** Loopy produces the PRD and plan, executes the work in safe batches, runs reviews, and ends with a ready‑to‑merge GitHub PR.

**When to use:** Any non‑trivial feature or change that needs clear scope and reliable delivery.

### How to use it

1. **Define the problem:** Run `/loopy-requirements` to produce a PRD (requirements, scope, open questions).
2. **Create the plan:** Run `/loopy-plan` to produce a Tech Plan with concrete subtasks and tests.
3. **Build safely:** Run `/loopy-build` to execute the plan with TDD and commits per subtask.
4. **Review and wrap:** Use `/loopy-code-review` as needed, then `/loopy-ship` to verify tests and create the PR.

### Example

```text
Feature: Add audit log export
1) /loopy-requirements → PRD created
2) /loopy-plan → plan + test scenarios
3) /loopy-build → batches, tests, commits
4) /loopy-ship → tests pass, PR created
```

## Use Case: Small Changes / Quick Fixes

**Goal:** Ship a small change without heavy overhead.

**How to use it**
1. **Skip requirements discovery:** If the scope is obvious, start at `/loopy-plan` or go straight to `/loopy-build`.
2. **Keep it light:** Use a short plan or a single batch, then run `/loopy-code-review` only if the change is risky.
3. **Wrap up:** Use `/loopy-ship` to verify tests and create the PR.

## Use Case: Day-to-Day Developer Flow

**Goal:** Provide a simple, repeatable daily workflow from idea → plan → code → PR.

**What it does:** Loopy guides a developer through clear steps so work stays scoped, reviewed, and ready to merge.

### First Day (New Developer)

Assuming GitHub access and IDE are already set up:

1. **Install once:** Run `make install` (or `./scripts/install.sh`).
2. **Start with a small task:** Pick a low‑risk issue and run `/loopy-requirements` to produce a PRD.
3. **Create the plan:** Run `/loopy-plan` to translate the PRD into a Tech Plan.
4. **Implement safely:** Run `/loopy-build` to execute subtasks with tests and commits.
5. **Finish cleanly:** Run `/loopy-ship` to verify tests and create the PR.

### Typical Day

1. **Start the day:** If the task is new or unclear, run `/loopy-requirements` to produce a PRD.
2. **Plan the work:** Run `/loopy-plan` to create the Tech Plan with concrete subtasks and tests.
3. **Build in batches:** Run `/loopy-build` to execute subtasks, write tests, and commit per step.
4. **Review and wrap:** If needed, run `/loopy-code-review`, then finish with `/loopy-ship` to verify tests and create the PR.

**Example**

```text
09:00 — /loopy-requirements (PRD created)
10:00 — /loopy-plan (plan + test scenarios)
11:00 — /loopy-build (batch 1 + tests)
14:00 — /loopy-build (batch 2 + tests)
16:00 — /loopy-code-review (fix selected severities)
17:00 — /loopy-ship (tests pass, PR created)
```

## Use Case: Team Workflow

**Goal:** Keep the whole team aligned on scope, quality, and delivery with shared artifacts and consistent reviews.

**How it works in a team**
- **Shared artifacts:** PRDs and Tech Plans are committed so everyone sees the same source of truth.
- **Consistent reviews:** Plan and code reviews use the same severity model, so feedback is predictable.
- **Clear handoffs:** Anyone can pick up a task because plans and decisions are explicit.
- **Decision visibility:** Open questions and scope boundaries are documented early and revisited as needed.

**Team routine (recommended)**
1. **Before kickoff:** Create or update the PRD with `/loopy-requirements`.
2. **Before coding:** Create or update the Tech Plan with `/loopy-plan`.
3. **During build:** Use `/loopy-build` so batches, tests, and reviews are consistent.
4. **Before merge:** Use `/loopy-code-review` and `/loopy-ship` for final quality gates.

## Use Case: Iterative Optimization (Autoloop)

**Goal:** Autonomously improve target files toward a measurable metric through repeated propose-evaluate-accept/reject cycles.

**What it does:** Autoloop reads a program definition (goal, target files, evaluation command), proposes targeted changes, evaluates them against a metric, and creates draft PRs for improvements. Regressions are automatically rejected.

**When to use:** Optimizing test coverage, reducing bundle size, improving performance benchmarks, or any other measurable code quality metric.

### How to use it

1. **Create a program:** Run `/loopy-optimize` — if no programs exist, it guides you through creating one in `.loopy/autoloop/programs/`.
2. **Run iterations:** Select the program and iteration mode (single, N iterations, or until target met).
3. **Review draft PRs:** Each accepted improvement becomes a draft PR for human review before merging.

### Example

```text
Optimization: Increase test coverage for auth module
1) /loopy-optimize → program created, baseline: 62% coverage
2) Iteration 1 → added edge case tests → 68% → accepted, draft PR created
3) Iteration 2 → added error path tests → 71% → accepted, draft PR created
4) Iteration 3 → refactored test helpers → 70% → rejected (regression)
5) Iteration 4 → added integration tests → 74% → accepted, draft PR created
```

## Use Case: Existing Project Adoption

**Goal:** Use loopy> on a live codebase without disrupting current workflows.

**How to use it**
1. **No repo changes required:** Loopy works with your existing structure; it writes docs under `docs/` only.
2. **Install once:** Run `make install` (or `./scripts/install.sh`).
3. **Pick a real task:** Choose an issue or PR‑sized change already in your backlog.
4. **Decide the entry point:** If requirements are unclear, run `/loopy-requirements`. If requirements are clear, skip to `/loopy-plan`.
5. **Plan in‑repo:** Let Loopy write the PRD/plan into `docs/` so the team can review it on GitHub.
6. **Implement on a branch:** Run `/loopy-build` to execute the plan with tests and commits.
7. **Wrap up:** Run `/loopy-ship` to verify tests and create the PR.

**Quick example**

```text
Existing project: add audit log export
Start: /loopy-plan (requirements already known)
Build: /loopy-build (tests + commits)
Finish: /loopy-ship (PR created)
```

### Requirements

Use requirements discovery to turn a vague idea into a clear, shared understanding of what to build.

**What it does**
- Asks 2–3 focused questions to map the problem.
- Proposes a few high‑level directions and helps you choose.
- Produces a PRD that captures scope, priorities, and open questions.

**What you get (PRD)**
- Requirements grouped by priority: Core / Must‑Have / Nice‑to‑Have / Out.
- Scope split into In Scope and Boundaries.
- Open questions tagged by what they affect.
- High‑level technical direction only (no implementation details).

**What happens next**
- Optional review with 4 reviewers (clarity, completeness, specificity, YAGNI).
- If questions remain, use `/loopy-research` (answers exist) or `/loopy-spike` (answers must be experienced).
- When ready, move to `/loopy-plan`.

**When to skip**
- If requirements are already clear and agreed, go straight to `/loopy-plan`.

### Planning

Use planning to turn a PRD into a clear, executable implementation plan.

**What it does**
- Scans the codebase for patterns and affected areas.
- Resolves PRD open questions that depend on codebase context.
- Defines architecture decisions, file paths, and test scenarios.

**What you get (Tech Plan)**
- A plan with ordered subtasks and dependencies.
- Concrete test scenarios with inputs and expected outputs.
- No pre‑written implementation code (the plan describes what and where).

**What happens next**
- Optional plan review (clarity, completeness, specificity, YAGNI).
- Fix issues, then move to `/loopy-build`.

**When to skip**
- If a solid plan already exists, go straight to `/loopy-build`.

### Build

Use build to execute the plan safely and consistently.

**What it does**
- Executes subtasks in dependency order.
- Uses TDD for feature work and commits per subtask.
- Runs code reviews at section boundaries and at the end.

**What you get**
- Working code and tests aligned to the plan.
- A final review and cleanup pass.
- A ready‑to‑create GitHub PR.

**What happens next**
- If reviews find issues, fix the selected severities.
- When clean, run `/loopy-ship` to verify tests and create the PR.

**When to pause**
- If reviews surface Critical or High issues, stop and fix before continuing.

### Stage Boundaries

Each stage has a clear scope — what it produces and what it deliberately leaves to the next stage:

| Stage | Produces | Does | Does NOT |
|-------|----------|------|----------|
| **Requirements** | PRD | Explore problem space, make directional choices, capture prioritized requirements and scope boundaries | Specify libraries, schemas, API endpoints, or implementation details |
| **Planning** | Tech Plan | Structure subtasks with dependencies, file paths, test scenarios, and architecture decisions | Pre-write implementation code — describe what and where, implementer writes the code |
| **Build** | Code → PR | Execute plan with dependency-aware batching, TDD, code reviews, test verification, PR creation | Deploy or release — the workflow ends at PR creation |

### Reviews

Reviews are user-driven:

- **Offered, never forced** — Every review is presented as a choice. The user can skip.
- **Severity-based acceptance** — Findings grouped by severity (Critical / High / Medium / Low). User selects which levels to fix — not all-or-nothing.
- **User-controlled loop** — After fixes, user chooses to re-review or continue. No automatic re-review.
- **Agent teams with fallback** — Reviewers run as an agent team so they can cross-validate findings (a YAGNI reviewer can push back on completeness suggestions). When agent teams aren't available, reviews automatically fall back to parallel subagents.
- **Scaled to scope** — Full review for substantial work, quick review for moderate changes, skip for trivial config edits.

## Design Decisions

| Decision | Rationale |
|----------|-----------|
| PRD captures direction, not implementation | High-level technical direction ("real-time via WebSockets") belongs in the PRD. Specific libraries and database schemas don't — that's tech planning's job. |
| Requirements are prioritized, not flat | Requirements grouped as Core / Must-Have / Nice-to-Have / Out. Priority drives implementation scope and prevents everything from being treated as equally important. |
| PRD is a living document | Tech planning and implementation update the PRD when they hit new constraints. Changes are noted with rationale. |
| Tech plan describes what, not how | Plans capture architecture, query strategies, and test scenarios. They don't pre-write method bodies — that's brittle and gets followed blindly. The implementer writes the actual code. |
| Dependency-aware batch execution | Subtasks are grouped by their dependency graph. Each batch runs concurrently, but batches execute sequentially. Not one-at-a-time (too slow), not all-at-once (ignores ordering). |
| Incremental reviews for large sections | Plan sections with 6+ subtasks get code review offers between batches. Catches issues before later batches build on flawed code. |
| Severity-based fix acceptance | Not all review findings warrant fixing. User picks which severity levels to address. Keeps the user in control of review scope. |
| Docs committed at every checkpoint | PRDs, plans, and spike docs are committed incrementally — not left as uncommitted changes across workflow stages. A branch safety gate before the first commit prevents accidental commits to the default branch. |

## Skills

The core workflow skills use a `loopy-` prefix in their name (e.g., `/loopy-requirements`). The slash command menu shows skill names from all installed plugins — if another plugin also has a "requirements" skill, you'd see duplicate entries. The prefix makes ours immediately identifiable. Substring search still works — typing `/req` finds `/loopy-requirements`.

### Core Workflow

| Skill | Output | Description |
|-------|--------|-------------|
| `/loopy-requirements` | PRD | Collaborative exploration of problem space, broad directions, deep Q&A |
| `/loopy-research` | Updated PRD | Research open questions from PRD or user — parallel investigation, findings synthesis |
| `/loopy-spike` | Spike Doc + Updated PRD | Build and validate uncertain requirements — throwaway prototypes, user feedback loops |
| `/loopy-plan` | Tech Plan | Structure PRD into dependency-ordered subtasks with file paths, test scenarios, architecture decisions |
| `/loopy-plan-review` | Review Report | 4 specialized reviewers analyze PRDs and tech plans via agent team with cross-validation |
| `/loopy-build` | Code → PR | Dependency-aware batch execution with TDD, incremental and final code reviews, then wrapup |
| `/loopy-code-review` | Review Report | 5 specialized reviewers with severity ratings, full or quick mode, language-agnostic |
| `/loopy-optimize` | Draft PRs + Experiment Log | Autonomous iterative optimization — propose, evaluate, accept/reject changes toward a measurable metric |

### Internal

| Skill | Description |
|-------|-------------|
| `/loopy-ship` | Test verification, final review, PR creation — invoked by implementing or standalone ("create a PR") |
| `/loopy-workspace` | Workspace isolation — invoked by implementing and spike during setup |

### Supporting

| Skill | Description |
|-------|-------------|
| `/loopy-address-review` | Resolve PR review comments systematically — use after a review or when addressing PR threads |
| `/loopy-browse` | Browser automation using Vercel's agent-browser CLI — use for web flows and screenshots |

## Agents

### Review Agents (Plan Review)

4 specialized reviewers analyze documents via agent team:

| Agent | Focus |
|-------|-------|
| `clarity-reviewer` | Vague language, ambiguity, structure |
| `completeness-reviewer` | Missing sections, gaps, dependencies |
| `specificity-reviewer` | Actionability, concrete details |
| `yagni-reviewer` | Scope creep, over-specification |

### Review Agents (Code Review)

5 specialized reviewers analyze code via agent team:

| Agent | Focus |
|-------|-------|
| `correctness-reviewer` | Logic errors, edge cases, bugs, silent failures, plan compliance |
| `security-reviewer` | Vulnerabilities, auth, input validation, project conventions |
| `performance-reviewer` | Algorithmic complexity, queries, memory, caching |
| `simplicity-reviewer` | YAGNI, over-engineering, unnecessary abstraction |
| `testing-reviewer` | Coverage, test quality, edge cases, plan test scenarios |

Review agents run as teammates who can cross-validate findings — a security reviewer can flag missing test coverage, a YAGNI reviewer can push back on completeness suggestions. When agent teams are unavailable, reviews fall back to parallel subagent execution.

### Workflow Agents

| Agent | Purpose |
|-------|---------|
| `task-worker` | Executes subtasks — reads plan context, loads patterns, implements with TDD, commits |
| `code-simplifier` | Behavior-preserving simplification pass on changed files before final review |
| `branch-setup-worker` | Creates git worktrees or branches for isolation |
| `pr-creator-worker` | Creates pull requests following repo conventions (used by `/loopy-ship`) |
| `autoloop-optimizer` | Proposes and implements targeted changes to optimize files toward a measurable goal (used by `/loopy-optimize`) |

Workflow agents run as isolated subagents. Each `task-worker` gets its own context window with just its subtask from the plan.



## Troubleshooting

**`loopy: command not found` after `make install`**  
The `loopy` CLI is installed to `~/.local/bin` (or `LOOPY_TASK_BIN_DIR` if set). Ensure that directory is on your `PATH`:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

Add the line to `~/.zshrc` / `~/.bashrc` to make it persistent. Re-run `make verify` to confirm.

**Plan validation fails on a pre-existing plan**  
The schema validator (`loopy validate plan <path>`) was introduced after v1.0. Older plans may legitimately not conform (missing `**PRD:**` header, no standardized subtask format, etc.). Options:

- Run `loopy validate plan <path> --json` to get structured output you can inspect or feed to another tool.
- Fix the plan in place — most errors are small header/field additions.
- Skip validation for legacy plans; the build skill will still run, but you lose the pre-flight gate.

**`.loopy/state.yml` showing up as an uncommitted change**  
It's created per repo by the CLI as you run skills. Committing it is a team choice — commit for shared pipeline history, or add to `.gitignore` for per-developer state. See `docs/builtin-task-format.md` for the schema.

**`loopy verify-tests` passes even though a subtask is missing tests**  
`verify-tests` counts leaf test functions (`it(...)`, `test(...)`, `def test_*`, `func Test*`, `#[test]`) in the test file declared by the subtask's `**Test scenarios:** (path/to/test)` parenthetical, and compares with the number of scenario bullets in the plan. It cannot attribute specific tests to specific subtasks. When multiple subtasks share one test file (e.g., 1.1 and 1.2 both writing to `tests/test_foo.py`), the gate can pass for a subtask even though *its* scenarios weren't covered — as long as the file's total test count exceeds the scenario count for the subtask being checked.

**Mitigations:**
- **Preferred:** give each feature subtask its own test file (`tests/test_foo_1_1.py`, `tests/test_foo_1_2.py`). The plan template recommends this. The gate then becomes precise.
- If subtasks must share a file, rely on the `task-worker` agent's stop-condition check that every declared scenario has a corresponding test case — that check is prose-based but runs per subtask.
- Do not treat `verify-tests OK` as proof of coverage; treat it as a floor check.

**Gemini CLI: “Unknown command: /loopy-requirements”**  
Gemini CLI reserves `/` for built‑in commands; loopy skills are managed via `/skills`, not invoked as slash commands. Use `/skills list` to confirm discovery, `/skills reload` after installs/renames, and `/skills enable <name>` if a skill is disabled. Then invoke the skill in natural language (e.g., “Use the loopy‑requirements skill to create a PRD for …”).

**Commands to try (Gemini CLI):**

```bash
/skills list
/skills reload
/skills enable loopy-requirements
```

**Claude Code: plugin not showing / skills missing**  
Run Claude Code with the plugin directory explicitly:

```bash
claude --plugin-dir ~/.claude/plugins/loopy
```

This will make skills available as slash commands like:
- `/loopy:loopy-requirements`
- `/loopy:loopy-plan`
- `/loopy:loopy-build`
- `/loopy:loopy-code-review`
- etc.

To make it persistent, run this inside Claude Code:

```
/plugin marketplace add ~/.claude/plugins/loopy
```

Then install it from the marketplace via `/plugin`.
