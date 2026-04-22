---
name: loopy-browse
description: "Browser automation with `agent-browser` for Codex, Claude Code, or Gemini CLI. Use whenever a browser would reduce guesswork: browse sites, read docs/articles, interact with web apps, fill forms, take screenshots, extract data, or test pages. Uses snapshot refs like `@e1` and shell-based workflows."
user-invocable: true
---

# loopy-browse

Use this skill when page state matters more than memory:

- Current site content
- Logged-in flows
- DOM-dependent debugging
- Forms, downloads, and uploads
- Screenshots, PDFs, and extraction

This skill is shell-first, so the same workflow works in Codex, Claude Code, and Gemini CLI as long as the agent can run `agent-browser` commands.

## Setup Check

```bash
command -v agent-browser >/dev/null 2>&1 && echo "Installed" || echo "NOT INSTALLED"
```

If needed:

```bash
npm install -g agent-browser
agent-browser install
```

## Core Rules

- Prefer `snapshot -i` before interacting.
- Prefer refs from the snapshot (`@e1`, `@e2`) over brittle selectors.
- Re-run `snapshot -i` after navigation or meaningful DOM changes.
- Use explicit waits for slow pages: `wait --url`, `wait --text`, or `wait --load networkidle`.
- Use screenshots when visual confirmation matters.

## Quick Start

```bash
agent-browser open https://example.com
agent-browser snapshot -i
agent-browser click @e1
agent-browser fill @e2 "search query"
agent-browser wait --load networkidle
agent-browser snapshot -i
```

## Commands

### Navigation

```bash
agent-browser open <url>
agent-browser back
agent-browser forward
agent-browser reload
agent-browser close
```

### Snapshot

```bash
agent-browser snapshot
agent-browser snapshot -i
agent-browser snapshot -i --json
agent-browser snapshot -c
agent-browser snapshot -d 3
agent-browser snapshot -s "#main"
agent-browser snapshot -i -C
```

### Interactions

```bash
agent-browser click @e1
agent-browser dblclick @e1
agent-browser fill @e1 "text"
agent-browser type @e1 "text"
agent-browser press Enter
agent-browser hover @e1
agent-browser focus @e1
agent-browser check @e1
agent-browser uncheck @e1
agent-browser select @e1 "option"
agent-browser scroll down 500
agent-browser scrollintoview @e1
agent-browser upload @e1 ./file.pdf
agent-browser download @e1 ./downloads/report.pdf
```

### Waits

```bash
agent-browser wait @e1
agent-browser wait 2000
agent-browser wait --text "Success"
agent-browser wait --url "**/dashboard"
agent-browser wait --load networkidle
agent-browser wait --download ./file.pdf
```

### Read Page State

```bash
agent-browser get text @e1
agent-browser get html @e1
agent-browser get value @e1
agent-browser get attr @e1 href
agent-browser get title
agent-browser get url
agent-browser get count "button"
agent-browser get box @e1
agent-browser get styles @e1
agent-browser is visible @e1
agent-browser is enabled @e1
agent-browser is checked @e1
```

### Screenshots and PDFs

```bash
agent-browser screenshot
agent-browser screenshot output.png
agent-browser screenshot --full
agent-browser screenshot --annotate
agent-browser pdf output.pdf
```

### Semantic Locators

Use these when a ref is not available yet or when you need a one-shot action.

```bash
agent-browser find role button click --name "Submit"
agent-browser find text "Sign in" click
agent-browser find label "Email" fill "user@example.com"
agent-browser find placeholder "Search" type "query"
```

### Sessions and Persistence

```bash
agent-browser --session browser1 open https://site1.com
agent-browser --session browser2 open https://site2.com
agent-browser session
agent-browser session list

agent-browser --profile ~/.myapp-profile open https://app.example.com
agent-browser --session-name myapp open https://app.example.com

agent-browser state save ./auth-state.json
agent-browser state load ./auth-state.json
```

### Auth, Cookies, and Storage

```bash
agent-browser open https://api.example.com --headers '{"Authorization":"Bearer <token>"}'

echo "password" | agent-browser auth save myapp \
  --url https://app.example.com/login \
  --username user@example.com \
  --password-stdin
agent-browser auth login myapp

agent-browser cookies get
agent-browser cookies clear
agent-browser storage local
agent-browser storage session
```

### Debugging and Diagnostics

```bash
agent-browser eval "document.title"
agent-browser console
agent-browser errors
agent-browser highlight @e1
agent-browser diff snapshot
agent-browser trace start
agent-browser trace stop trace.zip

agent-browser --headed open https://example.com
agent-browser --headed snapshot -i
```

## Agent Notes

### Codex

- Run `agent-browser` through the shell tool.
- Paste back the relevant output instead of dumping large snapshots verbatim.
- Prefer refs and screenshots over prose guesses.

### Claude Code

- Run the same shell commands via Bash.
- Keep the loop tight: `open`, `snapshot -i`, act by ref, re-snapshot.
- Use screenshots or annotated screenshots when handing off visual evidence.

### Gemini CLI

- Treat `agent-browser` as the browser execution layer and the model as the planner.
- Use short shell calls and inspect results between steps.
- Prefer page-grounded extraction over summarizing from memory.

## Examples

### Login Flow

```bash
agent-browser open https://app.example.com/login
agent-browser snapshot -i
agent-browser fill @e1 "user@example.com"
agent-browser fill @e2 "password123"
agent-browser click @e3
agent-browser wait --url "**/dashboard"
agent-browser snapshot -i
```

### Form Fill With Verification

```bash
agent-browser open https://forms.example.com
agent-browser snapshot -i
agent-browser fill @e1 "John Doe"
agent-browser fill @e2 "john@example.com"
agent-browser select @e3 "United States"
agent-browser check @e4
agent-browser click @e5
agent-browser wait --text "Thanks"
agent-browser screenshot confirmation.png
```

### Extraction

```bash
agent-browser open https://news.ycombinator.com
agent-browser snapshot -i
agent-browser get text @e12
agent-browser get attr @e12 href
```
