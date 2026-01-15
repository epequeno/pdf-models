# Browser Testing with agent-browser

## Overview

[agent-browser](https://github.com/vercel-labs/agent-browser) is a headless browser automation CLI designed for AI agents. It provides fast, deterministic browser automation using element references (refs) that are ideal for automated testing and AI-driven workflows.

## Installation

```bash
npm install -g agent-browser
agent-browser install  # Downloads Chromium
```

On Linux, install system dependencies:
```bash
agent-browser install --with-deps
```

## Core Concepts

### Element References (Refs)

agent-browser uses a ref-based workflow optimized for automation:

1. Take a snapshot to get element references (`@e1`, `@e2`, etc.)
2. Interact with elements using those refs
3. Re-snapshot after page state changes

This approach is deterministic and avoids brittle CSS selectors.

### Sessions

Isolated browser instances via `--session` flag, each with separate:
- Cookies and storage
- Authentication state
- Browser history

## Common Commands

### Navigation

```bash
agent-browser open https://epequeno.app
agent-browser back
agent-browser forward
agent-browser reload
```

### Snapshots (Key for Automation)

```bash
# Full accessibility tree
agent-browser snapshot

# Interactive elements only (recommended for testing)
agent-browser snapshot -i

# Compact mode (removes empty elements)
agent-browser snapshot -i -c

# JSON output for programmatic use
agent-browser snapshot -i --json
```

### Interaction

```bash
# Click by ref
agent-browser click @e2

# Fill form field
agent-browser fill @e3 "test@example.com"

# Type text (doesn't clear first)
agent-browser type @e4 "Hello"

# Press keys
agent-browser press Enter
agent-browser press Tab
agent-browser press Control+a

# Check/uncheck
agent-browser check @e5
agent-browser uncheck @e5

# Select dropdown
agent-browser select @e6 "option-value"
```

### Getting Information

```bash
agent-browser get text @e1
agent-browser get html @e1
agent-browser get value @e1
agent-browser get title
agent-browser get url
```

### State Checking

```bash
agent-browser is visible @e1
agent-browser is enabled @e1
agent-browser is checked @e1
```

### Screenshots

```bash
agent-browser screenshot
agent-browser screenshot --full        # Full page
agent-browser screenshot login.png     # Save to file
```

### Semantic Element Finding

```bash
# Find by ARIA role
agent-browser find role button click --name "Sign In"

# Find by text content
agent-browser find text "Submit" click

# Find by label
agent-browser find label "Email" fill "user@example.com"
```

## Testing the PDF Models Frontend

### Login Flow

```bash
# Start a named session
export AGENT_BROWSER_SESSION=test-login

# Navigate to login page
agent-browser open https://epequeno.app

# Get interactive elements
agent-browser snapshot -i

# Fill credentials (using refs from snapshot)
# UI Test User: ui-test@pdf-models.local / UiTest123!
agent-browser fill @e1 "ui-test@pdf-models.local"
agent-browser fill @e2 "UiTest123!"

# Submit
agent-browser click @e3  # Or find the submit button
agent-browser find role button click --name "Sign In"

# Verify redirect to dashboard
agent-browser get url
# Should show /jobs or dashboard route
```

### Upload Flow

```bash
# After login, navigate to upload
agent-browser open https://epequeno.app/upload

# Snapshot to see form elements
agent-browser snapshot -i

# Select model (if dropdown)
agent-browser select @e2 "marker"

# Upload a PDF
agent-browser upload @e3 ./test-document.pdf

# Submit job
agent-browser find role button click --name "Submit"

# Wait for processing feedback
agent-browser wait 2000
agent-browser snapshot -i
```

### Dashboard Verification

```bash
agent-browser open https://epequeno.app/jobs

# Capture dashboard state
agent-browser snapshot -i

# Verify job cards are present
agent-browser get text @e1

# Take screenshot for visual verification
agent-browser screenshot dashboard.png --full
```

## Advanced Usage

### Authentication Headers

Skip login flow by passing auth headers:

```bash
agent-browser open https://api.epequeno.app/jobs \
  --headers '{"Authorization": "Bearer <token>"}'
```

### Headed Mode (Visible Browser)

```bash
agent-browser open https://epequeno.app --headed
```

### JSON Output for Scripting

```bash
agent-browser snapshot -i --json | jq '.elements[] | select(.role == "button")'
```

### Network Interception

```bash
# Block analytics
agent-browser network route "**/analytics/**" --abort

# Mock API response
agent-browser network route "**/api/jobs" --body '{"jobs": []}'
```

### Console and Error Monitoring

```bash
# View console logs
agent-browser console

# View page errors
agent-browser errors
```

### Debug Tracing

```bash
agent-browser trace start
# ... perform actions ...
agent-browser trace stop trace.zip
# Open trace.zip in Playwright Trace Viewer
```

## Typical AI Agent Workflow

1. **Navigate**: `agent-browser open <url>`
2. **Snapshot**: `agent-browser snapshot -i --json`
3. **Parse**: Identify target elements from refs
4. **Act**: Execute commands using refs (`click @e2`, `fill @e3 "value"`)
5. **Verify**: `agent-browser get text @e1` or `agent-browser is visible @e1`
6. **Re-snapshot**: After state changes, snapshot again

## Global Options

| Option | Description |
|--------|-------------|
| `--session <name>` | Isolated browser session |
| `--headers <json>` | HTTP headers (scoped to origin) |
| `--json` | Machine-readable output |
| `--headed` | Show browser window |
| `--full, -f` | Full page screenshot |
| `--debug` | Debug output |

## Environment Variables

| Variable | Description |
|----------|-------------|
| `AGENT_BROWSER_SESSION` | Default session name |
| `AGENT_BROWSER_EXECUTABLE_PATH` | Custom Chromium path |
| `AGENT_BROWSER_STREAM_PORT` | WebSocket streaming port |

## Tips

- Always use `snapshot -i` to get only interactive elements (smaller output)
- Use `--json` when scripting or parsing output programmatically
- Named sessions persist state between commands
- Refs (`@e1`) are more reliable than CSS selectors for automation
- Use `wait` command for dynamic content loading

---

*See also: [agent-browser GitHub](https://github.com/vercel-labs/agent-browser)*
