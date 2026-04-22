package parser

import "testing"

func TestParsePlanTasks(t *testing.T) {
	plan := `# Plan

### Parent 1: Alpha

#### 1.1 First task

**Depends on:** none
**Files:** 	` + "`" + `a.go` + "`" + `, ` + "`" + `b.go` + "`" + `

Do the first thing.

**Test scenarios:** (` + "`" + `a_test.go` + "`" + `)
- scenario

#### 1.2 Second task

**Depends on:** 1.1, 2.1
**Files:** ` + "`" + `c.go` + "`" + `

Second desc.

**Test scenarios:** (` + "`" + `c_test.go` + "`" + `)
- scenario

### Parent 2: Beta

#### 2.1 Third task

**Depends on:** 1.1
**Files:** ` + "`" + `d.go` + "`" + `

Third desc.

**Test scenarios:** (` + "`" + `d_test.go` + "`" + `)
- scenario
`

	tasks, err := ParsePlanBytes([]byte(plan))
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(tasks) != 3 {
		t.Fatalf("expected 3 tasks, got %d", len(tasks))
	}
	if tasks[0].ID != "1.1" || tasks[0].ParentTitle != "Alpha" {
		t.Fatalf("unexpected first task: %+v", tasks[0])
	}
	if len(tasks[0].DependsOn) != 0 {
		t.Fatalf("expected no deps for 1.1, got %v", tasks[0].DependsOn)
	}
	if len(tasks[1].DependsOn) != 2 {
		t.Fatalf("expected 2 deps for 1.2, got %v", tasks[1].DependsOn)
	}
	if tasks[2].ParentTitle != "Beta" {
		t.Fatalf("expected parent Beta, got %s", tasks[2].ParentTitle)
	}
}

func TestParsePlanMissingFields(t *testing.T) {
	plan := `# Plan

### Parent 1: Alpha

#### 1.1 First task

**Depends on:** none

No files listed.

**Test scenarios:**
- scenario
`
	if _, err := ParsePlanBytes([]byte(plan)); err == nil {
		t.Fatalf("expected error for missing files")
	}
}

func TestParsePlanDependsNone(t *testing.T) {
	plan := `# Plan

### Parent 1: Alpha

#### 1.1 First task

**Depends on:** none
**Files:** ` + "`" + `a.go` + "`" + `

Desc.

**Test scenarios:** (` + "`" + `a_test.go` + "`" + `)
`
	tasks, err := ParsePlanBytes([]byte(plan))
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(tasks) != 1 {
		t.Fatalf("expected 1 task, got %d", len(tasks))
	}
	if len(tasks[0].DependsOn) != 0 {
		t.Fatalf("expected empty deps, got %v", tasks[0].DependsOn)
	}
}

func TestParsePlanIdempotentIDs(t *testing.T) {
	plan := `# Plan

### Parent 1: Alpha

#### 1.1 First task

**Depends on:** none
**Files:** ` + "`" + `a.go` + "`" + `

Desc.

**Test scenarios:** (` + "`" + `a_test.go` + "`" + `)
`
	first, err := ParsePlanBytes([]byte(plan))
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	second, err := ParsePlanBytes([]byte(plan))
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if first[0].ID != second[0].ID {
		t.Fatalf("expected stable IDs, got %s vs %s", first[0].ID, second[0].ID)
	}
}
