package task

import (
	"sort"
	"time"

	"go.temporal.io/sdk/workflow"
)

const (
	UpdateUpsertTasks    = "UpsertTasks"
	UpdateClaimTask      = "ClaimTask"
	UpdateHeartbeatTask  = "HeartbeatTask"
	UpdateCheckpointTask = "CheckpointTask"
	UpdateCompleteTask   = "CompleteTask"
	QueryTaskBoardState  = "taskboard_state"

	ReasonOK              = "ok"
	ReasonBlocked         = "blocked"
	ReasonClaimed         = "claimed"
	ReasonNotFound        = "not_found"
	ReasonLeaseExpired    = "lease_expired"
	ReasonInvalidClaimant = "invalid_claimant"
)

var (
	defaultLeaseTTL           = 10 * time.Minute
	defaultLeaseSweepInterval = 30 * time.Second
)

type UpdateResponse struct {
	Ok     bool          `json:"ok"`
	Reason string        `json:"reason"`
	Task   *TaskSnapshot `json:"task,omitempty"`
}

type UpsertTasksInput struct {
	Tasks []TaskSpec
}

type ClaimTaskInput struct {
	TaskID   string
	Claimant string
}

type HeartbeatTaskInput struct {
	TaskID   string
	Claimant string
}

type CheckpointTaskInput struct {
	TaskID   string
	Claimant string
	Message  string
}

type CompleteTaskInput struct {
	TaskID   string
	Claimant string
}

// TaskBoardWorkflow is a long-running workflow that stores task state for a plan.
func TaskBoardWorkflow(ctx workflow.Context, input TaskBoardInput) error {
	state := TaskBoardState{
		Tasks:              map[string]*Task{},
		LeaseTTL:           input.LeaseTTL,
		LeaseSweepInterval: input.LeaseSweepInterval,
	}
	if state.LeaseTTL <= 0 {
		state.LeaseTTL = defaultLeaseTTL
	}
	if state.LeaseSweepInterval <= 0 {
		state.LeaseSweepInterval = defaultLeaseSweepInterval
	}

	if err := workflow.SetQueryHandler(ctx, QueryTaskBoardState, func() (TaskBoardSnapshot, error) {
		return buildSnapshot(state.Tasks), nil
	}); err != nil {
		return err
	}

	if err := workflow.SetUpdateHandler(ctx, UpdateUpsertTasks, func(ctx workflow.Context, input UpsertTasksInput) (UpdateResponse, error) {
		now := workflow.Now(ctx)
		expired := expireLeases(now, &state)
		if err := upsertTasks(&state, input.Tasks); err != nil {
			return UpdateResponse{Ok: false, Reason: err.Error()}, nil
		}
		if expired {
			RecomputeStatuses(state.Tasks)
		}
		return UpdateResponse{Ok: true, Reason: ReasonOK}, nil
	}); err != nil {
		return err
	}

	if err := workflow.SetUpdateHandler(ctx, UpdateClaimTask, func(ctx workflow.Context, input ClaimTaskInput) (UpdateResponse, error) {
		now := workflow.Now(ctx)
		if expireLeases(now, &state) {
			RecomputeStatuses(state.Tasks)
		}
		return claimTask(now, &state, input), nil
	}); err != nil {
		return err
	}

	if err := workflow.SetUpdateHandler(ctx, UpdateHeartbeatTask, func(ctx workflow.Context, input HeartbeatTaskInput) (UpdateResponse, error) {
		now := workflow.Now(ctx)
		if expireLeases(now, &state) {
			RecomputeStatuses(state.Tasks)
		}
		return heartbeatTask(now, &state, input), nil
	}); err != nil {
		return err
	}

	if err := workflow.SetUpdateHandler(ctx, UpdateCheckpointTask, func(ctx workflow.Context, input CheckpointTaskInput) (UpdateResponse, error) {
		now := workflow.Now(ctx)
		if expireLeases(now, &state) {
			RecomputeStatuses(state.Tasks)
		}
		return checkpointTask(now, &state, input), nil
	}); err != nil {
		return err
	}

	if err := workflow.SetUpdateHandler(ctx, UpdateCompleteTask, func(ctx workflow.Context, input CompleteTaskInput) (UpdateResponse, error) {
		now := workflow.Now(ctx)
		if expireLeases(now, &state) {
			RecomputeStatuses(state.Tasks)
		}
		return completeTask(now, &state, input), nil
	}); err != nil {
		return err
	}

	workflow.Go(ctx, func(ctx workflow.Context) {
		for {
			if err := workflow.Sleep(ctx, state.LeaseSweepInterval); err != nil {
				return
			}
			now := workflow.Now(ctx)
			if expireLeases(now, &state) {
				RecomputeStatuses(state.Tasks)
			}
		}
	})

	return workflow.Await(ctx, func() bool { return false })
}

func upsertTasks(state *TaskBoardState, specs []TaskSpec) error {
	if state.Tasks == nil {
		state.Tasks = map[string]*Task{}
	}
	next := make(map[string]*Task, len(specs))
	for _, spec := range specs {
		if existing, ok := state.Tasks[spec.ID]; ok {
			existing.TaskSpec = spec
			next[spec.ID] = existing
		} else {
			next[spec.ID] = &Task{TaskSpec: spec}
		}
	}
	state.Tasks = next
	if err := ValidateTaskGraph(state.Tasks); err != nil {
		return err
	}
	RecomputeStatuses(state.Tasks)
	return nil
}

func claimTask(now time.Time, state *TaskBoardState, input ClaimTaskInput) UpdateResponse {
	task, ok := state.Tasks[input.TaskID]
	if !ok {
		return UpdateResponse{Ok: false, Reason: ReasonNotFound}
	}
	if task.Status != StatusReady {
		if task.Status == StatusInProgress {
			return UpdateResponse{Ok: false, Reason: ReasonClaimed, Task: snapshotPtr(task)}
		}
		return UpdateResponse{Ok: false, Reason: ReasonBlocked, Task: snapshotPtr(task)}
	}
	if task.ClaimedBy != "" {
		return UpdateResponse{Ok: false, Reason: ReasonClaimed, Task: snapshotPtr(task)}
	}
	task.Status = StatusInProgress
	task.ClaimedBy = input.Claimant
	task.LeaseExpiresAt = now.Add(state.LeaseTTL)
	return UpdateResponse{Ok: true, Reason: ReasonOK, Task: snapshotPtr(task)}
}

func heartbeatTask(now time.Time, state *TaskBoardState, input HeartbeatTaskInput) UpdateResponse {
	task, ok := state.Tasks[input.TaskID]
	if !ok {
		return UpdateResponse{Ok: false, Reason: ReasonNotFound}
	}
	if task.Status != StatusInProgress {
		return UpdateResponse{Ok: false, Reason: ReasonLeaseExpired, Task: snapshotPtr(task)}
	}
	if task.ClaimedBy != input.Claimant {
		return UpdateResponse{Ok: false, Reason: ReasonInvalidClaimant, Task: snapshotPtr(task)}
	}
	if !task.LeaseExpiresAt.After(now) {
		clearClaim(task)
		return UpdateResponse{Ok: false, Reason: ReasonLeaseExpired, Task: snapshotPtr(task)}
	}
	task.LeaseExpiresAt = now.Add(state.LeaseTTL)
	return UpdateResponse{Ok: true, Reason: ReasonOK, Task: snapshotPtr(task)}
}

func checkpointTask(now time.Time, state *TaskBoardState, input CheckpointTaskInput) UpdateResponse {
	task, ok := state.Tasks[input.TaskID]
	if !ok {
		return UpdateResponse{Ok: false, Reason: ReasonNotFound}
	}
	if task.Status != StatusInProgress {
		return UpdateResponse{Ok: false, Reason: ReasonInvalidClaimant, Task: snapshotPtr(task)}
	}
	if task.ClaimedBy != input.Claimant {
		return UpdateResponse{Ok: false, Reason: ReasonInvalidClaimant, Task: snapshotPtr(task)}
	}
	task.Checkpoints = append(task.Checkpoints, Checkpoint{
		At:      now,
		Worker:  input.Claimant,
		Message: input.Message,
	})
	return UpdateResponse{Ok: true, Reason: ReasonOK, Task: snapshotPtr(task)}
}

func completeTask(now time.Time, state *TaskBoardState, input CompleteTaskInput) UpdateResponse {
	task, ok := state.Tasks[input.TaskID]
	if !ok {
		return UpdateResponse{Ok: false, Reason: ReasonNotFound}
	}
	if task.Status != StatusInProgress {
		return UpdateResponse{Ok: false, Reason: ReasonLeaseExpired, Task: snapshotPtr(task)}
	}
	if task.ClaimedBy != input.Claimant {
		return UpdateResponse{Ok: false, Reason: ReasonInvalidClaimant, Task: snapshotPtr(task)}
	}
	if !task.LeaseExpiresAt.After(now) {
		clearClaim(task)
		return UpdateResponse{Ok: false, Reason: ReasonLeaseExpired, Task: snapshotPtr(task)}
	}
	task.Status = StatusDone
	clearClaim(task)
	RecomputeStatuses(state.Tasks)
	return UpdateResponse{Ok: true, Reason: ReasonOK, Task: snapshotPtr(task)}
}

func expireLeases(now time.Time, state *TaskBoardState) bool {
	changed := false
	for _, task := range state.Tasks {
		if task.Status != StatusInProgress {
			continue
		}
		if task.LeaseExpiresAt.IsZero() {
			continue
		}
		if task.LeaseExpiresAt.After(now) {
			continue
		}
		clearClaim(task)
		task.Status = StatusBlocked
		changed = true
	}
	return changed
}

func clearClaim(task *Task) {
	task.ClaimedBy = ""
	task.LeaseExpiresAt = time.Time{}
}

func snapshotPtr(task *Task) *TaskSnapshot {
	snapshot := task.Snapshot()
	return &snapshot
}

func buildSnapshot(tasks map[string]*Task) TaskBoardSnapshot {
	ids := make([]string, 0, len(tasks))
	for id := range tasks {
		ids = append(ids, id)
	}
	sort.Strings(ids)

	snapshots := make([]TaskSnapshot, 0, len(ids))
	for _, id := range ids {
		snapshots = append(snapshots, tasks[id].Snapshot())
	}
	return TaskBoardSnapshot{Tasks: snapshots}
}
