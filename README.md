# Ralph Loop Scaffold

A copy-paste scaffold for running [Ralph Loop](https://ghuntley.com/loop/) — an external orchestration shell that wraps an AI coding agent and re-invokes it repeatedly until a machine-verifiable completion signal appears.

## What is the Ralph Loop?

The agent exits when it *thinks* it's done, not when it *is* done. Ralph solves this by removing the agent from the exit decision entirely. A shell script checks for an exact completion signal. If absent, the agent is re-invoked with a fresh context window.

```
while (not COMPLETE and iterations < MAX):
    run_agent(prompt + filesystem state)
    check_output_for_completion_signal()
    increment_iteration()
```

## Files

| File | Purpose |
|------|---------|
| `loop-claude.sh` | Orchestrator for Claude Code |
| `loop-cursor.sh` | Orchestrator for Cursor agent |
| `PROMPT_spec.md` | Step 1 — discovery: brain dump → spec files |
| `PROMPT_plan.md` | Step 2 — planning: spec files → prd.json |
| `PROMPT_build.md` | Step 3 — fed into every loop iteration |
| `prd.json` | Task tracker (machine-readable, updated by agent) |
| `specs/` | Requirements — one file per feature |

## Workflow

### 1. Write specs (interactive)
Load `PROMPT_spec.md` into an active Claude/Cursor session with your raw ideas. The agent asks clarifying questions and writes `specs/<feature>.md`.

### 2. Plan (interactive)
Load `PROMPT_plan.md`. The agent reads your specs, explores the codebase, proposes a task breakdown, and iterates with you until approved. Writes `prd.json`.

### 3. Run the loop
```bash
# Claude Code
./loop-claude.sh          # 20 iterations (default)
./loop-claude.sh 10       # bounded run

# Cursor (requires CURSOR_API_KEY)
./loop-cursor.sh
./loop-cursor.sh 10
```

The loop runs until the agent outputs `<promise>COMPLETE</promise>` (all `prd.json` stories have `passes: true`) or the iteration cap is hit. State is preserved in `prd.json` and `progress.txt` — re-run to continue.

## Setup

1. Copy `.ralph/` into your project root
2. Write specs in `specs/` (delete `_example.md` first)
3. Run the workflow above

## Memory

Each iteration the agent appends to `progress.txt` — an append-only log of what happened. This is the short-term memory that survives context resets. The agent reads the last 20 lines at the start of each iteration.

`prd.json` is the source of truth for task state. The loop terminates when all stories have `"passes": true`.
