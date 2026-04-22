---
name: loopy-optimize
description: This skill should be used when the user says "optimize toward", "iterate on metrics", "continuous improvement", "run autoloop", or wants to run autonomous iterative optimization on target files toward a measurable goal.
---

# Optimize: Autonomous Iterative Optimization

Run autonomous optimization loops that improve target files toward a measurable goal. Each iteration proposes a change, evaluates it against a metric, and promotes improvements as draft PRs.

## When to Use

- When the user wants to iteratively optimize code toward a measurable metric (test coverage, performance, bundle size, etc.)
- When a program definition exists in `.loopy/autoloop/programs/`
- When the user wants to create a new optimization program
- Can be invoked standalone or on a schedule via external tools

## Key Principles

1. **Measure before changing** — Establish a baseline metric before the first optimization attempt
2. **One change per iteration** — Small, focused changes enable clear metric attribution
3. **Automatic rejection** — Metric regressions are rejected without human intervention
4. **Human review required** — All improvements go through draft PRs; nothing merges automatically
5. **History-aware proposals** — The optimizer reads experiment history to avoid repeating rejected approaches

## Workflow

### Phase 0: Detect Resume

1. Scan `docs/autoloop/` for directories containing experiment logs with `Status: In Progress`.
2. For each in-progress log, check if the corresponding program still exists in `.loopy/autoloop/programs/`.
3. If active programs found, present them:

> **Active autoloop programs:**
> - **[name]** — [goal summary], [N] iterations, last metric: [value] ([date])

4. Ask the user:
   - A) Resume [program name] (continue from last iteration)
   - B) Start a new iteration on a discovered program
   - C) Create a new program
5. If resuming: load the experiment log. Check if the last iteration is incomplete (no `**Result:**` in the last iteration detail). If incomplete: offer to re-evaluate (if worktree exists) or discard and start fresh. If complete: continue from the next iteration number. Skip to Phase 2.
6. If no active programs: proceed to Phase 1.

### Phase 1: Discover and Configure Programs

**Program discovery:**

1. Scan `.loopy/autoloop/programs/` for `*.md` files.
2. Parse each program file. Validate that it has the required sections: Goal, Target, Evaluation (with Command, Metric Extraction, Direction). See the program template in `references/program-template.md`.
3. Skip programs with `Status: Paused` or `Status: Archived`.

**No programs found:**

4. Offer to create one: "No autoloop programs found. Would you like to create one?"
5. Guide the user through defining the program:
   - **Name:** used as the filename and program identifier
   - **Goal:** what metric to optimize and in which direction
   - **Target files:** which files the optimizer may modify
   - **Evaluation command:** shell command that produces the metric
   - **Metric extraction:** how to parse the numeric metric from command output
   - **Direction:** minimize or maximize
   - **Constraints:** additional rules (optional)
   - **Stop conditions:** target metric, max iterations, max consecutive rejections
6. Save to `.loopy/autoloop/programs/<name>.md` using the program template.
7. Commit the program file: `git add .loopy/autoloop/programs/<name>.md && git commit -m "autoloop: add program <name>"`

**Programs found:**

8. Present programs with name, goal, target files, and current metric (from experiment log if one exists, or "no history" for first run).

**Program selection:**

9. If the user invoked with a specific program name (e.g., `/loopy-optimize my-program`), use that program.
10. If multiple programs and no argument: ask which program(s) to run. Support "all" for running each program sequentially.

**Iteration mode:**

11. Ask the user:
    - A) Run one iteration (default)
    - B) Run N iterations (user specifies N)
    - C) Run until target metric is met or consecutive failure limit is reached

**Confirm before execution:**

12. Present the execution plan:

> **Ready to run autoloop:**
> - Program: [name]
> - Goal: [goal]
> - Target files: [list]
> - Evaluation: [command summary]
> - Direction: [minimize/maximize]
> - Current metric: [value or "no baseline yet"]
> - Mode: [single / N iterations / until target]

13. Get user confirmation before proceeding to Phase 2.

### Phase 2: Execute Iteration (repeat per iteration, per program)

This is the core optimization loop. Each iteration follows the cycle: **review history, propose change, implement on branch, evaluate, accept or reject.**

#### Step 1: Review History

- **First iteration (no experiment log):** Create the experiment log at `docs/autoloop/<program-name>/log.md` using the experiment log template. Run the evaluation command against the current state of target files to establish a baseline metric. Record as "Iteration 0 (baseline)" in the log. Commit the log file. If the evaluation command fails on baseline, this is a program configuration error — report and ask the user to fix the evaluation command or target file paths. See `references/edge-cases.md` for details.
- **Subsequent iteration:** Read the experiment log. Note the iteration count, recent results, metric trend, and current best metric.

#### Step 2: Propose Change

Spawn the `autoloop-optimizer` agent as a subagent with:
- The program definition (goal, targets, evaluation criteria, constraints)
- The experiment log summary (last 10 iterations: what was tried, result, metric delta)
- The current content of all target files
- The evaluation command (read-only reference — the optimizer must not modify it)
- The current iteration number

The optimizer returns a proposal: description of the proposed change, which target files it will modify, expected metric improvement, and rationale.

If the optimizer returns "no proposal" (cannot identify a meaningful change): log as a "no-proposal" iteration, increment the consecutive-failure counter, check stop conditions (Step 8), and report to the user.

#### Step 3: Present Proposal

- **Single-iteration mode:** Show the proposal and ask the user to confirm:

> **Iteration [N] proposal:**
> - Change: [description]
> - Files: [list]
> - Expected effect: [improvement direction]
> - Rationale: [why]
>
> A) Proceed with this change
> B) Skip and propose a different change
> C) Stop autoloop

- **Batch mode (N iterations or until-target):** Show the proposal briefly and proceed. The user pre-approved batch execution in Phase 1 but can interrupt at any time.

#### Step 4: Implement on Branch

1. Invoke the `loopy-workspace` skill with branch name `autoloop/<program-name>/iter-<N>`.
2. The `autoloop-optimizer` agent implements the proposed change in the worktree.
3. The optimizer commits with message: `autoloop(<program>): <brief description of change>`

#### Step 5: Safety Gate

After the commit, verify that only files listed in the program's Target section were modified:

```bash
git diff --name-only <base-sha>..HEAD
```

Compare every file in the diff against the Target list. If any file outside the Target list was modified:
- Reject the change immediately
- Log the violation in the experiment log: "rejected — modified non-target file: [path]"
- Clean up the worktree and branch
- Report the violation to the user
- Skip to Step 8 (check stop conditions)

#### Step 6: Evaluate

1. Run the program's evaluation command in the worktree context.
2. Parse the output to extract the metric value using the program's Metric Extraction pattern.
3. Compare the metric to the previous iteration's value and to the overall best metric.
4. Determine pass/fail:
   - **Pass:** Metric improved in the program's Direction, OR metric regressed but within the Tolerance value
   - **Fail:** Metric regressed beyond the Tolerance value
   - **Error:** Evaluation command exited non-zero, or metric could not be parsed from output

#### Step 7: Accept or Reject

**If evaluation passes (metric improved or within tolerance):**

1. Log the iteration as "accepted" in the experiment log with: iteration number, date, change description, metric before, metric after, delta, branch name.
2. Update the Best Metric section if this is a new best.
3. Push the branch: `git push -u origin autoloop/<program-name>/iter-<N>`
4. Spawn the `pr-creator-worker` agent to create a draft PR:
   - Title: `[Autoloop] <program-name>: <brief change description>`
   - Description: program goal, iteration number, metric change (before -> after, delta), link to experiment log
   - Draft: yes
   - Target branch: default branch (main/master)
5. Log the PR reference in the experiment log.
6. Commit the updated experiment log on the original branch (not the iteration branch).
7. Report to user:

> **Iteration [N]: accepted**
> Metric: [before] -> [after] ([delta])
> Draft PR: [URL]

**If evaluation fails (metric regressed beyond tolerance):**

1. Log the iteration as "rejected" in the experiment log with: iteration number, date, change description, metric before, metric after, delta, reason.
2. Delete the worktree and branch (cleanup, no PR).
3. Commit the updated experiment log.
4. Report to user:

> **Iteration [N]: rejected**
> Metric: [before] -> [after] ([delta]) — regressed beyond tolerance
> Change discarded.

**If evaluation errors (command fails or metric unparseable):**

1. Log the iteration as "error" in the experiment log with the error message.
2. Preserve the worktree for debugging.
3. Commit the updated experiment log.
4. Ask the user:
   - A) Retry evaluation
   - B) Skip this iteration and continue
   - C) Stop autoloop

See `references/edge-cases.md` for detailed error handling guidance.

#### Step 8: Check Stop Conditions

Check whether to continue iterating:

- **Max iterations reached** (from program's Stop Conditions or user's selected N): stop
- **Target metric met** (from program's Stop Conditions): stop and report success
- **Consecutive failure limit** (rejections + no-proposals + errors in a row; default 3): stop
- **User interrupted**: stop

If no stop condition met and more iterations remain: return to Step 1 for the next iteration.

If stopping: proceed to Phase 3.

### Phase 3: Finish

1. Present a summary:

> **Autoloop complete: [program-name]**
> - Iterations: [total] ([accepted] accepted, [rejected] rejected, [errors] errors)
> - Metric: [first baseline] -> [current best] ([total improvement])
> - Draft PRs created: [list with URLs]
> - Stop reason: [max iterations / target met / consecutive failures / user stopped]

2. Update the experiment log:
   - Status: `Complete` if target metric met or max iterations reached
   - Status: `Paused` if user stopped early or consecutive failure limit reached
   - Last Updated: current date

3. Commit the final experiment log update.

4. Present options:
   - A) Run more iterations on this program
   - B) Run a different program
   - C) I'll review the draft PRs myself (exit)

## Program Definition

Programs are defined in `.loopy/autoloop/programs/<name>.md`. Each program specifies:

- **Goal** — What to optimize (natural language + measurable metric)
- **Target** — Files the optimizer may modify (all others off-limits)
- **Evaluation** — Command + metric extraction + direction + tolerance
- **Constraints** — Additional rules beyond target file restrictions
- **Stop Conditions** — When to stop automatically

See `references/program-template.md` for the full template and examples.

## Experiment Log

Each program's iterations are tracked in `docs/autoloop/<program-name>/log.md`. The log contains:

- A metric summary table (one row per iteration)
- Best metric achieved
- Detailed records per iteration (change, rationale, result, metric delta)

See `references/experiment-log-template.md` for the template.

## Scheduling

The `/loopy-optimize` skill is invoked manually. For automated/scheduled execution, use one of these approaches:

**Claude Code `/loop` command:**
```
/loop 30m /loopy-optimize --program my-program
```
Runs one iteration every 30 minutes.

**System cron:**
```bash
# Run one autoloop iteration every 6 hours
0 */6 * * * cd /path/to/repo && claude -p "/loopy-optimize --program my-program --iterations 1"
```

**Future Temporal integration:** Each iteration could be scheduled as a Temporal workflow via loopy's task system. This is out of scope for now but the architecture supports it — each iteration is a discrete, logged unit of work.

## Anti-Patterns to Avoid

| Anti-Pattern | Better Approach |
|--------------|-----------------|
| Too many target files | Focus on 3-5 files in the optimization area |
| Vague goal ("make it faster") | Specific measurable goal with a metric |
| Non-deterministic evaluation | Set tolerance > 0 or average multiple eval runs |
| Evaluation scripts in Target list | Never let the optimizer modify what measures it |
| Running many iterations without merging accepted PRs | Merge regularly to avoid stale branches and conflicts |
| Ignoring consecutive rejections | Review experiment log and adjust program after 3+ rejections |

See `references/anti-patterns.md` for the full list.

## Edge Cases

See `references/edge-cases.md` for handling of: first run, evaluation failures, metric plateaus, program changes mid-loop, resume after interruption, optimizer exhaustion, overlapping targets across programs, and more.
