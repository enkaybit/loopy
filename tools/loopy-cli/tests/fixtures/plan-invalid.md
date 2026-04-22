# Broken Plan

**Date:** 2026-04-20
**Status:** Planning

## Overview
x

## Architecture
x

#### 1.1 Add thing without tests

**Depends on:** none
**Files:** `app/x.ts`

Does something.

**Verify:** run tests.

#### 1.3 Numbering has a gap

**Depends on:** 1.1, 9.9
**Files:** `app/y.ts`, `app/y.test.ts`

More stuff.

**Test scenarios:**
- foo → bar

**Verify:** run tests.

#### 2.1 Cycle A

**Depends on:** 2.2
**Files:** `app/a.ts`

**Verify:** x.

#### 2.2 Cycle B

**Depends on:** 2.1
**Files:** `app/b.ts`

**Verify:** x.
