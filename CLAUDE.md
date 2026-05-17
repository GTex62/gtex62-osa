# gtex62-osa — Project Instructions

## Two Repos — Always Separate

This project spans two git repos. Identify which owns each file before editing.
Commit and push each repo independently.

- Suite: `~/.config/conky/gtex62-osa/`
- Engine: `~/.config/conky/gtex62-core/`

## Hard Rules

- `theme/osa-theme.lua` is almost always M in git status — `monitor_head` is
  changed locally after every push. Never commit a monitor_head-only change.
- Do not refactor while fixing a bug. Smallest safe change only.
- Do not rename files, dirs, or public paths unless explicitly requested.
- Commit messages: no Co-Authored-By or AI attribution lines.

## Bootstrap Gap

When a new provider is added to core, its profile TOML must be installed:

```bash
bash ~/.config/conky/gtex62-core/bin/gtex62-core-bootstrap-runtime
```

Missing profile TOML → 60s TTL fallback → meters appear frozen.

## Full Project Docs

- `docs/AI_README/AI_CONTEXT.md` — architecture, exact file paths, task rules
- `docs/AI_README/TROUBLESHOOTING_MAP.md` — panel-by-panel debug guides
- `docs/AI_README/DEBUGGING_RULES.md` — debugging order and scope rules
