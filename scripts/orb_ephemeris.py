#!/usr/bin/env python3
import math
import os
import time
from datetime import timezone

import ephem

HOME = os.path.expanduser("~")
SUITE_DIR = os.environ.get("CONKY_SUITE_DIR") or os.path.join(HOME, ".config", "conky", "gtex62-osa")
CACHE_DIR = os.environ.get("CONKY_CACHE_DIR") or os.path.join(os.environ.get("XDG_CACHE_HOME", os.path.join(HOME, ".cache")), "conky")
SKY_VARS = os.path.join(CACHE_DIR, "sky.vars")
OWM_VARS = os.path.join(SUITE_DIR, "legacy", "config", "owm.vars")


def parse_vars(path):
    out = {}
    if not os.path.exists(path):
        return out
    try:
        with open(path, "r", encoding="utf-8") as handle:
            for raw in handle:
                line = raw.split("#", 1)[0].strip()
                if not line or "=" not in line:
                    continue
                key, value = [part.strip() for part in line.split("=", 1)]
                out[key] = value
    except OSError:
        return out
    return out


def pick_lat_lon():
    sky = parse_vars(SKY_VARS)
    if "LAT" in sky and "LON" in sky:
        return float(sky["LAT"]), float(sky["LON"])

    owm = parse_vars(OWM_VARS)
    if "LAT" in owm and "LON" in owm:
        return float(owm["LAT"]), float(owm["LON"])

    lat = os.environ.get("LAT")
    lon = os.environ.get("LON")
    if lat and lon:
        return float(lat), float(lon)

    return None, None


def deg(value):
    return float(value) * 180.0 / math.pi


def az_to_theta(az_deg):
    theta = az_deg - 90.0
    while theta < 0:
        theta += 360.0
    while theta >= 360.0:
        theta -= 360.0
    return theta


def ts(ephem_date):
    return int(ephem_date.datetime().replace(tzinfo=timezone.utc).timestamp())


def safe_event(fn, body):
    try:
        return fn(body)
    except (ephem.AlwaysUpError, ephem.NeverUpError):
        return None


def pick_interval(observer, body, now_ts):
    prev_rise = safe_event(observer.previous_rising, body)
    prev_set = safe_event(observer.previous_setting, body)
    next_rise = safe_event(observer.next_rising, body)
    next_set = safe_event(observer.next_setting, body)

    pr_ts = ts(prev_rise) if prev_rise else None
    ps_ts = ts(prev_set) if prev_set else None
    nr_ts = ts(next_rise) if next_rise else None
    ns_ts = ts(next_set) if next_set else None

    def span_ok(rise_ts, set_ts, max_hours=24):
      return (
          rise_ts is not None
          and set_ts is not None
          and 0 < (set_ts - rise_ts) <= max_hours * 3600
      )

    rise_ts = None
    set_ts = None

    if pr_ts and ns_ts and pr_ts <= now_ts <= ns_ts and span_ok(pr_ts, ns_ts):
        rise_ts, set_ts = pr_ts, ns_ts

    if rise_ts is None and nr_ts and ns_ts and nr_ts < ns_ts and span_ok(nr_ts, ns_ts):
        rise_ts, set_ts = nr_ts, ns_ts

    if rise_ts is None and pr_ts and ps_ts and pr_ts < ps_ts and pr_ts <= now_ts <= ps_ts and span_ok(pr_ts, ps_ts):
        rise_ts, set_ts = pr_ts, ps_ts

    return {
        "rise_ts": rise_ts,
        "set_ts": set_ts,
        "set_prev_ts": ps_ts,
    }


def main():
    lat, lon = pick_lat_lon()
    if lat is None or lon is None:
        return 1

    observer = ephem.Observer()
    observer.lat = str(lat)
    observer.lon = str(lon)
    observer.elevation = 0
    observer.date = ephem.now()
    now_ts = int(time.time())

    bodies = {
        "SUN": ephem.Sun(),
        "MOON": ephem.Moon(),
        "MERCURY": ephem.Mercury(),
        "VENUS": ephem.Venus(),
        "MARS": ephem.Mars(),
        "JUPITER": ephem.Jupiter(),
        "SATURN": ephem.Saturn(),
    }

    lines = [
        f"LAT={lat}",
        f"LON={lon}",
        f"TS={now_ts}",
    ]

    for name, body in bodies.items():
        body.compute(observer)
        az = deg(body.az)
        alt = deg(body.alt)
        theta = az_to_theta(az)
        lines.append(f"{name}_AZ={az:.3f}")
        lines.append(f"{name}_ALT={alt:.3f}")
        lines.append(f"{name}_THETA={theta:.3f}")

        interval = pick_interval(observer, body, now_ts)
        prev_rise = safe_event(observer.previous_rising, body)
        prev_set = safe_event(observer.previous_setting, body)
        next_rise = safe_event(observer.next_rising, body)
        next_set = safe_event(observer.next_setting, body)
        if interval["rise_ts"] is not None and interval["set_ts"] is not None:
            lines.append(f"{name}_RISE_TS={interval['rise_ts']}")
            lines.append(f"{name}_SET_TS={interval['set_ts']}")
        if interval["set_prev_ts"] is not None:
            lines.append(f"{name}_SET_PREV_TS={interval['set_prev_ts']}")
        if prev_rise is not None:
            lines.append(f"{name}_PREV_RISE_TS={ts(prev_rise)}")
        if prev_set is not None:
            lines.append(f"{name}_PREV_SET_TS={ts(prev_set)}")
        if next_rise is not None:
            lines.append(f"{name}_NEXT_RISE_TS={ts(next_rise)}")
        if next_set is not None:
            lines.append(f"{name}_NEXT_SET_TS={ts(next_set)}")

    print("\n".join(lines))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
