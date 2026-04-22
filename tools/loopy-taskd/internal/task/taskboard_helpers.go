package task

import (
	"fmt"
	"sort"
)

func ValidateTaskGraph(tasks map[string]*Task) error {
	for id, task := range tasks {
		for _, dep := range task.DependsOn {
			if _, ok := tasks[dep]; !ok {
				return fmt.Errorf("task %s depends on missing task %s", id, dep)
			}
		}
	}

	state := make(map[string]int)
	var visit func(string) error
	visit = func(id string) error {
		switch state[id] {
		case 1:
			return fmt.Errorf("dependency cycle detected at %s", id)
		case 2:
			return nil
		}
		state[id] = 1
		for _, dep := range tasks[id].DependsOn {
			if err := visit(dep); err != nil {
				return err
			}
		}
		state[id] = 2
		return nil
	}

	for id := range tasks {
		if err := visit(id); err != nil {
			return err
		}
	}
	return nil
}

func RecomputeStatuses(tasks map[string]*Task) {
	for _, task := range tasks {
		if task.Status == StatusDone || task.Status == StatusInProgress {
			continue
		}
		if depsDone(task, tasks) {
			task.Status = StatusReady
		} else {
			task.Status = StatusBlocked
		}
	}
}

func ReadyTaskIDs(tasks map[string]*Task) []string {
	var ready []string
	for id, task := range tasks {
		if task.Status == StatusReady {
			ready = append(ready, id)
		}
	}
	sort.Strings(ready)
	return ready
}

func depsDone(task *Task, tasks map[string]*Task) bool {
	for _, dep := range task.DependsOn {
		depTask, ok := tasks[dep]
		if !ok || depTask.Status != StatusDone {
			return false
		}
	}
	return true
}
