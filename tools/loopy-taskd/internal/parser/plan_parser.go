package parser

import (
	"errors"
	"fmt"
	"os"
	"regexp"
	"strings"

	"github.com/enkaybit/loopy/tools/loopy-taskd/internal/task"
)

var (
	parentRe  = regexp.MustCompile(`^###\s+Parent\s+\d+:\s+(.+)$`)
	subtaskRe = regexp.MustCompile(`^####\s+(\d+\.\d+)\s+(.+)$`)
	dependsRe = regexp.MustCompile(`^\*\*Depends on:\*\*\s*(.+)$`)
	filesRe   = regexp.MustCompile(`^\*\*Files:\*\*\s*(.+)$`)
	filesItem = regexp.MustCompile("`([^`]+)`")
	testRe    = regexp.MustCompile(`^\*\*Test scenarios:\*\*`)
)

type taskBuilder struct {
	spec       task.TaskSpec
	hasDepends bool
	hasFiles   bool
	inDesc     bool
	descLines  []string
}

func ParsePlan(path string) ([]task.TaskSpec, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	return ParsePlanBytes(data)
}

func ParsePlanBytes(data []byte) ([]task.TaskSpec, error) {
	lines := strings.Split(string(data), "\n")
	var tasks []task.TaskSpec
	parentTitle := ""
	var current *taskBuilder

	flush := func() error {
		if current == nil {
			return nil
		}
		if !current.hasDepends {
			return fmt.Errorf("task %s missing Depends on", current.spec.ID)
		}
		if !current.hasFiles {
			return fmt.Errorf("task %s missing Files", current.spec.ID)
		}
		current.spec.Description = strings.TrimSpace(strings.Join(current.descLines, "\n"))
		tasks = append(tasks, current.spec)
		current = nil
		return nil
	}

	for _, raw := range lines {
		line := strings.TrimSpace(raw)
		if line == "" {
			if current != nil && current.inDesc {
				current.descLines = append(current.descLines, "")
			}
			continue
		}
		if match := parentRe.FindStringSubmatch(line); match != nil {
			if err := flush(); err != nil {
				return nil, err
			}
			parentTitle = strings.TrimSpace(match[1])
			continue
		}
		if match := subtaskRe.FindStringSubmatch(line); match != nil {
			if err := flush(); err != nil {
				return nil, err
			}
			current = &taskBuilder{
				spec: task.TaskSpec{
					ID:          match[1],
					Title:       strings.TrimSpace(match[2]),
					ParentTitle: parentTitle,
				},
			}
			continue
		}
		if current == nil {
			continue
		}
		if match := dependsRe.FindStringSubmatch(line); match != nil {
			current.hasDepends = true
			deps := strings.TrimSpace(match[1])
			if strings.EqualFold(deps, "none") {
				current.spec.DependsOn = nil
			} else {
				parts := strings.Split(deps, ",")
				var depList []string
				for _, part := range parts {
					dep := strings.TrimSpace(part)
					if dep == "" {
						continue
					}
					depList = append(depList, dep)
				}
				current.spec.DependsOn = depList
			}
			continue
		}
		if match := filesRe.FindStringSubmatch(line); match != nil {
			current.hasFiles = true
			files := filesItem.FindAllStringSubmatch(match[1], -1)
			if len(files) == 0 {
				return nil, fmt.Errorf("task %s files must be backticked", current.spec.ID)
			}
			current.spec.Files = nil
			for _, file := range files {
				current.spec.Files = append(current.spec.Files, strings.TrimSpace(file[1]))
			}
			current.inDesc = true
			continue
		}
		if testRe.MatchString(line) {
			current.inDesc = false
			continue
		}
		if current.inDesc {
			current.descLines = append(current.descLines, raw)
		}
	}

	if err := flush(); err != nil {
		return nil, err
	}
	if len(tasks) == 0 {
		return nil, errors.New("no tasks found")
	}
	return tasks, nil
}
