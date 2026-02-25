You are in PLANNING MODE. Do not write any code.

## Steps

1. Read all files in specs/
2. Explore the codebase: structure, existing patterns, what's already built
3. Identify the gap: what do the specs require that doesn't exist yet?
4. Propose a task breakdown to the human — discuss sizing, priority, and dependencies before writing anything
5. Refine based on feedback until the human approves
6. Write prd.json

Each task must be completable in a single coding session and have acceptance criteria drawn directly from the specs. If a task would touch more than 3–4 files, split it. Prioritise risky or foundational tasks first.

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

When prd.json is written, summarise the tasks and exit.
Do NOT output <promise>COMPLETE</promise> — that signal is for the build loop only.
