package config

import (
	"crypto/rand"
	"encoding/hex"
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"
)

const (
	DefaultTemporalAddress    = "127.0.0.1:7233"
	DefaultTemporalNamespace  = "default"
	DefaultTaskQueue          = "loopy-task-queue"
	DefaultLeaseTTL           = 10 * time.Minute
	DefaultHeartbeatInterval  = 2 * time.Minute
	DefaultLeaseSweepInterval = 30 * time.Second
)

type Config struct {
	TemporalAddress    string
	TemporalNamespace  string
	TaskQueue          string
	LeaseTTL           time.Duration
	HeartbeatInterval  time.Duration
	LeaseSweepInterval time.Duration
	WorkerID           string
}

func Load() (Config, error) {
	cfg := Config{
		TemporalAddress:    envString("TEMPORAL_ADDRESS", DefaultTemporalAddress),
		TemporalNamespace:  envString("TEMPORAL_NAMESPACE", DefaultTemporalNamespace),
		TaskQueue:          envString("TEMPORAL_TASK_QUEUE", DefaultTaskQueue),
		LeaseTTL:           envDuration("LOOPY_TASK_LEASE_TTL", DefaultLeaseTTL),
		HeartbeatInterval:  envDuration("LOOPY_TASK_HEARTBEAT_INTERVAL", DefaultHeartbeatInterval),
		LeaseSweepInterval: envDuration("LOOPY_TASK_LEASE_SWEEP_INTERVAL", DefaultLeaseSweepInterval),
	}
	workerID, err := resolveWorkerID()
	if err != nil {
		return Config{}, err
	}
	cfg.WorkerID = workerID
	return cfg, nil
}

func envString(name, def string) string {
	if val := os.Getenv(name); val != "" {
		return val
	}
	return def
}

func envDuration(name string, def time.Duration) time.Duration {
	if val := os.Getenv(name); val != "" {
		parsed, err := time.ParseDuration(val)
		if err == nil {
			return parsed
		}
	}
	return def
}

func resolveWorkerID() (string, error) {
	if val := os.Getenv("LOOPY_TASK_WORKER_ID"); val != "" {
		return val, nil
	}
	home, err := os.UserHomeDir()
	if err != nil {
		return "", fmt.Errorf("resolve worker id home: %w", err)
	}
	path := filepath.Join(home, ".loopy", "worker_id")
	if data, err := os.ReadFile(path); err == nil {
		if id := strings.TrimSpace(string(data)); id != "" {
			return id, nil
		}
	} else if !os.IsNotExist(err) {
		return "", fmt.Errorf("read worker id: %w", err)
	}
	host, err := os.Hostname()
	if err != nil {
		return "", fmt.Errorf("resolve worker id hostname: %w", err)
	}
	randBytes := make([]byte, 8)
	if _, err := rand.Read(randBytes); err != nil {
		return "", fmt.Errorf("generate worker id: %w", err)
	}
	id := fmt.Sprintf("%s-%s", host, hex.EncodeToString(randBytes))
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return "", fmt.Errorf("create worker id dir: %w", err)
	}
	if err := os.WriteFile(path, []byte(id+"\n"), 0o600); err != nil {
		return "", fmt.Errorf("write worker id: %w", err)
	}
	return id, nil
}

func ParseExitCode(code string) (int, bool) {
	if code == "" {
		return 0, false
	}
	parsed, err := strconv.Atoi(code)
	if err != nil {
		return 0, false
	}
	return parsed, true
}
