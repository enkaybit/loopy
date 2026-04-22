# Changelog

All notable changes to loopy> will be documented here.

The format is based on Keep a Changelog, and this project follows SemVer.

## [Unreleased]

### Added
- `/loopy-optimize` skill for autonomous iterative optimization toward measurable goals
- `autoloop-optimizer` agent for proposing and implementing targeted metric improvements
- `loopy` helper CLI (pure Python stdlib) providing: PRD + tech-plan schema validation, `.loopy/state.yml` pipeline-state management, objective test-verification counter, review report persistence to `docs/reviews/`, and token/time/usd budget tracking
- `docs/secrets.md` covering `gh` auth, private registries, and agent secret-handling rules
- `docs/builtin-task-format.md` specifying the `.loopy/state.yml` schema and built-in task lifecycle
- `tools/loopy-cli/tests/run_tests.sh` with tests covering every CLI subcommand; wired into `make test`
- `loopy validate` integration in `/loopy-requirements`, `/loopy-plan`, and `/loopy-build` (plan validation gate before Phase 2)
- `loopy verify-tests` integration in `/loopy-build` Phase 2 and the `task-worker` agent
- `loopy review-save` integration in `/loopy-code-review` for deterministic review filenames and plan linking
- `loopy budget summary` integration in `/loopy-ship`
- GitHub-native CI: `.github/workflows/test.yml` runs `make test` on pushes and PRs
- `.github/pull_request_template.md` and `.github/ISSUE_TEMPLATE/` scaffolding

## [1.0.0]

### Added
- Initial release of loopy>
