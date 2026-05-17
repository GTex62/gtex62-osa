# Troubleshooting Map for gtex62-osa

This file maps symptoms to the smallest useful set of files and checks.

Use this before scanning broadly.

---

## General Debugging Chain

Most display bugs follow this chain:

```text
data source
→ collection script or command
→ cache/state file
→ parser/helper function
→ Lua/Conky draw function
→ displayed panel
```

Start at the symptom, then trace backward.

Do not scan unrelated panels unless the relevant file directly imports or calls them.

---

## First Response Pattern for AI Assistants

When given a bug report, first respond with:

1. The likely subsystem
2. The smallest file set to inspect
3. Why each file matters
4. The first mechanical checks to perform
5. No edits yet

Example:

```text
Issue: NET panel ping and VLAN meters are stuck.

I will inspect only the NET display path, NET data collection scripts, NET cache files, and startup/update scripts that launch them. I will not inspect unrelated panels unless these files reference them.
```

---

## NET Panel

### Data Path

```text
gtex62-core/providers/net/fetch_net.sh (profile: local)
  → ~/.cache/gtex62-core/shared/net/local/state.vars   (ping, WAN IP, status)
  → ~/.cache/gtex62-core/shared/net/local/vlan.tsv     (VLAN latency rows)
    → lua/suite/net.lua                                 (reads cache)
      → lua/ui/frame.lua                               (draws NET panel)
```

TTL: 1 second (VLAN/ping are fast-track meters). WAN IP is rate-limited to 30s internally.

### Symptoms

- Ping meter stuck
- VLAN meter stuck or frozen at last value
- Network values not updating
- Meters move once then stop
- Panel shows stale values

### Likely File Categories

| Layer | Exact Path |
|---|---|
| Display | `lua/ui/frame.lua` (NET panel section) |
| Data module | `lua/suite/net.lua` |
| Provider | `gtex62-core/providers/net/fetch_net.sh` |
| Cache — state | `~/.cache/gtex62-core/shared/net/local/state.vars` |
| Cache — VLAN | `~/.cache/gtex62-core/shared/net/local/vlan.tsv` |
| Profile TOML | `~/.config/gtex62-core/profiles/net/local.toml` |
| Launcher | `gtex62-core/bin/gtex62-core-launch` |

### First Mechanical Checks

- Is `state.vars` timestamp changing? (`stat ~/.cache/gtex62-core/shared/net/local/state.vars`)
- Is the profile TOML installed? (`cat ~/.config/gtex62-core/profiles/net/local.toml`) — missing TOML causes 60s TTL fallback, making meters appear frozen
- Does the script run manually? (`bash gtex62-core/providers/net/fetch_net.sh local`)
- Is the interface name in `state.vars` correct? (`grep IFACE ~/.cache/gtex62-core/shared/net/local/state.vars`)
- Is the launcher loop running? (`pgrep -a gtex62-core-launch`)

### Trace Template

For each stuck NET meter, report:

```text
Meter:
Display function:
Displayed variable:
Cache file or command read:
Script or command that updates it:
Expected update interval:
Manual test command:
Observed failure point:
Smallest safe fix:
```

---

## Startup Problems

### Symptoms

- Suite works in terminal but not from Linux Mint Startup Applications
- Startup launches wrong suite
- Terminal does not open
- Script waits for input
- Conky never appears after login
- Palette/menu script stalls

### Likely File Categories

| Layer | What to Inspect |
|---|---|
| Startup entry | Linux Mint Startup Applications command |
| Startup script | Main suite launch script |
| Interactive menus | Palette/wallpaper/menu scripts |
| Environment | Env vars and paths |
| Conky launch | Final `conky` commands |
| Logs | Startup logs if configured |

### First Mechanical Checks

- Does the startup command use an absolute path?
- Is the script executable?
- Does the script require terminal input?
- Does the script launch an interactive menu?
- Does the startup path differ from the terminal path?
- Is there a delay/race condition?
- Are logs being written?
- Does the script exit early?

---

## Palette Problems

### Symptoms

- Wrong palette loads
- Palette menu works in terminal but not startup
- Colors do not match expected LCD/OSA style
- Conky loads but with default colors
- Palette changes do not persist

### Likely File Categories

| Layer | What to Inspect |
|---|---|
| Palette definitions | Palette file/module |
| Palette selector | Menu or selection script |
| State/cache | File storing selected palette |
| Loader | Lua/config code loading palette |
| Startup | Startup path that chooses or restores palette |

### First Mechanical Checks

- Is the selected palette written to state/cache?
- Is the state/cache path correct?
- Is startup bypassing the selector?
- Is the palette name misspelled?
- Are palette keys consistent?
- Are RGB values in the expected format/range?
- Is the wrong config file being loaded?

---

## Weather / Environment Panel

### Symptoms

- Weather data stale
- Pollution/pollen/solar values stuck
- Moon/weather section not updating
- API data absent or old

### Likely File Categories

| Layer | What to Inspect |
|---|---|
| API/env | Env file containing API key/config |
| Fetch script | Weather/pollution/pollen data script |
| Cache | JSON/text cache files |
| Parser | Lua/helper code reading cache |
| Display | Panel drawing file |
| Scheduler | Startup loop/timer/cron/systemd if used |

### First Mechanical Checks

- Is the fetch script running?
- Is the cache timestamp current?
- Is the API key loaded?
- Is the endpoint reachable?
- Did the API response format change?
- Is the parser failing and reusing stale values?
- Are cache paths malformed?

---

## Storage Panel

### Symptoms

- Storage values wrong
- Used/free space reversed
- Mount missing
- NAS values stale
- Table alignment broken

### Likely File Categories

| Layer | What to Inspect |
|---|---|
| Display | Storage table drawing file |
| Data source | `df`, Home Assistant sensor, NAS script, or cache |
| Config | Mount path definitions |
| Cache | Storage cache/state file |
| Formatting | Alignment/font/table function |

### First Mechanical Checks

- Is the mount available?
- Does `df` show expected values?
- Is the parser using the correct column?
- Did a label change break matching?
- Did font size/monospace assumptions change?
- Is alignment math hardcoded?

---

## WXR / Weather Panel

### Data Path

```text
gtex62-core/providers/weather/fetch_weather.sh (profile: home)
  → ~/.cache/gtex62-core/shared/weather/home/current.json
  → ~/.cache/gtex62-core/shared/weather/home/status.json
    → lua/suite/wxr.lua                   (reads cache, computes STALE/NOMINAL)
      → lua/ui/frame.lua                  (draws WXR panel)
```

Weather TTL: 300s. Session-start STALE threshold: 450s (data must be older than 450s AND predate the current session before STALE fires).

### Symptoms

- WXR DATA shows STALE unexpectedly
- Weather values not updating
- Moon/sun data absent
- Forecast missing

### Likely File Categories

| Layer | Exact Path |
|---|---|
| Data module | `lua/suite/wxr.lua` |
| Provider | `gtex62-core/providers/weather/fetch_weather.sh` |
| Cache | `~/.cache/gtex62-core/shared/weather/home/current.json` |
| Status | `~/.cache/gtex62-core/shared/weather/home/status.json` |
| Profile TOML | `~/.config/gtex62-core/profiles/weather/home.toml` |

### First Mechanical Checks

- How old is the cache? (`stat ~/.cache/gtex62-core/shared/weather/home/current.json`)
- Is the weather provider loop running? (`pgrep -a gtex62-core-launch`)
- Is the API key set? (`grep -i api ~/.config/gtex62-core/profiles/weather/home.toml`)
- STALE on every restart: data was likely fetched before session start AND is older than 450s — wait for next provider cycle or restart provider
- STALE persisting: provider loop may not be running or API is failing

---

## Orb / Celestial Panel

### Data Path

```text
gtex62-core/providers/orb/fetch_orb.py (profile: home)
  → ~/.cache/gtex62-core/shared/orb/home/ephemeris.vars
    → lua/suite/orb.lua                   (reads cache)
      → lua/ui/frame.lua                  (draws ORB panel)
```

Orb TTL: 60s. Location resolved from: env LAT/LON → astro cache → astro profile TOML → weather home TOML.

### Symptoms

- Planet/sun/moon positions frozen
- Rise/set times wrong or absent
- Orb panel blank

### Likely File Categories

| Layer | Exact Path |
|---|---|
| Data module | `lua/suite/orb.lua` |
| Provider | `gtex62-core/providers/orb/fetch_orb.py` |
| Shell wrapper | `gtex62-core/providers/orb/fetch_orb.sh` |
| Cache | `~/.cache/gtex62-core/shared/orb/home/ephemeris.vars` |
| Profile TOML | `~/.config/gtex62-core/profiles/orb/home.toml` |
| Astro profile | `~/.config/gtex62-core/profiles/astro/home.toml` |

### First Mechanical Checks

- Is the cache updating? (`stat ~/.cache/gtex62-core/shared/orb/home/ephemeris.vars`)
- Does the script run manually? (`python3 gtex62-core/providers/orb/fetch_orb.py home`)
- Is `pyephem` installed? (`python3 -c "import ephem; print(ephem.__version__)"`)
- Is lat/lon available? Check astro profile → weather home TOML cascade

---

## File Scan Limits

The AI assistant should not scan the whole repo until these fail:

1. Recent diff check
2. Mechanical path/string check
3. Relevant subsystem file check
4. Cache/state freshness check
5. Manual command reproduction

Only then expand scope.
