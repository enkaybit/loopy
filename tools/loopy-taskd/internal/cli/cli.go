package cli

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"net/url"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"time"

	"github.com/enkaybit/loopy/tools/loopy-taskd/internal/config"
	"github.com/enkaybit/loopy/tools/loopy-taskd/internal/parser"
	"github.com/enkaybit/loopy/tools/loopy-taskd/internal/task"
	"go.temporal.io/api/serviceerror"
	"go.temporal.io/sdk/client"
)

const (
	exitOK                  = 0
	exitTemporalUnreachable = 10
	exitWorkflowNotFound    = 11
	exitTaskNotFound        = 20
	exitTaskBlocked         = 21
	exitTaskClaimed         = 22
	exitInvalidClaimant     = 23
	exitImportRejected      = 24
	exitUsage               = 64
)

const (
	workflowIDPrefix = "loopy-plan-"
)

func Execute(args []string, stdout, stderr io.Writer) int {
	if len(args) == 0 {
		usage(stderr)
		return exitUsage
	}

	switch args[0] {
	case "status":
		return runStatus(args[1:], stdout, stderr)
	case "import":
		return runImport(args[1:], stdout, stderr)
	case "list":
		return runList(args[1:], stdout, stderr)
	case "claim":
		return runUpdate(args[1:], stdout, stderr, task.UpdateClaimTask)
	case "heartbeat":
		return runUpdate(args[1:], stdout, stderr, task.UpdateHeartbeatTask)
	case "checkpoint":
		return runUpdate(args[1:], stdout, stderr, task.UpdateCheckpointTask)
	case "complete":
		return runUpdate(args[1:], stdout, stderr, task.UpdateCompleteTask)
	default:
		usage(stderr)
		return exitUsage
	}
}

func runStatus(args []string, stdout, stderr io.Writer) int {
	fs := flag.NewFlagSet("status", flag.ContinueOnError)
	plan := fs.String("plan", "", "Path to plan file")
	fs.SetOutput(stderr)
	if err := fs.Parse(args); err != nil {
		return exitUsage
	}

	return withClient(stderr, func(ctx context.Context, cfg config.Config, c client.Client) int {
		if *plan == "" {
			fmt.Fprintln(stdout, "ok")
			return exitOK
		}
		workflowID, err := workflowIDForPlan(*plan)
		if err != nil {
			fmt.Fprintf(stderr, "workflow id: %v\n", err)
			return exitUsage
		}
		_, err = c.DescribeWorkflowExecution(ctx, workflowID, "")
		if err != nil {
			if isNotFound(err) {
				fmt.Fprintf(stderr, "workflow not found: %s\n", workflowID)
				return exitWorkflowNotFound
			}
			fmt.Fprintf(stderr, "status error: %v\n", err)
			return exitTemporalUnreachable
		}
		fmt.Fprintln(stdout, "ok")
		return exitOK
	})
}

func runImport(args []string, stdout, stderr io.Writer) int {
	fs := flag.NewFlagSet("import", flag.ContinueOnError)
	plan := fs.String("plan", "", "Path to plan file")
	fs.SetOutput(stderr)
	if err := fs.Parse(args); err != nil {
		return exitUsage
	}
	if *plan == "" {
		fmt.Fprintln(stderr, "--plan is required")
		return exitUsage
	}

	return withClient(stderr, func(ctx context.Context, cfg config.Config, c client.Client) int {
		workflowID, err := workflowIDForPlan(*plan)
		if err != nil {
			fmt.Fprintf(stderr, "workflow id: %v\n", err)
			return exitUsage
		}
		specs, err := parser.ParsePlan(*plan)
		if err != nil {
			fmt.Fprintf(stderr, "parse plan: %v\n", err)
			return exitUsage
		}
		if err := ensureWorkflow(ctx, cfg, c, workflowID); err != nil {
			fmt.Fprintf(stderr, "start workflow: %v\n", err)
			return exitTemporalUnreachable
		}
		handle, err := c.UpdateWorkflow(ctx, workflowID, "", task.UpdateUpsertTasks, task.UpsertTasksInput{Tasks: specs})
		if err != nil {
			if isNotFound(err) {
				fmt.Fprintf(stderr, "workflow not found: %s\n", workflowID)
				return exitWorkflowNotFound
			}
			fmt.Fprintf(stderr, "update failed: %v\n", err)
			return exitTemporalUnreachable
		}
		var resp task.UpdateResponse
		if err := handle.Get(ctx, &resp); err != nil {
			fmt.Fprintf(stderr, "update response: %v\n", err)
			return exitTemporalUnreachable
		}
		if err := writeJSON(stdout, resp); err != nil {
			fmt.Fprintf(stderr, "write response: %v\n", err)
			return exitUsage
		}
		if !resp.Ok {
			fmt.Fprintf(stderr, "import rejected: %s\n", resp.Reason)
			return exitImportRejected
		}
		return exitOK
	})
}

func runList(args []string, stdout, stderr io.Writer) int {
	fs := flag.NewFlagSet("list", flag.ContinueOnError)
	plan := fs.String("plan", "", "Path to plan file")
	fs.SetOutput(stderr)
	if err := fs.Parse(args); err != nil {
		return exitUsage
	}
	if *plan == "" {
		fmt.Fprintln(stderr, "--plan is required")
		return exitUsage
	}

	return withClient(stderr, func(ctx context.Context, cfg config.Config, c client.Client) int {
		workflowID, err := workflowIDForPlan(*plan)
		if err != nil {
			fmt.Fprintf(stderr, "workflow id: %v\n", err)
			return exitUsage
		}
		value, err := c.QueryWorkflow(ctx, workflowID, "", task.QueryTaskBoardState)
		if err != nil {
			if isNotFound(err) {
				fmt.Fprintf(stderr, "workflow not found: %s\n", workflowID)
				return exitWorkflowNotFound
			}
			fmt.Fprintf(stderr, "query failed: %v\n", err)
			return exitTemporalUnreachable
		}
		var snapshot task.TaskBoardSnapshot
		if err := value.Get(&snapshot); err != nil {
			fmt.Fprintf(stderr, "decode snapshot: %v\n", err)
			return exitUsage
		}
		if err := writeJSON(stdout, snapshot); err != nil {
			fmt.Fprintf(stderr, "write response: %v\n", err)
			return exitUsage
		}
		return exitOK
	})
}

func runUpdate(args []string, stdout, stderr io.Writer, updateName string) int {
	fs := flag.NewFlagSet(updateName, flag.ContinueOnError)
	plan := fs.String("plan", "", "Path to plan file")
	taskID := fs.String("task", "", "Task ID")
	message := fs.String("message", "", "Checkpoint message")
	fs.SetOutput(stderr)
	if err := fs.Parse(args); err != nil {
		return exitUsage
	}
	if *plan == "" || *taskID == "" {
		fmt.Fprintln(stderr, "--plan and --task are required")
		return exitUsage
	}
	if updateName == task.UpdateCheckpointTask && *message == "" {
		fmt.Fprintln(stderr, "--message is required for checkpoint")
		return exitUsage
	}

	return withClient(stderr, func(ctx context.Context, cfg config.Config, c client.Client) int {
		workflowID, err := workflowIDForPlan(*plan)
		if err != nil {
			fmt.Fprintf(stderr, "workflow id: %v\n", err)
			return exitUsage
		}
		var input interface{}
		switch updateName {
		case task.UpdateClaimTask:
			input = task.ClaimTaskInput{TaskID: *taskID, Claimant: cfg.WorkerID}
		case task.UpdateHeartbeatTask:
			input = task.HeartbeatTaskInput{TaskID: *taskID, Claimant: cfg.WorkerID}
		case task.UpdateCheckpointTask:
			input = task.CheckpointTaskInput{TaskID: *taskID, Claimant: cfg.WorkerID, Message: *message}
		case task.UpdateCompleteTask:
			input = task.CompleteTaskInput{TaskID: *taskID, Claimant: cfg.WorkerID}
		default:
			fmt.Fprintf(stderr, "unknown update %s\n", updateName)
			return exitUsage
		}

		handle, err := c.UpdateWorkflow(ctx, workflowID, "", updateName, input)
		if err != nil {
			if isNotFound(err) {
				fmt.Fprintf(stderr, "workflow not found: %s\n", workflowID)
				return exitWorkflowNotFound
			}
			fmt.Fprintf(stderr, "update failed: %v\n", err)
			return exitTemporalUnreachable
		}
		var resp task.UpdateResponse
		if err := handle.Get(ctx, &resp); err != nil {
			fmt.Fprintf(stderr, "update response: %v\n", err)
			return exitTemporalUnreachable
		}

		if err := writeJSON(stdout, resp); err != nil {
			fmt.Fprintf(stderr, "write response: %v\n", err)
			return exitUsage
		}

		summary := updateName
		if resp.Ok {
			summary = fmt.Sprintf("%s ok", updateName)
		} else {
			summary = fmt.Sprintf("%s %s", updateName, resp.Reason)
		}
		fmt.Fprintln(stderr, summary)

		return exitCodeForReason(resp.Reason)
	})
}

func ensureWorkflow(ctx context.Context, cfg config.Config, c client.Client, workflowID string) error {
	opts := client.StartWorkflowOptions{
		ID:        workflowID,
		TaskQueue: cfg.TaskQueue,
	}
	input := task.TaskBoardInput{
		LeaseTTL:           cfg.LeaseTTL,
		LeaseSweepInterval: cfg.LeaseSweepInterval,
	}
	_, err := c.ExecuteWorkflow(ctx, opts, task.TaskBoardWorkflow, input)
	if err == nil {
		return nil
	}
	if isAlreadyStarted(err) {
		return nil
	}
	return err
}

func exitCodeForReason(reason string) int {
	switch reason {
	case task.ReasonOK:
		return exitOK
	case task.ReasonNotFound:
		return exitTaskNotFound
	case task.ReasonBlocked:
		return exitTaskBlocked
	case task.ReasonClaimed:
		return exitTaskClaimed
	case task.ReasonInvalidClaimant, task.ReasonLeaseExpired:
		return exitInvalidClaimant
	default:
		return exitUsage
	}
}

func isNotFound(err error) bool {
	var target *serviceerror.NotFound
	return errors.As(err, &target)
}

func isAlreadyStarted(err error) bool {
	var target *serviceerror.WorkflowExecutionAlreadyStarted
	return errors.As(err, &target)
}

func workflowIDForPlan(planPath string) (string, error) {
	absPlan, err := filepath.Abs(planPath)
	if err != nil {
		return "", err
	}
	repoRoot, gitDir, err := findRepoRootAndGitDir(absPlan)
	if err != nil {
		return "", err
	}
	relPath, err := filepath.Rel(repoRoot, absPlan)
	if err != nil {
		return "", err
	}
	repoID := repoRoot
	if gitDir != "" {
		if remote, ok, err := readRemoteOriginURL(gitDir); err == nil && ok {
			if canonical := canonicalizeRemote(remote); canonical != "" {
				repoID = canonical
			} else {
				repoID = remote
			}
		}
	}
	hash := sha256.Sum256([]byte(repoID + ":" + relPath))
	return workflowIDPrefix + hex.EncodeToString(hash[:]), nil
}

func findRepoRootAndGitDir(planPath string) (string, string, error) {
	info, err := os.Stat(planPath)
	if err != nil {
		return "", "", err
	}
	start := planPath
	if !info.IsDir() {
		start = filepath.Dir(planPath)
	}

	dir := start
	for {
		gitPath := filepath.Join(dir, ".git")
		if _, err := os.Stat(gitPath); err == nil {
			gitDir, err := resolveGitDir(gitPath)
			if err != nil {
				return "", "", err
			}
			return dir, gitDir, nil
		}
		parent := filepath.Dir(dir)
		if parent == dir {
			break
		}
		dir = parent
	}
	return "", "", fmt.Errorf("repo root not found from %s", start)
}

func withClient(stderr io.Writer, fn func(context.Context, config.Config, client.Client) int) int {
	cfg, err := config.Load()
	if err != nil {
		fmt.Fprintf(stderr, "config error: %v\n", err)
		return exitUsage
	}
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()

	c, err := client.Dial(client.Options{
		HostPort:  cfg.TemporalAddress,
		Namespace: cfg.TemporalNamespace,
	})
	if err != nil {
		fmt.Fprintf(stderr, "temporal unreachable: %v\n", err)
		return exitTemporalUnreachable
	}
	defer c.Close()

	return fn(ctx, cfg, c)
}

func writeJSON(w io.Writer, value interface{}) error {
	enc := json.NewEncoder(w)
	enc.SetIndent("", "  ")
	return enc.Encode(value)
}

func usage(w io.Writer) {
	fmt.Fprintln(w, "Usage: loopy-tasks <command> [options]")
	fmt.Fprintln(w, "Commands: status, import, list, claim, heartbeat, checkpoint, complete")
}

func resolveGitDir(dotGitPath string) (string, error) {
	info, err := os.Stat(dotGitPath)
	if err != nil {
		return "", err
	}
	if info.IsDir() {
		return dotGitPath, nil
	}
	data, err := os.ReadFile(dotGitPath)
	if err != nil {
		return "", err
	}
	line := strings.TrimSpace(string(data))
	const prefix = "gitdir:"
	if !strings.HasPrefix(strings.ToLower(line), prefix) {
		return "", fmt.Errorf("unsupported .git file format at %s", dotGitPath)
	}
	gitDir := strings.TrimSpace(line[len(prefix):])
	if gitDir == "" {
		return "", fmt.Errorf("empty gitdir in %s", dotGitPath)
	}
	if !filepath.IsAbs(gitDir) {
		gitDir = filepath.Join(filepath.Dir(dotGitPath), gitDir)
	}
	return gitDir, nil
}

func readRemoteOriginURL(gitDir string) (string, bool, error) {
	configPath := filepath.Join(gitDir, "config")
	data, err := os.ReadFile(configPath)
	if err != nil {
		return "", false, err
	}
	inOrigin := false
	for _, raw := range strings.Split(string(data), "\n") {
		line := strings.TrimSpace(raw)
		if line == "" || strings.HasPrefix(line, "#") || strings.HasPrefix(line, ";") {
			continue
		}
		if strings.HasPrefix(line, "[") && strings.HasSuffix(line, "]") {
			section := strings.TrimSpace(line[1 : len(line)-1])
			inOrigin = section == `remote "origin"`
			continue
		}
		if !inOrigin {
			continue
		}
		if strings.HasPrefix(line, "url") {
			parts := strings.SplitN(line, "=", 2)
			if len(parts) != 2 {
				continue
			}
			return strings.TrimSpace(parts[1]), true, nil
		}
	}
	return "", false, nil
}

func canonicalizeRemote(remote string) string {
	s := strings.TrimSpace(remote)
	if s == "" {
		return ""
	}
	if strings.Contains(s, "://") {
		if parsed, err := url.Parse(s); err == nil {
			host := parsed.Host
			path := strings.TrimPrefix(parsed.Path, "/")
			s = path
			if host != "" {
				s = host + "/" + path
			}
		}
	} else if strings.Contains(s, "@") && strings.Contains(s, ":") {
		parts := strings.SplitN(s, "@", 2)
		s = parts[len(parts)-1]
		if idx := strings.Index(s, ":"); idx != -1 {
			s = s[:idx] + "/" + s[idx+1:]
		}
	}
	if at := strings.LastIndex(s, "@"); at != -1 {
		s = s[at+1:]
	}
	s = strings.TrimSuffix(s, ".git")
	s = strings.TrimSuffix(s, "/")
	if runtime.GOOS == "windows" {
		s = strings.ReplaceAll(s, "\\", "/")
	}
	return s
}
