# VS Code Session Opener — gtex62-osa

## Open the right workspace

Open both repos so edits in either are visible:

```bash
code ~/.config/conky/gtex62-osa
code --add ~/.config/conky/gtex62-core   # open in same window or new window
```

## First message to AI

```text
Read docs/AI_README/AI_CONTEXT.md first and treat it as authoritative.
Do not read the whole repo by default. Do not edit anything yet.
First list the smallest set of files needed for this task and explain why.

Task:
[describe what you want to do]
```

## Reminders

- Changes may span both repos — commit and push each separately
- `theme/osa-theme.lua` is almost always M in git status (monitor_head) — that's normal
- If a new provider was added to core, re-run bootstrap before testing:

  ```bash
  bash ~/.config/conky/gtex62-core/bin/gtex62-core-bootstrap-runtime
  ```

- Suite restart picks up Lua changes immediately; provider changes may need
  a launcher restart
