# OSA ORB Panel — Cache Notes

The `ORB` panel reads from the shared core `orb` provider cache.

For the full cache schema, file formats, key reference, location resolution,
and refresh model see:

- `gtex62-core/docs/orb-provider.md`

## OSA-Specific Notes

OSA derives the following from `ephemeris.vars` in `lua/suite/orb.lua`:

- CELESTIAL row `body` label and `data` text
- Visible time-band start/end hours (for the timeline arc)
- Above-horizon flag (`visible_now`)
- Current time marker position
- Rise/set display times for SUN and MOON rows

The THETA projection angle (`azimuth − 90°`, wrapped 0–360) is used to place
bodies on the orb ring. Rise/set window selection handles overnight intervals
(body rises before midnight, sets during the current day) and evening intervals
(body rises today, sets tomorrow).

The orb profile is bound in the suite TOML under `[profiles] orb` (default `"home"`).
OSA resolves the cache path in `lua/suite/orb.lua` via `orb_cache_dir()`.
