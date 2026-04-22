# Experiment Log Template

Use this template when creating experiment logs for autoloop programs. The skill creates the log automatically at `docs/autoloop/<program-name>/log.md` on the first iteration.

## Document Structure

```markdown
# Autoloop Experiment Log: [program-name]

**Program:** `.loopy/autoloop/programs/[program-name].md`
**Goal:** [copied from program definition]
**Direction:** [minimize/maximize]
**Status:** In Progress
**Started:** [date]
**Last Updated:** [date]

## Metric Summary

| Iteration | Date | Change | Metric Before | Metric After | Delta | Result | PR |
|-----------|------|--------|---------------|--------------|-------|--------|----|
| 0 (baseline) | YYYY-MM-DD | — | — | [value] | — | baseline | — |
| 1 | YYYY-MM-DD | [brief description] | [value] | [value] | [+/- delta] | accepted | !123 |
| 2 | YYYY-MM-DD | [brief description] | [value] | [value] | [+/- delta] | rejected | — |

## Best Metric

**Value:** [best value achieved]
**Iteration:** [which iteration achieved it]
**PR:** [PR reference, if accepted]

## Iteration Details

### Iteration 0 (Baseline)

**Date:** YYYY-MM-DD
**Metric:** [value]

Baseline measurement of the current state before any optimization.

---

### Iteration 1

**Date:** YYYY-MM-DD
**Branch:** `autoloop/[program]/iter-1`
**Result:** accepted / rejected / error
**Metric:** [before] -> [after] ([delta])
**PR:** #123 (if accepted)

**Change:**
[Detailed description of what was changed]

**Rationale:**
[Why the optimizer proposed this change]

**Strategy:** [label — e.g., "algorithmic optimization"]

---
```

## Valid Status Values

- **In Progress** — Active autoloop with pending iterations
- **Complete** — All planned iterations finished or target metric met
- **Paused** — User stopped early; can be resumed

## Update Rules

- Add a new row to the Metric Summary table for each iteration (including errors)
- Update the Best Metric section whenever a new best is achieved
- Add a new Iteration Details section for each iteration
- Update Last Updated date on every change
- Set Status to Complete when stop conditions are met
- Set Status to Paused when the user stops early

## Result Values

- **baseline** — Initial measurement, no changes made
- **accepted** — Metric improved (or within tolerance), draft PR created
- **rejected** — Metric regressed beyond tolerance, change discarded
- **error** — Evaluation command failed or metric unparseable
- **no-proposal** — Optimizer could not identify a meaningful change
