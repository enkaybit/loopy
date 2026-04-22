package task

import "testing"

func TestReadyTaskIDsEmpty(t *testing.T) {
	tasks := map[string]*Task{}
	RecomputeStatuses(tasks)
	ready := ReadyTaskIDs(tasks)
	if len(ready) != 0 {
		t.Fatalf("expected no ready tasks, got %v", ready)
	}
}

func TestReadyTaskNoDeps(t *testing.T) {
	tasks := map[string]*Task{
		"1.1": {TaskSpec: TaskSpec{ID: "1.1"}},
	}
	RecomputeStatuses(tasks)
	if tasks["1.1"].Status != StatusReady {
		t.Fatalf("expected ready status, got %s", tasks["1.1"].Status)
	}
}

func TestReadyTaskDepsNotDone(t *testing.T) {
	tasks := map[string]*Task{
		"1.1": {TaskSpec: TaskSpec{ID: "1.1"}, Status: StatusDone},
		"1.2": {TaskSpec: TaskSpec{ID: "1.2", DependsOn: []string{"1.3"}}},
		"1.3": {TaskSpec: TaskSpec{ID: "1.3"}, Status: StatusReady},
	}
	RecomputeStatuses(tasks)
	if tasks["1.2"].Status != StatusBlocked {
		t.Fatalf("expected blocked status, got %s", tasks["1.2"].Status)
	}
}

func TestReadyTaskDepsDone(t *testing.T) {
	tasks := map[string]*Task{
		"1.1": {TaskSpec: TaskSpec{ID: "1.1"}, Status: StatusDone},
		"1.2": {TaskSpec: TaskSpec{ID: "1.2", DependsOn: []string{"1.1"}}},
	}
	RecomputeStatuses(tasks)
	if tasks["1.2"].Status != StatusReady {
		t.Fatalf("expected ready status, got %s", tasks["1.2"].Status)
	}
}

func TestValidateTaskGraphDetectsCycle(t *testing.T) {
	tasks := map[string]*Task{
		"1.1": {TaskSpec: TaskSpec{ID: "1.1", DependsOn: []string{"1.2"}}},
		"1.2": {TaskSpec: TaskSpec{ID: "1.2", DependsOn: []string{"1.1"}}},
	}
	if err := ValidateTaskGraph(tasks); err == nil {
		t.Fatalf("expected cycle error")
	}
}
