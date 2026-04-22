# Secrets & Auth Handling

Loopy skills and agents never read secret values directly. Tools that need
credentials (notably `gh` for PR creation and any private package registries
used by the code under build) must be authenticated **outside loopy**, through
the normal OS-level mechanisms.

## Guiding rule

**Never place secret values in files that live inside the repo or inside loopy
artifacts** (PRDs, plans, experiment logs, review reports, `.loopy/state.yml`).
They are committed, reviewed, and sometimes shared across the team.

If you are running loopy on a machine where a user-global `AGENTS.md` (or
equivalent) defines how to fetch secrets (for example via macOS Keychain or a
system secret store), agents must follow those rules. The loopy skills
themselves do not override them.

## `gh` (GitHub CLI) — required for PR creation

`/loopy-ship` and `pr-creator-worker` use `gh pr create`.
`gh` must already be authenticated before loopy runs. Options:

1. **Interactive auth (preferred for humans):**
   ```bash
   gh auth login --hostname github.com
   ```
2. **Token via environment variable (preferred for CI / ephemeral sessions):**
   ```bash
   export GH_TOKEN="$(security find-generic-password -a "$USER" -s github-api -w)"
   # or: export GH_TOKEN=$(pass show github/api-token)
   gh auth status
   ```
   Do not echo `$GH_TOKEN` (or the legacy `$GITHUB_TOKEN`) into logs, prompts,
   or artifacts. The `pr-creator-worker` agent only calls `gh`; it does not
   read or transmit the token.

Required token scopes for typical loopy flows:

- Classic PAT: `repo` (full) is sufficient. Prefer narrower scopes when the
  target repo is public (`public_repo` only).
- Fine-grained PAT: on the target repository, grant `Contents: read/write`,
  `Pull requests: read/write`, and (if you want to resolve review threads)
  `Metadata: read`.

In GitHub Actions, the built-in `GITHUB_TOKEN` provided to the workflow is
usually enough; `gh` picks it up automatically when `GH_TOKEN` or
`GITHUB_TOKEN` is set in the environment.

## Private package registries

Examples: npm scopes on GitHub Packages, PyPI mirrors, `pip` extra index URLs,
Go module proxies behind auth. These are **consumed by the build tooling**
(pnpm, poetry, pip, go), not by loopy directly. Configure them:

- via `~/.npmrc`, `~/.gitconfig`, `~/.netrc` with correct file permissions
  (`chmod 600`), **or**
- via environment variables populated at shell start-up from your OS secret
  store.

If a subtask's build step fails because a registry token is missing, the
`task-worker` agent should report the failure plainly — it must not paste
the token into the task description or commit message to "fix" it.

## `.loopy/state.yml`

The state file records branch, stage, section baselines, review references,
and budget counters. It is intended to be committable (optional), and must
**not** contain secrets. Everything the CLI writes to state is metadata
about workflow progress, not credentials.

## Browser automation (`agent-browser`, `loopy browser-capture`)

Browser-automation commands can exfiltrate credentials, take actions under a
logged-in session, or hit production URLs. These rules apply to both the
`loopy-browse` skill and the `loopy browser-capture` subcommand used by
`/loopy-spike` and `/loopy-code-review` for visual evidence.

- **Prefer local / static targets.** Screenshots for spikes and reviews should
  come from `file://` URLs, `http://localhost`, or a staging host. Do not
  capture production pages by default.
- **Explicit user confirmation for logged-in sessions.** `agent-browser`
  supports persisted sessions (`--session`, `auth save`, `state save`). Any
  skill that would operate under a saved session must present the target URL
  and session name to the user and require confirmation before executing.
- **Never embed credentials in program files or plans.** Credentials for
  `agent-browser auth save` come from `--password-stdin` or the environment,
  not from `.loopy/autoloop/programs/*.md`, PRDs, or plans.
- **Browser allowlist (forward-looking).** When `autoloop` programs or review
  workflows start driving logged-in sessions, the program / review config
  should declare a `browser_allowlist:` list of hosts the tool is permitted
  to reach. `loopy browser-capture` does not currently enforce this — the
  gate lives at the skill layer today — but program authors should write it
  in defensively so enforcement can be added without migration.
- **Screenshots are artifacts.** Captured screenshots are committed to the
  repo (under `docs/spikes/` or `docs/reviews/`). Before capturing, assume
  the screenshot will be readable by everyone who can see the repo — do not
  capture pages containing PII, API tokens, or secret query parameters.

## Autoloop programs (`.loopy/autoloop/programs/*.md`)

The `autoloop-optimizer` agent reads these files verbatim and uses them as
instructions. Treat them as code:

- Keep evaluation commands simple and auditable.
- Do not embed secrets in program files; read from environment at runtime.
- The autoloop safety gate only enforces *which files* the optimizer may
  modify — it does not sandbox arbitrary evaluation commands. Review new
  programs before running them on shared machines.

## AI agent responsibilities

When an agent needs a secret (e.g. to run `gh`, `pnpm publish`, or a
deployment command), it must:

1. Read only from the environment or a documented secret-fetch command.
2. Never print the secret value in its output.
3. Never persist the secret to state, plans, PRDs, review reports, or
   commit messages.
4. Stop and ask the user to provide authentication if the required
   mechanism is not available — do not guess or fall back to
   committing tokens.

These rules mirror the stricter form of per-machine `AGENTS.md` policies and
apply whether or not such a file exists on the current host.
