# Ralph Loop: Architecture & Implementation Reference

> Research compiled 2026-02-20.
> Purpose: comprehensive reference to build a ralph loop system from scratch.

---

## 1. What Is The Ralph Loop?

The Ralph (Wiggum) Loop is an **external orchestration shell** that wraps an AI coding agent (Claude Code, Amp, etc.) and re-invokes it repeatedly until a machine-verifiable completion signal appears — or a safety iteration limit is reached.

Named after the Simpsons character who persists regardless of outcome. The methodology is: stubborn, bounded iteration beats single-shot perfection.

**Core mental model:**
```
while (not COMPLETE and iterations < MAX):
    run_agent(task_prompt + context_files + git_history)
    check_output_for_completion_signal()
    increment_iteration()
```

This is an **outer loop controlled by the filesystem and a shell script** — entirely separate from the agent's internal reasoning loop.

---

## 2. Why It Exists: The Self-Assessment Problem

LLMs exit when they *think* they're done, not when they *are* done. Their self-assessment is unreliable by design — the model has no ground truth about whether tests pass, coverage thresholds are met, or acceptance criteria are satisfied.

Ralph solves this by removing the agent from the exit decision entirely:

| Dimension | Traditional / ReAct | Ralph Loop |
|-----------|---------------------|------------|
| Exit control | Agent decides | External script decides |
| Exit condition | LLM self-assessment | Exact string match |
| Context per run | Single growing session | Fresh window each iteration |
| Failure tolerance | Errors compound in context | Restart from filesystem state |
| Memory | Within context window | Git + files (survives restarts) |

The completion signal — e.g. `<promise>COMPLETE</promise>` — is an exact string the agent must output. The orchestrator script checks for it. If absent, the agent is re-invoked regardless of what it said.

---

## 3. End-to-End Process

### Phase 0: Requirements  *(human + LLM collaboration, no code)*

- Collaborate with the LLM to identify "jobs to be done"
- Break into **spec files** — one markdown file per topic in `specs/`
- Spec files are the single source of truth for everything downstream
- No implementation decisions made here — just requirements

### Phase 1: Planning  *(single agent run, not a loop)*

- Agent reads all spec files + the existing codebase
- Produces `IMPLEMENTATION_PLAN.md`: a prioritized, broken-down task list
- **Does not implement anything**
- Uses a dedicated prompt: `PROMPT_plan.md`
- Exits after writing the plan — this is a one-shot run, not a loop

The planning agent performs a gap analysis: what do the specs require vs what currently exists? It outputs an ordered list of tasks that close that gap, each sized to fit within a single context window.

### Phase 2: Build Loop  *(the ralph loop)*

- Shell script invokes the agent repeatedly
- Each iteration: fresh context window, agent reads state files, picks the top incomplete task, implements, runs validation, writes memory, commits, exits
- Shell script checks output for completion signal
- Loop continues until signal appears or `MAX_ITERATIONS` is hit
- Uses a dedicated prompt: `PROMPT_build.md`

**One task per iteration.** Fresh context prevents the compounding degradation that occurs when a long session accumulates errors and conflicting tool outputs.

---

## 4. File Structure

```
project/
├── CLAUDE.md                    # Auto-loaded by Claude Code — project knowledge base
├── CLAUDE.local.md              # Auto-loaded, gitignored — personal/local preferences
├── .claude/
│   ├── settings.json            # Stop hook configuration
│   └── rules/                   # Path-scoped rule files (optional)
│       ├── api.md               # Rules for src/api/**
│       └── tests.md             # Rules for tests/**
├── specs/                       # Requirements — one file per topic
│   ├── auth.md
│   └── payments.md
├── PROMPT_plan.md               # Injected prompt for planning phase
├── PROMPT_build.md              # Injected prompt for build loop
├── IMPLEMENTATION_PLAN.md       # Prioritised task list — shared state across iterations
├── prd.json                     # Structured task tracker with passes:true/false
├── progress.txt                 # Append-only episodic log
└── loop.sh                      # The orchestrator
```

### What each file does

**`CLAUDE.md`** — Project knowledge base. Auto-loaded by Claude Code at every session start, no instruction needed. This is where accumulated codebase knowledge lives: build commands, conventions, gotchas, architecture notes. Keep under 100 lines; use `@imports` or `.claude/rules/` for overflow.

**`CLAUDE.local.md`** — Same as CLAUDE.md but gitignored. For personal preferences, local URLs, sandbox credentials — things that shouldn't travel to other machines or teammates.

**`.claude/rules/*.md`** — Modular rule files loaded alongside CLAUDE.md. Can be scoped to specific file paths with YAML frontmatter (see §5). Useful for separating API rules, test conventions, security requirements, etc. without bloating the root CLAUDE.md.

**`PROMPT_plan.md`** — Injected into the planning phase agent. Tells the agent how to read specs, analyse the codebase, and produce IMPLEMENTATION_PLAN.md. One-shot.

**`PROMPT_build.md`** — Injected into every build loop iteration. Tells the agent: what files to read, what to implement, what validation to run, how to update memory files before exiting. **This is where behavioral instructions live** — without this, the agent won't maintain progress.txt, prd.json, etc.

**`IMPLEMENTATION_PLAN.md`** — The living task list produced by the planning phase and consumed by the build loop. Updated by the agent as tasks complete. Human-readable markdown checked list.

**`prd.json`** — Structured task state. Each story has a `passes` boolean. The loop terminates when all are `true`. This is the machine-readable source of truth for completion.

**`progress.txt`** — Append-only episodic log. Agent writes to it before exiting each iteration. Short-term memory: what was tried, what failed, what was learned. Never edited — only appended.

**`loop.sh`** — The orchestrator. Invokes the agent, checks for completion signal, enforces iteration limit. ~20 lines of bash.

---

## 5. Memory Architecture

### The critical distinction

Two completely different things get called "memory":

| Type | File | Contains | Who writes | When read |
|------|------|----------|-----------|-----------|
| **Behavioral instructions** | `PROMPT_build.md` | *How* the agent must behave | You | Every iteration (injected by loop.sh) |
| **Semantic knowledge** | `CLAUDE.md` | *What* the agent knows about the codebase | Agent + you | Every iteration (auto-loaded by Claude Code) |
| **Episodic log** | `progress.txt` | *What just happened* in recent iterations | Agent | Per explicit instruction in PROMPT_build.md |
| **Task state** | `prd.json` | *What's done* and what isn't | Agent | Per explicit instruction in PROMPT_build.md |
| **Immutable history** | Git commits | *What actually changed* | Agent | Agent reads `git log` explicitly |
| **Claude's own notes** | `~/.claude/projects/.../MEMORY.md` | Claude's automatic session learnings | Claude Code (automatic) | Every session start (first 200 lines) |

**The core principle: memory lives in the repository, not the conversation.**

`progress.txt` and `prd.json` are only read if `PROMPT_build.md` tells the agent to read them. `CLAUDE.md` is read automatically — no instruction needed. This distinction determines whether your memory system works.

### Claude Code's native memory hierarchy

Claude Code auto-loads these at startup, walking up the directory tree — highest to lowest priority:

```
/etc/claude-code/CLAUDE.md          → org-wide policy (managed by IT)
~/.claude/CLAUDE.md                 → personal preferences (all projects)
~/.claude/rules/*.md                → personal rules (all projects)
./CLAUDE.md or ./.claude/CLAUDE.md  → project shared (in git)
./.claude/rules/*.md                → project rules (in git)
./CLAUDE.local.md                   → project personal (gitignored)
```

**Subdirectory CLAUDE.md files load lazily** — only when the agent first reads a file in that directory. This keeps startup context lean and enables rich monorepo patterns:

```
project/
├── CLAUDE.md              ← always loaded
├── src/
│   └── CLAUDE.md          ← loaded when agent first touches src/
├── tests/
│   └── CLAUDE.md          ← loaded when agent first touches tests/
└── packages/
    ├── api/CLAUDE.md      ← loaded when agent first touches packages/api/
    └── web/CLAUDE.md      ← loaded when agent first touches packages/web/
```

### Path-scoped rules

Rules in `.claude/rules/` with `paths` YAML frontmatter only activate for matching files:

```markdown
---
paths:
  - "src/api/**/*.ts"
  - "src/api/**/*.test.ts"
---

# API Layer Rules
- All endpoints must validate input with zod
- Return errors using the shared ApiError class
- Every endpoint needs a corresponding integration test
```

Rules without `paths` frontmatter load unconditionally. This lets you keep global CLAUDE.md lean while having rich per-module instructions that don't consume context when irrelevant.

### CLAUDE.md `@import` syntax

CLAUDE.md files can pull in other files:

```markdown
See @README.md for project overview.
Build commands: @docs/build-guide.md

# Additional Rules
- Git workflow: @docs/git-workflow.md
```

Imports resolve relative to the file, not cwd. Max depth 5 hops. Useful for keeping CLAUDE.md as an index without bloating it.

### Claude Code's auto memory (separate system)

Claude Code maintains its own memory directory, separate from your in-repo files:

```
~/.claude/projects/<repo-hash>/memory/
├── MEMORY.md       ← first 200 lines injected every session automatically
├── debugging.md    ← loaded on demand when MEMORY.md references it
├── patterns.md
└── ...
```

This is local-only (not in git). The agent writes here automatically. You can prompt it explicitly: *"remember that we use pnpm, not npm"*. Enable with `CLAUDE_CODE_DISABLE_AUTO_MEMORY=0`.

For ralph loops, this complements your in-repo memory — it's where Claude stores personal observations that don't need to be shared with the team.

### AGENTS.md structure (starter template)

```markdown
## Build & Validation Commands
- Build: `npm run build`
- Test: `npm test -- --coverage`
- Lint: `npm run lint`
- Typecheck: `npx tsc --noEmit`
- All gates: `npm run build && npm test && npm run lint`

## Architecture Conventions
- Services live in /src/services, always constructor-injected
- Database access only through /src/repositories — never direct queries
- All API routes require a corresponding integration test in /tests/api/

## Gotchas
- (agent fills this in as it discovers them)

## Recent Learnings
- (agent appends here, compress into above sections periodically)
```

Keep under 100 lines. When it grows, have the agent summarize `progress.txt` entries into it, then truncate progress.txt.

### The compound learning flywheel

```
Iteration N: encounters a gotcha
    → writes to CLAUDE.md "## Gotchas"
        → Iteration N+1: avoids the same mistake
            → gets further, finds a deeper issue
                → writes that to CLAUDE.md
                    → Iteration N+2: avoids both mistakes
```

Over 20–50 iterations, CLAUDE.md becomes a dense, project-specific knowledge base. The agent gets measurably better with each cycle.

### Information flow per iteration

```
START:
  [auto] Claude Code loads CLAUDE.md hierarchy
  [prompt] Agent reads progress.txt (last N entries)
  [prompt] Agent reads prd.json (finds first passes=false)
  [prompt] Agent runs git log --oneline (sees recent changes)

DURING:
  Agent implements the task
  Agent runs validation gates (tests, lint, typecheck)

END (before exit):
  Agent appends to progress.txt
  Agent updates CLAUDE.md with any new discoveries
  Agent flips prd.json passes=true (if task succeeded)
  Agent commits (locks in the work)
  Agent exits (triggering stop hook check)
```

---

## 6. Task Design

### Sizing: fit within one context window

**Good (completable in ~30 mins of human work):**
- Add a database column with migration
- Add a UI component to an existing page
- Implement a single API endpoint
- Write tests for an existing module to reach X% coverage
- Fix all lint errors in a specific directory
- Add a filter dropdown to an existing list view

**Too large (break these down first):**
- "Build the authentication system"
- "Refactor the entire API layer"
- "Build the dashboard"
- "Add real-time features"

**Rule of thumb:** If you'd naturally break it into sub-tasks on a Jira board, break it in the PRD.

### Spec file format (Phase 0)

```markdown
# Payments: Stripe Webhook Handler

## Job to be done
Process Stripe webhook events to update order status in the database.

## Scope
- Receive POST /webhooks/stripe
- Verify webhook signature using Stripe secret
- Handle: payment_intent.succeeded, payment_intent.payment_failed
- Update orders table: status, paid_at, failure_reason
- Idempotent: duplicate events must not double-update

## Out of scope
- Refunds (separate spec)
- Subscription events (separate spec)

## Constraints
- Use existing Order repository (src/repositories/OrderRepository.ts)
- Stripe SDK already installed
- Webhook secret in env: STRIPE_WEBHOOK_SECRET
```

### PRD user story format (converted from specs in planning phase)

```json
{
  "id": "US-012",
  "description": "Create Stripe webhook endpoint at POST /webhooks/stripe",
  "acceptance_criteria": [
    "Endpoint exists and returns 200 for valid signed requests",
    "Returns 400 for invalid signatures",
    "Tests cover both success and failure signature cases"
  ],
  "passes": false,
  "priority": 1
}
```

### Completion promise design

The completion promise is an exact string the agent must output. It's checked by the stop hook / orchestrator. Design it carefully:

**Good — machine verifiable:**
```
Output <promise>COMPLETE</promise> when:
- All prd.json stories have passes=true
- npm test exits 0
- npm run lint exits 0
```

**Bad — subjective:**
```
Output DONE when you think the feature is complete.
```

The default from Letta's implementation is deliberately verbose to prevent casual false positives:
```
"The task is complete. All requirements have been implemented and verified working."
```

Whatever you choose, it must be:
- An exact string (no variation)
- Something the agent would only output when genuinely done
- Checked by the orchestrator with a simple grep/string match

---

## 7. The Stop Hook Mechanism

Claude Code supports **stop hooks** — shell commands that execute when the agent attempts to exit. Ralph uses this to intercept premature exits:

**`.claude/settings.json`:**
```json
{
  "hooks": {
    "Stop": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "bash .claude/ralph-stop-hook.sh"
          }
        ]
      }
    ]
  }
}
```

**`.claude/ralph-stop-hook.sh`:**
```bash
#!/bin/bash
# Exit code 0 = allow the agent to stop
# Exit code 2 = block the stop, reinject prompt

ITERATION_FILE=".claude/iteration_count"
MAX_ITERATIONS=${MAX_ITERATIONS:-20}
CURRENT=$(cat "$ITERATION_FILE" 2>/dev/null || echo 0)

# Read the agent's last output
LAST_OUTPUT=$(cat .claude/last_output 2>/dev/null || echo "")

# Check for completion promise
if echo "$LAST_OUTPUT" | grep -q "<promise>COMPLETE</promise>"; then
  echo "Completion promise found. Allowing exit."
  exit 0
fi

# Check iteration limit
if [ "$CURRENT" -ge "$MAX_ITERATIONS" ]; then
  echo "Max iterations ($MAX_ITERATIONS) reached. Allowing exit."
  exit 0
fi

# Increment and continue
echo $((CURRENT + 1)) > "$ITERATION_FILE"
echo "Iteration $((CURRENT + 1))/$MAX_ITERATIONS — reinjecting prompt."
exit 2
```

The alternative (and simpler) approach is a plain bash loop in `loop.sh` that doesn't use stop hooks at all — it just invokes `claude --print` with the prompt file and checks the output itself (see §9).

---

## 8. Cycle vs Task: The Key Distinction

This is the most counterintuitive aspect of ralph loops.

**A "cycle"** = one invocation of loop.sh (bounded by `--max-iterations`)
**A "task"** = a unit of work in prd.json (persists indefinitely across cycles)

```
CYCLE 1:
  iter 1: works on Task X → no completion signal
  iter 2: works on Task X → no completion signal
  iter 3: MAX_ITERATIONS hit → CYCLE ENDS
  Result: Task X still has passes=false in prd.json

CYCLE 2 (you run loop.sh again):
  iter 1: reads prd.json → Task X incomplete → works on it again
  iter 2: outputs <promise>COMPLETE</promise>
  Result: Task X passes=true, moves to next task
```

**The agent does not decide to stop.** The external shell script stops the cycle. The agent is always trying to continue. Nothing is lost between cycles — state lives entirely in files and git.

**Why this design:**
1. **Cost control** — each cycle is a bounded token budget; you decide how much to spend per run
2. **Human checkpoints** — natural inspection point: review git diff, check progress.txt, decide whether to re-run
3. **Handles hard problems** — a task that needs multiple attempts across cycles is fine; it just keeps going

**When to intervene manually:** If the same task fails to complete after 3+ cycles:
- Break the task into smaller pieces in prd.json
- Add missing context to CLAUDE.md (gotchas, architecture details)
- Check if the validation gate (tests/lint) is itself broken
- Consider running a single manual iteration to unblock it

**Iteration limits by task size:**
- Small tasks: 3–5 iterations
- Medium tasks: 10–20 iterations
- Large tasks: 30–50 iterations

---

## 9. Implementation Templates

### `loop.sh` — The orchestrator

```bash
#!/bin/bash
MAX_ITERATIONS=${1:-20}
PROMPT_FILE="${2:-PROMPT_build.md}"
ITERATION=0
COMPLETE=false

echo "Starting ralph loop: max=$MAX_ITERATIONS prompt=$PROMPT_FILE"

while [ $ITERATION -lt $MAX_ITERATIONS ]; do
  ITERATION=$((ITERATION + 1))
  TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
  echo ""
  echo "=== [$TIMESTAMP] Iteration $ITERATION / $MAX_ITERATIONS ==="

  # Run agent, capture output
  OUTPUT=$(claude --print --no-stream < "$PROMPT_FILE" 2>&1)
  EXIT_CODE=$?

  # Append raw output to progress log
  {
    echo ""
    echo "--- iteration $ITERATION ($TIMESTAMP) ---"
    echo "$OUTPUT"
  } >> progress.txt

  # Check for completion promise
  if echo "$OUTPUT" | grep -q "<promise>COMPLETE</promise>"; then
    echo "Completion promise received. Loop complete after $ITERATION iterations."
    COMPLETE=true
    break
  fi

  echo "No completion signal. Continuing..."
  sleep 2
done

if [ "$COMPLETE" = false ]; then
  echo ""
  echo "Max iterations ($MAX_ITERATIONS) reached without completion."
  echo "Task state preserved in prd.json. Review progress.txt for context."
  echo "Re-run loop.sh to continue."
  exit 1
fi

exit 0
```

**Usage:**
```bash
chmod +x loop.sh
./loop.sh              # 20 iterations (default)
./loop.sh 5            # 5 iterations
./loop.sh 50 PROMPT_build.md
```

### `PROMPT_plan.md` — Planning phase instructions

```markdown
You are in PLANNING MODE. Do not write any code.

## Your task
Analyse the codebase and the spec files in specs/ to produce a prioritised implementation plan.

## Steps
1. Read all files in specs/ to understand the requirements
2. Explore the existing codebase: structure, patterns, key files, existing tests
3. Identify the gap: what do the specs require that doesn't exist yet?
4. Break the gap into tasks, each completable in a single coding session
5. Write IMPLEMENTATION_PLAN.md with the prioritised task list (see format below)
6. Write prd.json with the same tasks in structured format (see format below)
7. Write initial CLAUDE.md sections for: build commands, architecture conventions (what you observed)

## IMPLEMENTATION_PLAN.md format
```
# Implementation Plan

## Status
Generated: <date>
Total tasks: N
Completed: 0

## Tasks (priority order)
- [ ] US-001: <one-sentence description> — acceptance: <criteria>
- [ ] US-002: <one-sentence description> — acceptance: <criteria>
...
```

## prd.json format
```json
{
  "generated": "<date>",
  "stories": [
    {
      "id": "US-001",
      "description": "<one sentence>",
      "acceptance_criteria": ["<verifiable criterion>", "..."],
      "passes": false,
      "priority": 1
    }
  ]
}
```

## Task sizing rules
- Each task must be completable in one coding session (30 mins human equivalent)
- If a task requires touching more than 3–4 files, split it
- Each task must have machine-verifiable acceptance criteria
- Do NOT include tasks that require subjective judgment

## Exit
When IMPLEMENTATION_PLAN.md and prd.json are written, print a summary and exit normally.
Do NOT output the completion promise. Planning phase has no loop.
```

### `PROMPT_build.md` — Build loop instructions

```markdown
You are in BUILD MODE. One task per iteration.

## Context files — read these first, in order
1. CLAUDE.md — project conventions, commands, architecture
2. progress.txt (last 20 lines) — what happened in recent iterations
3. prd.json — find the first story where passes=false; that is your task
4. IMPLEMENTATION_PLAN.md — broader context on the plan
5. Run: git log --oneline -10 — see what has changed recently

## Your task
Implement the first incomplete story from prd.json.

## Validation gates — ALL must pass before marking complete
Run these in order. Fix failures before proceeding:
```
npm run build
npm test
npm run lint
npx tsc --noEmit
```

## On success
1. Set `passes: true` for the story in prd.json
2. Update IMPLEMENTATION_PLAN.md (check off the task)
3. Commit with: `git commit -m "feat(US-XXX): <description>"`

## Before exiting (MANDATORY)
Regardless of success or failure, you MUST do all of these:
1. Append to progress.txt:
   ```
   [iteration - <timestamp>]
   Task: <task id and description>
   Status: PASSED | FAILED
   What happened: <brief summary>
   Errors encountered: <if any>
   Fixes applied: <if any>
   New discoveries: <patterns, gotchas, constraints found>
   ```
2. Update CLAUDE.md with any new gotchas, patterns, or conventions discovered
3. If status is FAILED: describe clearly what blocked you

## Completion check
After marking a story passed: check if ALL stories in prd.json now have passes=true.
If yes: output exactly — <promise>COMPLETE</promise>
If no: exit normally (the loop will re-invoke you for the next task).

## Important
- Do not attempt more than one story per iteration
- Do not modify spec files in specs/
- Do not modify PROMPT_build.md or PROMPT_plan.md
- If validation gates are themselves broken (not caused by your changes), document in progress.txt and exit
```

### `CLAUDE.md` — Starter template

```markdown
# Project: <name>

## Build & Validation Commands
- Build: `npm run build`
- Test: `npm test`
- Test with coverage: `npm test -- --coverage`
- Lint: `npm run lint`
- Typecheck: `npx tsc --noEmit`
- All gates: `npm run build && npm test && npm run lint && npx tsc --noEmit`

## Project Structure
- `src/` — application source
- `tests/` — test files (mirrors src/ structure)
- `specs/` — requirements documents (do not modify)
- `prd.json` — task tracker (update as tasks complete)
- `progress.txt` — iteration log (append only)

## Architecture Conventions
(agent fills this in during planning and build phases)

## Gotchas
(agent fills this in as discovered)

## Recent Learnings
(agent appends here; compress into above sections when list grows long)
```

---

## 10. Concrete Use Cases

### Test coverage expansion
```
Task: "Increase test coverage for /src/auth from 40% to 80%.
Acceptance: npm test -- --coverage shows ≥80% for src/auth/**"
```
Entirely objective. Ralph writes tests, checks the number, repeats until hit.

### Lint/type error elimination
```
Task: "Fix all ESLint errors in /src/components.
Acceptance: npm run lint exits with code 0, no suppressions added."
```
Machine-verifiable exit condition — ideal for ralph.

### Feature from spec
```
specs/payments.md → planning phase → 6 tasks in prd.json
→ build loop executes one per iteration, committing after each
→ each commit is reviewable independently
```

### Incremental refactor
```
Task: "Refactor UserService to repository pattern per specs/architecture.md.
Acceptance: all existing tests pass, no direct DB queries outside /src/repositories."
```

### Debt elimination campaigns
```
Task: "Remove all usages of deprecated ApiV1Client across the codebase.
Replace with ApiV2Client. All tests pass."
```
This is where ralph shines — grinding through N files systematically.

---

## 11. What Ralph Is NOT Suited For

- Tasks requiring subjective judgment: design decisions, UX choices, architecture debates
- Strategic planning and prioritisation
- Exploratory research or investigation (use single-shot instead)
- Tasks without machine-verifiable completion criteria
- Tasks larger than one context window that haven't been broken down first
- Any task where "done" is defined by human aesthetic opinion rather than a test

---

## 12. Advanced Patterns

### Dual-model review (worker + reviewer)

Some implementations use two separate model invocations per cycle:
1. **Worker model** implements the task
2. **Reviewer model** evaluates it: "SHIP" or "REVISE"

This removes self-assessment bias at a deeper level — the completing agent and the judging agent are independent. Used in Goose's ralph implementation.

### Human-in-the-loop checkpoints

For sensitive work, run `loop.sh` with `MAX_ITERATIONS=1` — one task per run. Review the git diff, then re-run. This gives full oversight while still automating the implementation work.

Some implementations (ralph-orchestrator) support Telegram integration — the agent can message you mid-loop when it hits a decision that needs human input.

### Parallel task streams

For independent areas of the codebase (e.g. backend + frontend), run two ralph loops in parallel using git worktrees. Each has its own prd.json scoped to its domain.

### Progress.txt overflow management

When `progress.txt` grows beyond ~100 lines:
```
Prompt: "Read progress.txt. Summarise the key learnings, gotchas, and patterns
into CLAUDE.md under appropriate sections. Then truncate progress.txt to the
last 10 entries."
```

### Plan drift recovery

Plans in `IMPLEMENTATION_PLAN.md` can go stale if requirements change or the codebase evolves significantly. Rather than trying to patch a stale plan:
```
Delete IMPLEMENTATION_PLAN.md → re-run planning phase
```
The new plan will incorporate everything that's already been built (it's visible in the codebase and git history).

---

## 13. Knowing When To Intervene

| Signal | What it means | Action |
|--------|---------------|--------|
| Same task fails 3+ cycles | Task too large or missing context | Split task OR add context to CLAUDE.md |
| Agent keeps hitting lint errors | Lint config issue or wrong auto-fix | Fix lint config manually, document in CLAUDE.md |
| Tests broken before agent starts | Pre-existing test failures | Fix manually, then restart loop |
| Agent modifying spec files | Prompt not clear enough | Add explicit "do not modify specs/" instruction |
| Agent marking tasks done without passing gates | Completion prompt too weak | Strengthen completion promise requirements |
| Progress.txt shows same error repeated | Agent can't self-correct this issue | Intervene manually, add fix to CLAUDE.md |

---

## Sources

- [everything is a ralph loop — Geoffrey Huntley](https://ghuntley.com/loop/)
- [Inventing the Ralph Wiggum Loop — Dev Interrupted](https://devinterrupted.substack.com/p/inventing-the-ralph-wiggum-loop-creator)
- [From ReAct to Ralph Loop — Alibaba Cloud](https://www.alibabacloud.com/blog/from-react-to-ralph-loop-a-continuous-iteration-paradigm-for-ai-agents_602799)
- [GitHub: snarktank/ralph](https://github.com/snarktank/ralph)
- [GitHub: mikeyobrien/ralph-orchestrator](https://github.com/mikeyobrien/ralph-orchestrator)
- [Getting Started With Ralph — AIHero](https://www.aihero.dev/getting-started-with-ralph)
- [The Ralph Wiggum Playbook — paddo.dev](https://paddo.dev/blog/ralph-wiggum-playbook/)
- [Ralph Loop — Goose docs](https://block.github.io/goose/docs/tutorials/ralph-loop/)
- [Ralph Mode (forced continuation) — Letta Docs](https://docs.letta.com/letta-code/ralph-mode/)
- [Ralph Wiggum Loop — Agent Factory / Panaversity](https://agentfactory.panaversity.org/docs/General-Agents-Foundations/general-agents/ralph-wiggum-loop)
- [Ralph TUI](https://ralph-tui.com/)
- [GitHub: vercel-labs/ralph-loop-agent](https://github.com/vercel-labs/ralph-loop-agent)
- [Manage Claude's memory — Official Claude Code Docs](https://code.claude.com/docs/en/memory)
- [Writing a good CLAUDE.md — HumanLayer](https://www.humanlayer.dev/blog/writing-a-good-claude-md)
- [Self-Improving Coding Agents — Addy Osmani](https://addyosmani.com/blog/self-improving-agents/)
- [The RALPH Loop — Understanding Data](https://understandingdata.com/posts/ralph-loop/)
- [11 Tips For AI Coding With Ralph Wiggum — AIHero](https://www.aihero.dev/tips-for-ai-coding-with-ralph-wiggum)
