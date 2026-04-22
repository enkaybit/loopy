---
name: loopy-address-review
description: Address code review feedback by evaluating validity and fixing issues. This skill should be used when the user says "address review feedback", "address PR comments", "fix the review feedback", or after a loopy-code-review agent produces findings.
user-invocable: true
context: fork
---

# loopy-address-review

Address code review feedback from local review agents or GitHub pull requests (PRs).

**This skill fixes feedback, not generates it.** Use code review agents to get feedback first, then use this skill to address it.

## Core Principles

> **Agent time is cheap. Tech debt is expensive.**

- **Fix everything valid** - Including nitpicks. Don't carry debt forward.
- **Reviewers can be wrong** - Verify concerns exist before fixing.
- **Quote feedback in replies** - Provide context for what was addressed.

---

## Mode Detection

| Trigger | Mode |
|---------|------|
| Code review agent just provided feedback in conversation | **Local Mode** (auto-invoke) |
| `/loopy-address-review` with no args | **PR Mode - Full** (current branch's PR) |
| User provides link to specific comment/thread | **PR Mode - Targeted** (only that feedback) |
| Ambiguous | Ask user |

**Targeted mode**: When user provides a specific feedback URL, ONLY address that feedback. Do not fetch or evaluate other PR feedback unless user explicitly asks.

---

## Local Mode (Post-Review Agent)

When a code review agent has just provided feedback:

### 1. Parse Feedback
Extract issues from the conversation - typically file:line references with descriptions.

### 2. Evaluate Each Item

| Category | Action |
|----------|--------|
| ✅ Valid concern | Fix (possibly with better approach than suggested) |
| ⚠️ Valid concern, bad suggestion | Fix differently |
| ❌ Invalid (misread code, already handled) | Skip with explanation |
| 🤔 Uncertain | Ask user |

### 3. Fix All Valid Issues
Read files, implement fixes, verify they work. **Do not commit yet.**

### 4. Batch Commit
After ALL fixes are implemented, create a single commit:

```bash
git add -A
git commit -m "Address code review feedback

- [list all changes]"
```

Report what was fixed vs. skipped (with reasons).

---

## PR Mode (GitHub Feedback)

### 1. Determine Scope

**No arguments** → Get current branch's PR:
```bash
gh pr view --json number,headRefName,baseRefName,url,author,isDraft
```

**Specific feedback URL provided** → Targeted mode:
- Extract the comment ID from the URL (e.g., `#discussion_r123456789` for a review comment, or `#issuecomment-123` for a conversation comment)
- Only fetch and address that specific feedback
- Do NOT evaluate other PR feedback unless user asks

### 2. Fetch Feedback

GitHub splits PR feedback across three surfaces; fetch whichever you need:

- **Inline review comments** (attached to diff lines):
  ```bash
  gh api repos/:owner/:repo/pulls/:number/comments --paginate
  ```
- **Reviews and their top-level bodies**:
  ```bash
  gh api repos/:owner/:repo/pulls/:number/reviews --paginate
  ```
- **PR conversation / issue comments** (non-inline):
  ```bash
  gh api repos/:owner/:repo/issues/:number/comments --paginate
  ```
- **Review threads with resolution state** (GraphQL — required to check `isResolved` and to resolve threads):
  ```bash
  gh api graphql -f query='
    query($owner:String!, $name:String!, $number:Int!) {
      repository(owner:$owner, name:$name) {
        pullRequest(number:$number) {
          reviewThreads(first:100) {
            nodes {
              id
              isResolved
              comments(first:20) { nodes { id databaseId body path line author { login } } }
            }
          }
        }
      }
    }' -F owner=OWNER -F name=REPO -F number=NUMBER
  ```

Use `gh repo view --json nameWithOwner` to get `OWNER/REPO` if needed.

**Targeted mode**: filter the fetched results to the single comment / thread referenced by the URL.

**Full mode**: evaluate all unresolved review threads and any open conversation comments.

### 3. Check for Stale Feedback

For comments referencing specific lines, verify the code still matches:
```bash
git show HEAD:$FILE_PATH | sed -n "${LINE}p"
```

If code changed significantly, verify the concern still applies before acting.

### 4. Evaluate Validity

Same framework as Local Mode.

### 5. Fix All Valid Issues

Read files, implement fixes, verify. **Do not commit yet** — batch all fixes.

### 6. Reply to Review Threads / Comments

Quote the original feedback:

```markdown
> [original feedback]

Addressed: [brief description]
```

For invalid feedback:
```markdown
> [original feedback]

Not addressing: [reason with evidence, e.g., "null check exists at line 85"]
```

Reply to an inline review comment (creates a threaded reply):
```bash
gh api repos/:owner/:repo/pulls/:number/comments/:comment_id/replies \
  -X POST -f body="$REPLY_BODY"
```

Reply on the PR conversation (non-inline):
```bash
gh api repos/:owner/:repo/issues/:number/comments \
  -X POST -f body="$REPLY_BODY"
```

### 7. Resolve Review Threads (If Allowed)

GitHub only lets the PR author or someone with write access resolve threads, and only via GraphQL:

```bash
gh api graphql -f query='
  mutation($threadId:ID!) {
    resolveReviewThread(input:{threadId:$threadId}) {
      thread { id isResolved }
    }
  }' -F threadId="$THREAD_ID"
```

`$THREAD_ID` is the node ID returned by the `reviewThreads` query in step 2. If you cannot resolve a thread (permissions, protected branch policies), leave a reply and note that resolution is pending reviewer action.

### 8. Batch Commit and Push

Single commit for all fixes:

```bash
git add -A
git commit -m "Address PR review feedback

- [list all changes]
- [threads resolved]"
git push
```

---

## GitHub CLI Usage

Always use the `gh` CLI. Fall back to raw API calls with `gh api` (REST) or `gh api graphql` only when high-level commands do not exist.

**If `gh` is not installed:** stop and tell the user to install `gh` (`brew install gh`, etc.) or handle PR feedback manually in the GitHub UI.

**Prefer high-level commands. Use `gh api` when required:**

| Operation | Command | Why |
|-----------|---------|-----|
| PR metadata | `gh pr view --json ...` | High-level, efficient |
| List review comments | `gh api repos/:owner/:repo/pulls/:number/comments` | No high-level equivalent for inline comments |
| List reviews | `gh api repos/:owner/:repo/pulls/:number/reviews` | No high-level equivalent |
| List conversation comments | `gh api repos/:owner/:repo/issues/:number/comments` | No high-level equivalent |
| Review threads + resolution state | `gh api graphql` with `reviewThreads` | Resolution state only available via GraphQL |
| Reply inline | `gh api repos/:owner/:repo/pulls/:number/comments/:id/replies -X POST` | No high-level equivalent |
| Resolve thread | `gh api graphql` with `resolveReviewThread` mutation | Only available via GraphQL |

Do NOT use `gh api` for operations that have high-level equivalents (e.g., creating a PR — use `gh pr create`).

---

## Validity Evaluation

```
1. Can I reproduce the concern?
   NO → Skip (explain why)

2. Is concern still relevant to current code?
   NO → Skip (explain code changed)

3. Would the fix improve the code?
   YES → Implement
   NO but concern valid → Implement better alternative
   NO and concern wrong → Skip (explain)
```

**When to ask user:** Architectural changes, security implications, conflicting conventions, business logic decisions.

---

## Examples

### PR Mode - Full

```
User: /loopy-address-review

Agent:
Fetching feedback for current branch's PR (#123)...

Found 3 unresolved review threads:

1. ✅ "Missing null check on user.email"
   → Adding null check at auth.js:45

2. ✅ "Unused import: lodash"
   → Removing unused import

3. ❌ "No error handling for API call"
   → Invalid: try/catch exists at line 78. Replying with explanation.

Committed and pushed. 2 fixed, 1 declined.
```

### PR Mode - Targeted

```
User: /loopy-address-review https://github.com/owner/repo/pull/123#discussion_r456

Agent:
Fetching specific feedback...

Comment: "Missing null check on user.email"
→ Valid concern. Adding null check at auth.js:45
```
