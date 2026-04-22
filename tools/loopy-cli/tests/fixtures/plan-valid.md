# Audit Log Export - Technical Plan

**Date:** 2026-04-20
**Status:** Planning
**PRD:** docs/prd/2026-04-20-audit-log-export-prd.md

## Overview
Add a CSV export endpoint plus a UI trigger.

## Architecture
Service-layer exporter + controller; streams rows to CSV.

## Subtasks

### Parent 1: Exporter service

#### 1.1 Add CSV exporter service

**Depends on:** none
**Files:** `app/services/audit_exporter.ts`, `app/services/audit_exporter.test.ts`

Implement a service that streams audit rows to CSV. Satisfies R1, R2.

**Test scenarios:** (`app/services/audit_exporter.test.ts`)
- Empty result set → emits header row only
- 1000 rows → all rows emitted in order
- Filter by actor → only matching rows emitted

**Verify:** Run `npm test audit_exporter`.

#### 1.2 Add controller endpoint

**Depends on:** 1.1
**Files:** `app/controllers/audit_controller.ts`, `app/controllers/audit_controller.test.ts`

Expose `GET /api/audit/export.csv` that calls the service. Satisfies R1.

**Test scenarios:** (`app/controllers/audit_controller.test.ts`)
- Authenticated request → 200 + CSV content-type
- Unauthenticated request → 401

**Verify:** Run controller tests.

### Parent 2: UI

#### 2.1 Add export button to audit page

**Depends on:** 1.2
**Files:** `web/components/AuditExport.tsx`, `web/components/AuditExport.test.tsx`

Add a button that posts to the export endpoint and triggers a download.

**Test scenarios:** (`web/components/AuditExport.test.tsx`)
- Click → fetches /api/audit/export.csv

**Verify:** Run component tests.

## Testing Strategy
Unit + integration tests per subtask.

## Risks and Mitigations
| Risk | Mitigation |
|------|------------|
| Huge exports time out | Stream row-by-row |
