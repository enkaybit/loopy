# Temporal Task System

Loopy can use Temporal OSS as a durable task system for multi-agent work. This is
optional — if Temporal is not available, the workflow falls back to built-in task
tracking.

## Local Setup

1. Start a local Temporal dev server:

```bash
temporal server start-dev
```

2. Start the loopy task worker:

```bash
loopy-taskd
```

3. Import a plan into Temporal:

```bash
loopy-tasks import --plan docs/plans/YYYY-MM-DD-<feature>-tech-plan.md
```

4. List tasks:

```bash
loopy-tasks list --plan docs/plans/YYYY-MM-DD-<feature>-tech-plan.md
```

## Team Setup

Run a shared Temporal server and point the CLI/worker at it using env vars:

- `TEMPORAL_ADDRESS` (default `127.0.0.1:7233`)
- `TEMPORAL_NAMESPACE` (default `default`)
- `TEMPORAL_TASK_QUEUE` (default `loopy-task-queue`)
- `LOOPY_TASK_LEASE_TTL` (default `10m`)
- `LOOPY_TASK_HEARTBEAT_INTERVAL` (default `2m`)
- `LOOPY_TASK_LEASE_SWEEP_INTERVAL` (default `30s`)
- `LOOPY_TASK_WORKER_ID` (default `hostname:pid`)

## Task Commands Used by Skills

- `loopy-tasks status [--plan <path>]` — checks Temporal connectivity and workflow existence
- `loopy-tasks import --plan <path>` — parses the plan and upserts tasks
- `loopy-tasks claim --plan <path> --task <id>` — claim a task
- `loopy-tasks heartbeat --plan <path> --task <id>` — extend a lease
- `loopy-tasks checkpoint --plan <path> --task <id> --message "..."` — record progress
- `loopy-tasks complete --plan <path> --task <id>` — mark task done

## Migration Note

Legacy task systems are not migrated. Re-run `loopy-tasks import` for each plan to
create tasks in Temporal.
