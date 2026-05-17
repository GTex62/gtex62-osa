# Debugging Rules for gtex62-osa

Use this file to keep AI debugging narrow, mechanical, and safe.

---

## Prime Directive

Find the smallest bug first.

Do not turn a bug hunt into an architecture rewrite.

---

## Debugging Order

Use this order unless the user gives a more specific instruction:

1. Restate the exact symptom.
2. Identify the smallest likely subsystem.
3. Check recent changes/diffs first.
4. Check mechanical failures.
5. Trace the data path.
6. Identify the most likely failure point.
7. Propose the smallest safe fix.
8. Apply only that fix.
9. Test or provide a manual test command.
10. Stop.

---

## Mechanical Checks First

Before broad scanning, check for:

- Extra `/`
- Missing `/`
- Wrong path join
- Wrong quote escaping
- Wrong glob pattern
- Recursive copy loop
- Symlink loop
- Script reading its own output
- Script writing into a directory it later scans
- Missing executable bit
- Wrong working directory
- Relative path used where absolute path is required
- Bad environment variable
- Unset variable
- Wrong interface name
- Wrong cache path
- Stale cache file
- Bad loop exit condition
- Fallback value reused forever
- Recent rename not updated everywhere

---

## AI Assistant Behavior

The AI assistant should:

- Ask for or inspect only relevant files.
- Explain why each inspected file matters.
- Avoid broad scans.
- Avoid unrelated cleanup.
- Avoid opportunistic refactoring.
- Preserve current project structure.
- Treat `docs/AI_CONTEXT.md` as authoritative.
- Treat this file as authoritative for debugging behavior.
- Stop after the smallest safe fix unless asked to continue.

---

## Do Not Do This

Avoid this pattern:

```text
symptom
→ scan entire repo
→ infer architecture
→ rewrite several files
→ introduce new behavior
→ create new bugs
```

Use this pattern instead:

```text
symptom
→ recent diff
→ exact data path
→ mechanical checks
→ smallest fix
→ test
```

---

## Context Reset Rule

If the AI assistant becomes generic, contradictory, or detached from the actual project, reset context.

Use:

```text
Context reset. Work only from the facts below.
```

Then provide:

- Project name
- Exact issue
- Known facts
- Relevant files
- What not to change
- Desired next step

---

## Scope Control Phrases

Useful instructions for the user to give the AI assistant:

```text
Do not edit anything yet. First list the files you believe are relevant and why.
```

```text
Trace this issue from display back to data source.
```

```text
Check recent changes and mechanical path/string errors before scanning broadly.
```

```text
Apply only the smallest safe fix. Do not refactor.
```

```text
Show the diff before finalizing.
```

```text
Stop after this fix.
```

---

## When to Expand Scope

Only expand beyond the first subsystem when:

- The relevant file directly calls another subsystem.
- The data path crosses into another subsystem.
- The cache/update chain proves the bug is upstream.
- The first hypothesis fails a concrete test.
- The user explicitly asks for broader analysis.

Do not expand scope just because more files exist.

---

## Testing Rule

Every fix should include one of:

- A command to test manually
- A file/cache timestamp to check
- A Conky reload/restart step
- A visual confirmation step
- A before/after expected output

Example:

```bash
stat ~/.cache/gtex62-osa/net_ping.json
```

Example:

```bash
bash -x ~/.config/conky/gtex62-osa/scripts/update-net.sh
```

Example:

```bash
conky -c ~/.config/conky/gtex62-osa/conky.conf
```

Adjust paths to match the actual suite.
