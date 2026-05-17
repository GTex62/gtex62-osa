# AI Context for gtex62-osa

This file is the first file an AI coding assistant should read before working on this project.

Its purpose is to provide the smallest useful context packet: project identity, current rules, and where to look next.

---

## Active Project

- Active suite: `gtex62-osa`
- Primary host: `Titan`
- Operating system: Linux Mint
- Main suite path: `~/.config/conky/gtex62-osa/`
- Primary development style: one issue at a time, smallest safe change first

---

## Current Architecture

- `gtex62-osa` is the active suite using the newer shared-engine approach.
- **Two separate git repos**: `gtex62-osa` (suite) and `gtex62-core` (engine/providers). Both require separate commit and push cycles.
- Legacy Conky suites should remain in their existing structures.
- Do not migrate older suites unless explicitly requested.
- Shared/core/engine code should remain separate from suite-specific code.
- Suite-specific behavior belongs in `~/.config/conky/gtex62-osa/`.
- Engine/provider behavior belongs in `~/.config/conky/gtex62-core/`.

### Bootstrap Profile Gap

When a new provider is added to `gtex62-core`, its runtime profile TOML must be installed before the suite can use it. The bootstrap script installs all `.example` files from `gtex62-core/examples/runtime/`:

```bash
bash ~/.config/conky/gtex62-core/bin/gtex62-core-bootstrap-runtime
```

If a profile TOML is missing, the launcher falls back to a 60-second TTL, making fast-track meters (VLAN, ping) appear frozen. **Always check whether the profile TOML exists before debugging a frozen meter.**

```bash
ls ~/.config/gtex62-core/profiles/net/
ls ~/.config/gtex62-core/profiles/orb/
ls ~/.config/gtex62-core/profiles/time/
```

### `monitor_head` Is Always Locally Modified

`theme/osa-theme.lua` will almost always show `M` in `git status` because `monitor_head` is changed locally after every push. This is expected — do not flag it as a problem, do not commit it to a specific value, and do not revert it.

### Two-Repo Rule

When a bug or change involves both repos, always check which repo owns the relevant file before editing. Root causes are often in `gtex62-core` even when the symptom appears in the OSA display. Examples:

| Symptom | Root cause repo |
|---|---|
| Clock timezone name wrong in display | `gtex62-core/providers/time/fetch_time.sh` |
| VLAN/ping meters frozen | `gtex62-core/providers/net/fetch_net.sh` or profile TOML |
| Orb/planet data missing | `gtex62-core/providers/orb/fetch_orb.py` |
| Weather data stale | `gtex62-core/providers/weather/` |

---

## Editing Rules

When making changes:

- Work on one issue at a time.
- Prefer the smallest safe change.
- Do not refactor while debugging unless explicitly requested.
- Do not rewrite unrelated files.
- Do not rename files, directories, public-facing repo names, or install paths unless explicitly requested.
- Preserve the current palette system unless explicitly told otherwise.
- Preserve existing user paths unless a path is proven wrong.
- Report the suspected cause before applying edits.
- Show diffs or exact changes before finalizing when possible.

---

## Context Rules for AI Assistants

Do not read the entire repo by default.

Start with:

1. This file: `docs/AI_CONTEXT.md`
2. The specific file or files involved in the task
3. One additional doc only if directly relevant

Use this rule:

| Task Type | Read |
|---|---|
| General coding task | `AI_CONTEXT.md` + relevant source file |
| NET panel issue | `AI_CONTEXT.md` + `TROUBLESHOOTING_MAP.md` + `lua/suite/net.lua` + `gtex62-core/providers/net/fetch_net.sh` |
| WXR/weather issue | `AI_CONTEXT.md` + `TROUBLESHOOTING_MAP.md` + `lua/suite/wxr.lua` |
| TME/clock issue | `AI_CONTEXT.md` + `lua/suite/tme.lua` + `gtex62-core/providers/time/fetch_time.sh` |
| ENV/atmos issue | `AI_CONTEXT.md` + `lua/suite/env.lua` + `lua/ui/frame.lua` (atmos section) |
| Orb/celestial issue | `AI_CONTEXT.md` + `lua/suite/orb.lua` + `gtex62-core/providers/orb/fetch_orb.py` |
| Theme/geometry issue | `AI_CONTEXT.md` + `theme/osa-theme.lua` + relevant `lua/ui/frame.lua` section |
| Startup issue | `AI_CONTEXT.md` + `scripts/start-conky.sh` + `gtex62-core/bin/gtex62-core-launch` |
| Palette issue | `AI_CONTEXT.md` + `theme/osa-palettes.lua` |
| Architecture issue | `AI_CONTEXT.md` + `gtex62-core/docs/architecture.md` |

Do not scan unrelated panels unless a relevant file directly references them.

---

## Important Project Rules

- Legacy suites stay untouched unless explicitly requested.
- New architecture work should be proven first with `gtex62-osa`.
- Avoid broad rewrites.
- Avoid speculative fixes.
- When stuck, reduce scope instead of expanding scope.
- If the answer starts becoming generic, reset context and restate the exact issue.

---

## Common Project Areas

| Area | Exact Path |
|---|---|
| Suite root | `~/.config/conky/gtex62-osa/` |
| Core/engine root | `~/.config/conky/gtex62-core/` |
| Lua drawing code | `~/.config/conky/gtex62-osa/lua/ui/frame.lua` |
| Lua data modules | `~/.config/conky/gtex62-osa/lua/suite/` (net.lua, wxr.lua, tme.lua, env.lua, orb.lua, …) |
| Theme / geometry | `~/.config/conky/gtex62-osa/theme/osa-theme.lua` |
| Palettes | `~/.config/conky/gtex62-osa/theme/osa-palettes.lua` |
| Suite startup | `~/.config/conky/gtex62-osa/scripts/start-conky.sh` |
| Core providers | `~/.config/conky/gtex62-core/providers/<domain>/` |
| Core launcher | `~/.config/conky/gtex62-core/bin/gtex62-core-launch` |
| Shared cache | `~/.cache/gtex62-core/shared/<domain>/<profile>/` |
| Runtime profiles | `~/.config/gtex62-core/profiles/<domain>/<profile>.toml` |
| Suite TOML | `~/.config/gtex62-core/suites/osa.toml` |
| Documentation | `~/.config/conky/gtex62-osa/docs/` |
| Runbooks | `/mnt/NAS_Data/Data/Linux/backups/_docs/` |

---

## Required Behavior for New Scripts

Any new script should have documentation describing:

- Full path
- Purpose
- Inputs
- Outputs
- Cache/state files used
- How it is launched
- How to test it manually
- How to disable or remove it safely

Runbooks are kept at:

```text
/mnt/NAS_Data/Data/Linux/backups/_docs/
```

---

## Current Task Instructions

For each task, the user should provide:

- Exact symptom
- Relevant file path if known
- What changed recently
- Expected behavior
- What should not be changed

If that information is missing, inspect only the smallest likely file set and report assumptions before editing.
