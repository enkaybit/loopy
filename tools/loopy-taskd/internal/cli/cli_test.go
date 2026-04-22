package cli

import (
	"crypto/sha256"
	"encoding/hex"
	"os"
	"path/filepath"
	"testing"
)

func TestWorkflowIDUsesRemoteOrigin(t *testing.T) {
	root := t.TempDir()
	gitDir := filepath.Join(root, ".git")
	if err := os.MkdirAll(gitDir, 0o755); err != nil {
		t.Fatalf("mkdir git dir: %v", err)
	}
	config := `[remote "origin"]
	url = git@github.com:acme/loopy.git
`
	if err := os.WriteFile(filepath.Join(gitDir, "config"), []byte(config), 0o644); err != nil {
		t.Fatalf("write config: %v", err)
	}

	planPath := filepath.Join(root, "docs", "plans", "plan.md")
	if err := os.MkdirAll(filepath.Dir(planPath), 0o755); err != nil {
		t.Fatalf("mkdir plan dir: %v", err)
	}
	if err := os.WriteFile(planPath, []byte("# Plan\n"), 0o644); err != nil {
		t.Fatalf("write plan: %v", err)
	}

	got, err := workflowIDForPlan(planPath)
	if err != nil {
		t.Fatalf("workflow id: %v", err)
	}
	relPath, _ := filepath.Rel(root, planPath)
	repoID := canonicalizeRemote("git@github.com:acme/loopy.git")
	sum := sha256.Sum256([]byte(repoID + ":" + relPath))
	want := workflowIDPrefix + hex.EncodeToString(sum[:])

	if got != want {
		t.Fatalf("workflow id mismatch: got %s want %s", got, want)
	}
}

func TestWorkflowIDUsesRemoteOriginFromGitFile(t *testing.T) {
	root := t.TempDir()
	gitDir := filepath.Join(root, ".gitdir")
	if err := os.MkdirAll(gitDir, 0o755); err != nil {
		t.Fatalf("mkdir git dir: %v", err)
	}
	config := `[remote "origin"]
	url = https://github.com/acme/loopy.git
`
	if err := os.WriteFile(filepath.Join(gitDir, "config"), []byte(config), 0o644); err != nil {
		t.Fatalf("write config: %v", err)
	}
	dotGit := filepath.Join(root, ".git")
	if err := os.WriteFile(dotGit, []byte("gitdir: .gitdir\n"), 0o644); err != nil {
		t.Fatalf("write .git file: %v", err)
	}

	planPath := filepath.Join(root, "docs", "plans", "plan.md")
	if err := os.MkdirAll(filepath.Dir(planPath), 0o755); err != nil {
		t.Fatalf("mkdir plan dir: %v", err)
	}
	if err := os.WriteFile(planPath, []byte("# Plan\n"), 0o644); err != nil {
		t.Fatalf("write plan: %v", err)
	}

	got, err := workflowIDForPlan(planPath)
	if err != nil {
		t.Fatalf("workflow id: %v", err)
	}
	relPath, _ := filepath.Rel(root, planPath)
	repoID := canonicalizeRemote("https://github.com/acme/loopy.git")
	sum := sha256.Sum256([]byte(repoID + ":" + relPath))
	want := workflowIDPrefix + hex.EncodeToString(sum[:])

	if got != want {
		t.Fatalf("workflow id mismatch: got %s want %s", got, want)
	}
}
