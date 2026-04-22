# Autoloop Anti-Patterns

Common mistakes to avoid when configuring and running autoloop programs.

## Program Definition

| Anti-Pattern | Problem | Better Approach |
|--------------|---------|-----------------|
| Too many target files | Changes become diffuse, hard to review, unclear attribution | Keep Target list to 3-5 files focused on the optimization area |
| Vague goal | "Make it faster" gives the optimizer no measurable direction | Specific measurable goal: "Reduce p95 latency of /api/search below 200ms" |
| No numeric metric | Evaluation output like "PASS/FAIL" can't track incremental improvement | Ensure eval produces a numeric value the optimizer can trend against |
| Non-deterministic evaluation | Benchmarks with high variance cause false accepts/rejects | Set tolerance > 0, or use averaged metrics (run eval 3x, take median) |
| Modifying eval scripts in Target | Optimizer could game the metric by changing what's measured | Never include evaluation scripts in the Target list |
| Missing stop conditions | Loop runs indefinitely with diminishing returns | Always set max iterations and consecutive rejection limits |

## Execution

| Anti-Pattern | Problem | Better Approach |
|--------------|---------|-----------------|
| Running all programs at once | Each program creates branches and PRs; many at once overwhelms review | Run one program at a time, or limit to 2-3 related programs |
| Ignoring rejected iterations | Repeated rejections mean the approach is wrong | Review the experiment log; adjust goal, targets, or constraints after 3 rejections |
| Skipping baseline | Without a baseline, you can't tell if changes actually improved anything | Always let the first iteration establish a baseline (iteration 0) |
| Merging PRs without review | Draft PRs exist for a reason — optimizer changes need human verification | Review each draft PR before merging |
| Running many iterations without merging | Accepted PRs pile up, creating merge conflicts and stale branches | Merge accepted PRs regularly; each new iteration builds on the current main state |

## Goal Design

| Anti-Pattern | Problem | Better Approach |
|--------------|---------|-----------------|
| Optimizing for a single metric at the expense of everything else | Optimizer might break readability, correctness, or other properties | Use constraints to protect important properties: "Do not change public API", "Keep code readable" |
| Goal requires modifying non-target files | Optimizer can't achieve the goal within the target boundary | Expand the Target list or redefine the goal to match what the targets can influence |
| Contradictory goal and constraints | "Maximize performance" + "Don't change any algorithms" = deadlock | Ensure goal and constraints are compatible; something must be allowed to change |
