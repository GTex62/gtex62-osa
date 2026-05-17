---
description: Run a gtex62-core provider manually to force-refresh the cache. Usage: /provider-run <domain>  Domains: net, time, orb, weather
arguments: [domain]
allowed-tools: Bash
---

## Task

Run the `$domain` provider manually to force-refresh the cache, then verify the cache updated.

Provider commands by domain:

| Domain  | Command |
|---------|---------|
| net     | `bash ~/.config/conky/gtex62-core/providers/net/fetch_net.sh local` |
| time    | `bash ~/.config/conky/gtex62-core/providers/time/fetch_time.sh local` |
| orb     | `bash ~/.config/conky/gtex62-core/providers/orb/fetch_orb.sh home` |
| weather | `bash ~/.config/conky/gtex62-core/providers/weather/fetch_weather.sh home` |

## Instructions

1. Run the provider command for `$domain`.
2. Check that the cache file timestamp updated (`stat` the relevant file).
3. Show a brief sample of the new cache content.
4. Report success or any errors from the provider output.

If `$domain` is not in the table above, check what providers exist under
`~/.config/conky/gtex62-core/providers/` and suggest the correct one.
