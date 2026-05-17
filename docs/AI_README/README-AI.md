# gtex62-osa AI Helper Docs

Context and troubleshooting documents for the `gtex62-osa` Conky suite.

Location: `gtex62-osa/docs/AI_README/`

---

## Reading Order

Do not read all files by default. Use this order:

### 1. Always — start here

```text
docs/AI_README/AI_CONTEXT.md
```

Every session reads this first. It covers project identity, the two-repo
split, exact file paths, architecture rules, and known gotchas
(bootstrap gap, monitor_head noise).

### 2. Bug or broken panel — read next

```text
docs/AI_README/DEBUGGING_RULES.md
```

Read this before touching any code. It defines the debugging order:
recent diff → mechanical checks → data path → smallest fix.

### 3. Specific panel issue — read the relevant section only

```text
docs/AI_README/TROUBLESHOOTING_MAP.md
```

Do not read the whole file. Jump to the section matching the symptom:
NET, TME, WXR, Orb, Startup, Palette, or Storage. Each section has
the exact data path, file table, and mechanical checks for that panel.

### 4. Starting a new task — pick a prompt template

```text
docs/AI_README/AI_PROMPTS.md
```

A library of reusable prompt templates. Copy the one that matches the
task type (coding session, bug report, two-repo change, code review,
etc.) and fill in the blanks. Do not read the whole file.

---

## Suggested Session-Start Instruction

```text
Read docs/AI_README/AI_CONTEXT.md first and treat it as authoritative.
Do not read the whole repo by default. Do not edit anything yet.
First list the smallest set of files needed for this task and explain why.
```
