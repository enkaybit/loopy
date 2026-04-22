# Autoloop Edge Cases

How to handle unusual situations during autoloop execution.

## First Run (No History)

**Situation:** No experiment log exists for this program.

**Handle:** Create the experiment log from template. Run the evaluation command against the unmodified target files to establish a baseline metric (iteration 0). If the evaluation command fails on baseline, this is a program configuration error — report to the user and ask them to fix the evaluation command or target file paths before proceeding.

## Evaluation Command Fails

**Situation:** The evaluation command exits with non-zero status.

**Distinguish between:**
- **Exit code non-zero with metric output:** The evaluation ran but the code under test has issues (e.g., tests fail). Treat as a rejection — the proposed change broke something.
- **Command not found / syntax error:** Program configuration issue. Stop and report. Ask the user to verify the evaluation command.
- **Metric unparseable:** Output didn't match the metric extraction pattern. Log as error, preserve the worktree for debugging, and ask the user. This often means the evaluation command's output format changed.

## Metric Plateau

**Situation:** 3+ consecutive iterations with no meaningful improvement (accepted or rejected).

**Handle:** The optimizer should recognize the plateau from the experiment log and shift strategy. If it still can't propose a meaningful change, it returns "no proposal" and increments the consecutive-failure counter. After hitting the consecutive rejection limit, the loop stops automatically.

**User guidance:** Suggest expanding the Target list, adjusting the goal, or reviewing accepted PRs for compounding opportunities.

## Program Definition Changes Mid-Loop

**Situation:** User edits the program file between iterations.

**Handle:** Phase 2 re-reads the program definition each iteration, so changes take effect immediately.
- **Target files changed:** Warn the user that the metric baseline may no longer be comparable. Suggest re-establishing a baseline.
- **Evaluation command changed:** Warn that previous metrics aren't comparable. Suggest starting a fresh experiment log.
- **Goal changed:** This is effectively a new program. Suggest archiving the current log and starting fresh.

## Resume After Interruption

**Situation:** The experiment log has `Status: In Progress` but the last iteration is incomplete.

**Detect by:** The last iteration detail entry has no `**Result:**` field.

**Handle:**
- Check for a worktree at the expected path (`autoloop/<program>/iter-<N>`).
- If worktree exists: offer to re-run evaluation (the change was implemented but not yet evaluated), or discard the iteration and start fresh.
- If no worktree: the iteration was interrupted before implementation. Discard the incomplete entry and start a new iteration.

## Optimizer Cannot Propose a Change

**Situation:** The optimizer returns "no proposal" — it has exhausted viable approaches.

**Handle:** Log as a "no-proposal" iteration in the experiment log. Increment the consecutive-failure counter. Report to the user with the optimizer's suggestion (e.g., "expand targets", "adjust goal"). If the consecutive-failure limit is reached, stop the loop.

## Target Files Don't Exist

**Situation:** Files listed in the program's Target section are missing from the repository.

**Handle:** Report the missing files to the user before starting any iteration. Do not proceed — the program definition needs updating.

## Multiple Programs With Overlapping Targets

**Situation:** Two programs list some of the same target files.

**Handle:** Programs run sequentially, not in parallel, so there's no write conflict during execution. However, warn the user that accepted changes from one program may affect another program's metric. Suggest re-running baseline for affected programs after merging PRs.

## Branch Already Exists

**Situation:** The branch `autoloop/<program>/iter-<N>` already exists (from a previous interrupted run).

**Handle:** Check the experiment log for iteration N. If it was completed (has a Result), increment N and use the next branch name. If it was incomplete, follow the resume-after-interruption flow above.

## Evaluation Takes Too Long

**Situation:** The evaluation command runs for an extended period.

**Handle:** There is no built-in timeout. If the evaluation is expected to be long-running, document this in the program's Evaluation section. The user can interrupt with Ctrl+C and the iteration will be treated as an error. Consider suggesting the user add a timeout to their evaluation command (e.g., `timeout 300 python train.py`).
