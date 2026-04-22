package task

import "time"

type TaskStatus string

const (
	StatusReady      TaskStatus = "ready"
	StatusBlocked    TaskStatus = "blocked"
	StatusInProgress TaskStatus = "in_progress"
	StatusDone       TaskStatus = "done"
)

type TaskSpec struct {
	ID          string
	ParentTitle string
	Title       string
	Description string
	Files       []string
	DependsOn   []string
}

type Checkpoint struct {
	At      time.Time
	Worker  string
	Message string
}

type Task struct {
	TaskSpec
	Status         TaskStatus
	ClaimedBy      string
	LeaseExpiresAt time.Time
	Checkpoints    []Checkpoint
}

type TaskSnapshot struct {
	ID          string     `json:"id"`
	ParentTitle string     `json:"parent_title"`
	Title       string     `json:"title"`
	Description string     `json:"description"`
	Files       []string   `json:"files"`
	DependsOn   []string   `json:"depends_on"`
	Status      TaskStatus `json:"status"`
	ClaimedBy   string     `json:"claimed_by"`
	LeaseUntil  time.Time  `json:"lease_until"`
}

type TaskBoardSnapshot struct {
	Tasks []TaskSnapshot `json:"tasks"`
}

type TaskBoardState struct {
	Tasks              map[string]*Task
	LeaseTTL           time.Duration
	LeaseSweepInterval time.Duration
}

type TaskBoardInput struct {
	LeaseTTL           time.Duration
	LeaseSweepInterval time.Duration
}

func (t *Task) Snapshot() TaskSnapshot {
	return TaskSnapshot{
		ID:          t.ID,
		ParentTitle: t.ParentTitle,
		Title:       t.Title,
		Description: t.Description,
		Files:       append([]string(nil), t.Files...),
		DependsOn:   append([]string(nil), t.DependsOn...),
		Status:      t.Status,
		ClaimedBy:   t.ClaimedBy,
		LeaseUntil:  t.LeaseExpiresAt,
	}
}
