# Program Template

Use this template when creating autoloop program definitions. Save the program to `.loopy/autoloop/programs/<program-name>.md` in the repository root.

## Document Structure

```markdown
# Program: [name]

**Created:** [date]
**Status:** Active

## Goal

[What metric to optimize and in which direction. Must be measurable.
Describe what "better" means concretely — the optimizer uses this to
guide its proposals.]

Examples:
- "Minimize average response time for the /api/search endpoint"
- "Maximize test coverage percentage for the auth module"
- "Reduce bundle size of the main entry point below 150KB"

## Target

[Files the optimizer is allowed to modify. Only these files may be touched.
All other files are off-limits. List each file on its own line with a
backtick-quoted path.]

- `path/to/file1.ts`
- `path/to/file2.ts`

## Evaluation

### Command

[Shell command to run. Must exit 0 on success, non-zero on failure.
Output should contain the metric value.]

```bash
npm run test:coverage -- --reporter=json | jq '.total.lines.pct'
```

### Metric Extraction

[How to extract the numeric metric from the command output.
Use a regex pattern, jq expression, or "last numeric value in stdout".]

```
Pattern: /(\d+\.?\d*)%/
```

### Direction

[Either "minimize" or "maximize".]

minimize

### Tolerance

[Accepted metric regression before rejecting a change. Default: 0.
A tolerance of 0.5 means a change is accepted if the metric regresses
by less than 0.5 from the previous value.]

0

## Constraints

[Additional rules the optimizer must follow beyond only touching Target files.
These are domain-specific guardrails.]

- Do not change public API signatures
- Maintain backward compatibility
- Keep code readable — no micro-optimizations that obscure intent

## Stop Conditions

[When to stop iterating automatically, beyond manual intervention.]

- Target metric: [value, e.g., "95% coverage" or "< 100ms"]
- Max consecutive rejections: 3
- Max total iterations: 20
```

## Valid Status Values

- **Active** — Program is ready for iterations
- **Paused** — Temporarily disabled; autoloop will skip this program
- **Archived** — No longer active; kept for historical reference

## Guidelines

- Keep the Target list focused. Too many files makes changes diffuse and hard to review.
- The evaluation command should be deterministic — same inputs should produce similar metric values.
- Set a tolerance > 0 if your evaluation has inherent variance (e.g., benchmarks with noise).
- Constraints should be specific and actionable. "Write good code" is too vague.
- Stop conditions prevent runaway loops. Always set a max iteration cap.
