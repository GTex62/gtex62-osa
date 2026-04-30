# Core V1 ORB Cache For OSA

## Purpose

This note documents the current suite-local `ORB` cache contract used by `gtex62-osa`.

This is not the same thing as the shared core `astro` schema.

The shared core `astro` domain remains normalized truth.
This cache is an OSA-specific derived ephemeris projection used to keep `ORB` rendering off the draw path.

---

## Core Position

`ORB` is currently split into:

- shared/background inputs:
  - normalized core astro/profile location data
  - core- or suite-generated astronomical source data
- suite cache lane:
  - `ephemeris.vars`
- render lane:
  - OSA CELESTIAL row derivation in Lua

The suite cache is refreshed by:

- [scripts/refresh_orb_cache.sh](/home/gtex62/.config/conky/gtex62-osa/scripts/refresh_orb_cache.sh)

That script writes the output of:

- [scripts/orb_ephemeris.py](/home/gtex62/.config/conky/gtex62-osa/scripts/orb_ephemeris.py)

into the suite cache.

---

## Cache Location

For OSA:

- `~/.cache/gtex62-core/suites/osa/orb/ephemeris.vars`

Generalized shape:

- `~/.cache/gtex62-core/suites/<suite_id>/orb/ephemeris.vars`

---

## `ephemeris.vars`

## Format

Simple key/value text.

Example:

```text
LAT=35.033333
LON=-89.983333
TS=1776841117
SUN_AZ=19.521
SUN_ALT=-40.639
SUN_THETA=289.521
SUN_RISE_TS=1776856729
SUN_SET_TS=1776904709
...
JUPITER_AZ=303.238
JUPITER_ALT=-5.983
JUPITER_THETA=213.238
JUPITER_NEXT_RISE_TS=1776873803
JUPITER_NEXT_SET_TS=1776925412
```

## Top-Level Keys

Required:

- `LAT`
- `LON`
- `TS`

These describe:

- observer latitude
- observer longitude
- cache generation timestamp

## Body Keys

Current bodies:

- `SUN`
- `MOON`
- `MERCURY`
- `VENUS`
- `MARS`
- `JUPITER`
- `SATURN`

For each body, the cache may contain:

- `<BODY>_AZ`
- `<BODY>_ALT`
- `<BODY>_THETA`
- `<BODY>_RISE_TS`
- `<BODY>_SET_TS`
- `<BODY>_SET_PREV_TS`
- `<BODY>_PREV_RISE_TS`
- `<BODY>_PREV_SET_TS`
- `<BODY>_NEXT_RISE_TS`
- `<BODY>_NEXT_SET_TS`

## Meanings

- `_AZ`
  - azimuth in degrees
- `_ALT`
  - altitude in degrees
- `_THETA`
  - legacy/OSA projection angle used by current CELESTIAL logic
- `_RISE_TS`
  - current selected rise time for display
- `_SET_TS`
  - current selected set time for display
- `_SET_PREV_TS`
  - carryover helper for wrapped overnight intervals
- `_PREV_RISE_TS`
- `_PREV_SET_TS`
- `_NEXT_RISE_TS`
- `_NEXT_SET_TS`
  - neighboring event timestamps used by OSA’s day-window selection logic

---

## OSA Consumption Model

[lua/suite/orb.lua](/home/gtex62/.config/conky/gtex62-osa/lua/suite/orb.lua) currently uses:

- `ephemeris.vars`
  - as the cached suite-local ephemeris source

OSA then derives:

- CELESTIAL row `body`
- CELESTIAL row `data`
- visible time-band start/end
- current visibility flag
- current marker position

The cache does not contain ready-to-render rows.
It contains suite-oriented source values that OSA transforms into the CELESTIAL table.

---

## Why This Is Suite-Local

This cache should remain suite-local because it includes:

- OSA-shaped `THETA` projection support
- OSA-specific rise/set window handling
- derived values chosen for the CELESTIAL panel rather than for all suites

The shared core `astro` schema should still own normalized truth such as:

- altitude
- azimuth
- above-horizon state
- rise/set timing

`ephemeris.vars` is a suite projection cache, not the core's canonical astronomy truth.

---

## Refresh Model

The launcher currently schedules:

- initial background refresh at startup
- recurring background refresh every `GTEX62_OSA_ORB_CACHE_TTL` seconds

Current default:

- `60` seconds

That cadence is appropriate because `ORB` does not need per-second ephemeris recomputation to look correct.
