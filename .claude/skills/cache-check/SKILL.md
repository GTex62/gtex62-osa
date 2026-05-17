---
description: Check the age and content of a gtex62-core shared cache. Usage: /cache-check <domain>  Domains: net, time, orb, weather
arguments: [domain]
allowed-tools: Bash
---

## Cache files for domain: $domain

!`CACHE="$HOME/.cache/gtex62-core/shared/$domain"; if [ -d "$CACHE" ]; then for f in "$CACHE"/*; do [ -f "$f" ] && printf "%s  age=%ss\n" "$(basename "$f")" "$(( $(date +%s) - $(stat -c '%Y' "$f") ))"; done; else echo "Cache directory not found: $CACHE"; fi`

## Cache content

!`CACHE="$HOME/.cache/gtex62-core/shared/$domain"; cat "$CACHE/state.vars" 2>/dev/null || (cat "$CACHE/current.json" 2>/dev/null | python3 -m json.tool 2>/dev/null | head -50) || cat "$CACHE/ephemeris.vars" 2>/dev/null || cat "$CACHE/vlan.tsv" 2>/dev/null || echo "No recognisable cache file found."`

## Instructions

Report concisely:
1. Is the cache present and fresh (age within expected TTL)?
2. Key values from the content
3. Any obvious problems (missing file, stale timestamp, empty content)

Expected TTLs by domain:
- net: 1s (VLAN/ping fast-track)
- time: 1s
- orb: 60s
- weather: 300s

If the domain is not one of the above, check what files exist and report them.
