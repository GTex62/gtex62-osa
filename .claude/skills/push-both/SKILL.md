---
name: push-both
description: Commit and push changes in both gtex62-osa and gtex62-core
allowed-tools: Bash
---

## Current status — gtex62-osa

!`git -C ~/.config/conky/gtex62-osa status`

## Current diff — gtex62-osa

!`git -C ~/.config/conky/gtex62-osa diff --stat`

## Current status — gtex62-core

!`git -C ~/.config/conky/gtex62-core status`

## Current diff — gtex62-core

!`git -C ~/.config/conky/gtex62-core diff --stat`

## Instructions

Commit and push meaningful changes in both repos. Follow these rules:

- **Do not commit** changes to `theme/osa-theme.lua` that are only a `monitor_head`
  value change — this is a local-only setting changed after every push and should
  never be committed on its own. If other changes exist in that file, commit those
  but note the monitor_head line was excluded.
- Stage only the files with real changes. Do not use `git add -A` or `git add .`.
- Write a concise commit message describing what changed and why.
- Commit and push each repo separately.
- If a repo has no meaningful changes, skip it and say so.
- After pushing, confirm both repos are clean.
