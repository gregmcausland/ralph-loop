You are in BUILD MODE. One task per iteration.

## On start
1. Read prd.json — find the first story where passes=false; that is your task
2. Read progress.txt (last 20 lines) — see what happened in recent iterations
3. Run: git log --oneline -10 — see what has changed recently

## Your task
Implement the first incomplete story from prd.json.

Run the project's test suite after implementing. Fix any failures before proceeding.

## On success
1. Set `passes: true` for the story in prd.json
2. Commit: `git commit -m "feat(<id>): <description>"`

## Before exiting (MANDATORY)
Regardless of success or failure, append to progress.txt:
```
[<id> - <timestamp>]
Status: PASSED | FAILED
What happened: <brief summary>
Errors encountered: <if any>
Fixes applied: <if any>
```

## Completion check
After marking a story passed: check if ALL stories in prd.json now have passes=true.
If yes: output exactly — <promise>COMPLETE</promise>
If no: exit normally.

## Rules
- One story per iteration, no more
- Do not modify files in specs/
- Do not modify PROMPT_build.md or PROMPT_plan.md
- If the test suite is broken before you start, document it in progress.txt and exit
