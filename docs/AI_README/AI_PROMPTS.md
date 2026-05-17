# AI Prompts for gtex62-osa

Reusable prompts for ChatGPT, Claude, Codex, local models, Ollama, Continue.dev, or VS Code AI tools.

---

## Start of Coding Session

```text
Context reset.

Read docs/AI_README/AI_CONTEXT.md first and treat it as authoritative.

Do not read the whole repo by default.
Do not edit anything yet.

Task:
[describe task here]

First, list the smallest set of files you need to inspect and explain why.
```

---

## Bug Report Prompt

```text
Context reset.

Read docs/AI_README/AI_CONTEXT.md and docs/AI_README/DEBUGGING_RULES.md first.

Issue:
[describe exact symptom]

Known facts:
- [fact 1]
- [fact 2]
- [fact 3]

Recent changes:
- [change 1]
- [change 2]

Goal:
Find the smallest safe fix.

Rules:
- Do not refactor.
- Do not scan unrelated panels.
- Check mechanical path/string/cache issues first.
- Do not edit anything until you report the likely failure point.

First step:
List the files you believe are relevant and why.
```

---

## NET Panel Bug Prompt

```text
Context reset.

Read:
1. docs/AI_README/AI_CONTEXT.md
2. docs/AI_README/DEBUGGING_RULES.md
3. docs/AI_README/TROUBLESHOOTING_MAP.md

Issue:
In the NET panel, the ping and VLAN meters are stuck.

Goal:
Trace each meter from display back to data source and find the smallest safe fix.

Scope:
Only inspect files related to:
- NET panel drawing
- Conky config that calls the NET panel
- ping data collection
- VLAN/interface data collection
- cache/state files used by the NET panel
- startup scripts that launch NET data collectors

Do not inspect unrelated panels unless a NET file directly references them.

First:
List the relevant files and explain why.

Second:
Trace ping and VLAN separately using this format:

Meter:
Display function:
Displayed variable:
Cache file or command read:
Script or command that updates it:
Expected update interval:
Manual test command:
Most likely failure point:
Smallest safe fix:

Do not edit anything until the trace is complete.
```

---

## Smallest Safe Fix Prompt

```text
Apply only the smallest safe fix for the most likely failure point.

Rules:
- Do not refactor.
- Do not rename files.
- Do not change unrelated behavior.
- Do not modify legacy suites.
- Preserve the current palette system.
- Show the exact diff or changed lines.
- Include a manual test command.
```

---

## Mechanical Triage Prompt

```text
Before scanning broadly, do a mechanical triage.

Check for:
- malformed paths
- extra slashes
- missing slashes
- bad globs
- bad quoting
- recursive loops
- symlink loops
- scripts reading their own output
- stale cache reuse
- wrong working directory
- missing executable bit
- unset variables
- recent diffs

Inspect the smallest likely file set first.
Do not edit anything yet.
```

---

## Context Reset Prompt

```text
Context reset. Ignore earlier assumptions.

Work only from the facts below.

Project:
gtex62-osa Conky suite on Titan / Linux Mint.

Goal:
[one specific goal]

Known facts:
- [fact 1]
- [fact 2]
- [fact 3]

Do not:
- rewrite unrelated files
- change legacy suites
- assume paths not shown here
- refactor while debugging

Relevant code:
[paste code here]

Give me the smallest safe next step.
```

---

## Documentation Update Prompt

```text
Update documentation for this change.

Read docs/AI_README/AI_CONTEXT.md first.

Change made:
[describe change]

Files changed:
[list files]

Update only the relevant docs.

Required documentation:
- what changed
- why it changed
- where the script/file lives
- how to test it
- how to undo or disable it if needed

Do not rewrite unrelated documentation.
```

---

## Code Review Prompt

```text
Review this change for safety.

Focus on:
- path correctness
- cache/state handling
- loops
- startup behavior
- accidental changes to unrelated panels
- legacy suite impact
- documentation needed

Do not rewrite the code unless there is a clear bug.

Report:
1. safe as-is / not safe
2. risks
3. smallest recommended change
4. test command
```
