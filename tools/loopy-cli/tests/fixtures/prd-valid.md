# Example Feature - PRD

**Date:** 2026-04-20
**Status:** Requirements

## Goal
Let users export audit logs as CSV for offline analysis.

## Scope

### In Scope
- CSV export for the last 90 days.
- On-demand export from the UI.

### Boundaries
- Streaming exports (deferred).
- Re-signing / tamper-evidence (deferred, handled elsewhere).

## Requirements

| ID | Priority | Requirement |
|----|----------|-------------|
| R1 | Core | Users can download audit logs as CSV |
| R2 | Must | Export covers the last 90 days |
| R3 | Nice | Export supports filtering by actor |
| R4 | Out | Real-time streaming of audit events |

## Open Questions
- **[Affects R3]** Should filters apply server-side or client-side?

## Next Steps
→ Create technical plan.
