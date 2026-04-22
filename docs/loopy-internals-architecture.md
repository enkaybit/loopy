# Loopy Internals - Technical Plan

**Date:** 2026-02-27
**Status:** Draft
**PRD:** None

## Overview
Loopy is a workflow plugin that orchestrates requirements discovery, planning, implementation, review, and pull request creation through reusable skills and specialized agents.

## Architecture
Core components:
- Skill layer (`skills/*`): Entry workflows (`loopy-requirements`, `loopy-plan`, `loopy-build`, `loopy-ship`) that drive phase-based execution.
- Agent layer (`agents/*`): Focused workers (for example `task-worker`, review agents, PR creator) used by skills for delegated execution.
- Orchestration runtime: The CLI host executes skill instructions, spawns agents, runs tools, and enforces transitions and safeguards.
- Artifact layer (`docs/*`): Persistent outputs (`docs/prd`, `docs/plans`, spikes, review artifacts) used as handoff contracts between phases.
- Integration layer (`scripts/install.sh`, `Makefile`, `gh`, `git`): Installs skills, runs verification, and performs branch and PR operations.

Control flow (simplified):
User -> `/loopy-*` command -> entry skill
-> optional requirements/research/spike/review loops
-> plan creation (structured subtasks + dependencies)
-> build orchestration (dependency batches)
-> task-worker execution (TDD, tests, commits)
-> code review + fixes
-> implementation wrap-up (verification, push, PR)

Data flow:
PRD -> Technical Plan -> Subtasks/Dependencies -> Code + Tests + Commits -> Pull Request

## /loopy-build Sequence (DevX Friendly)

```mermaid
sequenceDiagram
    autonumber
    actor Dev as Developer
    participant LB as loopy-build skill
    participant Plan as Tech Plan (docs/plans/*.md)
    participant TS as Task System (Temporal or Built-in)
    participant TW as task-worker agent(s)
    participant CR as loopy-code-review
    participant CS as code-simplifier
    participant WR as loopy-ship

    Dev->>LB: Run /loopy-build
    LB->>TS: Check existing tasks (resume?)
    alt Tasks exist
        LB->>Plan: Load plan + completed vs remaining
    else No tasks
        LB->>Plan: Read and validate plan
        LB->>TS: Create parent/subtasks + dependencies
    end

    loop Per plan section
        LB->>LB: Build dependency batches from "Depends on"
        par Parallel subtasks in batch
            LB->>TW: Spawn worker for subtask A
            LB->>TW: Spawn worker for subtask B
        end
        TW->>Plan: Read subtask context/files/tests
        TW->>TW: TDD (RED -> GREEN -> REFACTOR)
        TW->>TS: Mark progress/done
        TW->>LB: Return commit + tests status

        LB->>LB: Gate: required tests exist and pass
        opt Large section (6+ subtasks)
            LB->>CR: Incremental quick review
            CR-->>LB: Findings (fix selected severities)
        end
    end

    LB->>CR: Section/final review (as configured)
    CR-->>LB: Findings + fix loop
    LB->>CS: Simplification pass on changed files
    CS-->>LB: Cleanup commit + test verification
    LB->>CR: Optional final review round
    LB->>WR: Hand off for verification + push/PR
    WR-->>Dev: PR URL or branch outcome
```

DevX takeaway:
- You provide a plan once.
- `/loopy-build` executes dependency-aware batches with test gates.
- Reviews and fixes happen before wrap-up, then PR creation is the final step.

## /loopy-optimize Sequence

Autoloop is a parallel workflow path for iterative optimization. Instead of a plan-build cycle, it runs a measure-propose-evaluate loop against a measurable metric.

```
User -> /loopy-optimize
-> discover programs (.loopy/autoloop/programs/*.md)
-> establish baseline metric (iteration 0)
-> loop:
   -> autoloop-optimizer proposes a targeted change
   -> implement on isolated branch (via loopy-workspace)
   -> safety gate: verify only Target files modified
   -> run evaluation command, extract metric
   -> accept (draft PR via pr-creator-worker) or reject (discard branch)
   -> log iteration in experiment log (docs/autoloop/<program>/log.md)
   -> check stop conditions (target met, max iterations, consecutive failures)
-> summary + next steps
```

Data flow:
Program Definition -> Experiment History -> Optimizer Proposal -> Branch + Commit -> Evaluation -> Accept/Reject -> Draft PR
