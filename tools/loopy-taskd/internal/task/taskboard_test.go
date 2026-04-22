package task

import (
	"fmt"
	"testing"
	"time"

	"go.temporal.io/sdk/testsuite"
)

type updateResult struct {
	resp UpdateResponse
	err  error
}

type updateCallback struct {
	accept   func()
	reject   func(error)
	complete func(interface{}, error)
}

func (u *updateCallback) Accept() {
	if u.accept != nil {
		u.accept()
	}
}

func (u *updateCallback) Reject(err error) {
	if u.reject != nil {
		u.reject(err)
	}
}

func (u *updateCallback) Complete(result interface{}, err error) {
	if u.complete != nil {
		u.complete(result, err)
	}
}

func queueUpdate(env *testsuite.TestWorkflowEnvironment, name string, input interface{}, ch chan updateResult) {
	cb := &updateCallback{
		reject: func(err error) {
			ch <- updateResult{err: err}
		},
		complete: func(result interface{}, err error) {
			if err != nil {
				ch <- updateResult{err: err}
				return
			}
			resp, ok := result.(UpdateResponse)
			if !ok {
				ch <- updateResult{err: fmt.Errorf("unexpected update response type %T", result)}
				return
			}
			ch <- updateResult{resp: resp}
		},
	}
	env.UpdateWorkflow(name, "", cb, input)
}

func waitForResult(t *testing.T, ch <-chan updateResult) UpdateResponse {
	t.Helper()
	select {
	case res := <-ch:
		if res.err != nil {
			t.Fatalf("update error: %v", res.err)
		}
		return res.resp
	case <-time.After(2 * time.Second):
		t.Fatalf("timeout waiting for update result")
		return UpdateResponse{}
	}
}

func TestTaskBoardWorkflowClaimLifecycle(t *testing.T) {
	var suite testsuite.WorkflowTestSuite
	env := suite.NewTestWorkflowEnvironment()
	env.RegisterWorkflow(TaskBoardWorkflow)

	input := TaskBoardInput{LeaseTTL: 2 * time.Second, LeaseSweepInterval: 200 * time.Millisecond}

	upsertCh := make(chan updateResult, 1)
	claimCh := make(chan updateResult, 1)
	heartbeatCh := make(chan updateResult, 1)
	completeCh := make(chan updateResult, 1)
	claimDepCh := make(chan updateResult, 1)

	tasks := []TaskSpec{
		{ID: "1.1", Title: "first"},
		{ID: "1.2", Title: "second", DependsOn: []string{"1.1"}},
	}

	env.RegisterDelayedCallback(func() {
		queueUpdate(env, UpdateUpsertTasks, UpsertTasksInput{Tasks: tasks}, upsertCh)
	}, 0)
	env.RegisterDelayedCallback(func() {
		queueUpdate(env, UpdateClaimTask, ClaimTaskInput{TaskID: "1.1", Claimant: "worker-a"}, claimCh)
	}, time.Second)
	env.RegisterDelayedCallback(func() {
		queueUpdate(env, UpdateHeartbeatTask, HeartbeatTaskInput{TaskID: "1.1", Claimant: "worker-a"}, heartbeatCh)
	}, 2*time.Second)
	env.RegisterDelayedCallback(func() {
		queueUpdate(env, UpdateCompleteTask, CompleteTaskInput{TaskID: "1.1", Claimant: "worker-a"}, completeCh)
	}, 3*time.Second)
	env.RegisterDelayedCallback(func() {
		queueUpdate(env, UpdateClaimTask, ClaimTaskInput{TaskID: "1.2", Claimant: "worker-a"}, claimDepCh)
	}, 4*time.Second)
	env.RegisterDelayedCallback(func() {
		env.CancelWorkflow()
	}, 5*time.Second)

	env.ExecuteWorkflow(TaskBoardWorkflow, input)
	if !env.IsWorkflowCompleted() {
		t.Fatalf("workflow did not complete")
	}

	if resp := waitForResult(t, upsertCh); !resp.Ok {
		t.Fatalf("upsert failed: %s", resp.Reason)
	}
	resp := waitForResult(t, claimCh)
	if !resp.Ok || resp.Task == nil || resp.Task.Status != StatusInProgress {
		t.Fatalf("claim failed: %+v", resp)
	}
	resp = waitForResult(t, heartbeatCh)
	if !resp.Ok {
		t.Fatalf("heartbeat failed: %+v", resp)
	}
	resp = waitForResult(t, completeCh)
	if !resp.Ok || resp.Task == nil || resp.Task.Status != StatusDone {
		t.Fatalf("complete failed: %+v", resp)
	}
	resp = waitForResult(t, claimDepCh)
	if !resp.Ok || resp.Task == nil || resp.Task.Status != StatusInProgress {
		t.Fatalf("dependent claim failed: %+v", resp)
	}
}

func TestTaskBoardWorkflowLeaseExpiryAllowsReclaim(t *testing.T) {
	var suite testsuite.WorkflowTestSuite
	env := suite.NewTestWorkflowEnvironment()
	env.RegisterWorkflow(TaskBoardWorkflow)

	input := TaskBoardInput{LeaseTTL: time.Second, LeaseSweepInterval: 200 * time.Millisecond}

	upsertCh := make(chan updateResult, 1)
	claimCh := make(chan updateResult, 1)
	reclaimCh := make(chan updateResult, 1)

	tasks := []TaskSpec{{ID: "1.1", Title: "solo"}}

	env.RegisterDelayedCallback(func() {
		queueUpdate(env, UpdateUpsertTasks, UpsertTasksInput{Tasks: tasks}, upsertCh)
	}, 0)
	env.RegisterDelayedCallback(func() {
		queueUpdate(env, UpdateClaimTask, ClaimTaskInput{TaskID: "1.1", Claimant: "worker-a"}, claimCh)
	}, 0)
	env.RegisterDelayedCallback(func() {
		queueUpdate(env, UpdateClaimTask, ClaimTaskInput{TaskID: "1.1", Claimant: "worker-b"}, reclaimCh)
	}, 2*time.Second)
	env.RegisterDelayedCallback(func() {
		env.CancelWorkflow()
	}, 3*time.Second)

	env.ExecuteWorkflow(TaskBoardWorkflow, input)
	if !env.IsWorkflowCompleted() {
		t.Fatalf("workflow did not complete")
	}

	if resp := waitForResult(t, upsertCh); !resp.Ok {
		t.Fatalf("upsert failed: %s", resp.Reason)
	}
	if resp := waitForResult(t, claimCh); !resp.Ok {
		t.Fatalf("initial claim failed: %+v", resp)
	}
	resp := waitForResult(t, reclaimCh)
	if !resp.Ok || resp.Task == nil || resp.Task.ClaimedBy != "worker-b" {
		t.Fatalf("reclaim failed: %+v", resp)
	}
}

func TestUpsertTasksRemovesMissing(t *testing.T) {
	state := TaskBoardState{
		Tasks: map[string]*Task{
			"1.1": {TaskSpec: TaskSpec{ID: "1.1"}, Status: StatusDone},
			"1.2": {TaskSpec: TaskSpec{ID: "1.2"}},
		},
	}
	specs := []TaskSpec{{ID: "1.1", Title: "keep"}}
	if err := upsertTasks(&state, specs); err != nil {
		t.Fatalf("upsert failed: %v", err)
	}
	if _, ok := state.Tasks["1.2"]; ok {
		t.Fatalf("expected removed task to be deleted")
	}
	if state.Tasks["1.1"].Status != StatusDone {
		t.Fatalf("expected status to be preserved")
	}
}
