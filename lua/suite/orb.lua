local M = {}

local HOME = os.getenv("HOME") or ""
local SUITE_DIR = os.getenv("CONKY_SUITE_DIR") or (HOME .. "/.config/conky/gtex62-osa")
local ENGINE_CACHE_ROOT = os.getenv("GTEX62_CACHE_DIR") or os.getenv("GTEX62_CONKY_CACHE_DIR") or (HOME .. "/.cache/gtex62-core")
local SUITE_ID = os.getenv("GTEX62_SUITE_ID") or os.getenv("GTEX62_CONKY_SUITE_ID") or "osa"
local SUITE_CACHE_DIR = string.format("%s/suites/%s/orb", ENGINE_CACHE_ROOT, SUITE_ID)

local BODY_ROWS = {
  { body = "SUN", key = "SUN" },
  { body = "LUN", key = "MOON" },
  { body = "MER", key = "MERCURY" },
  { body = "VEN", key = "VENUS" },
  { body = "MAR", key = "MARS" },
  { body = "JUP", key = "JUPITER" },
  { body = "SAT", key = "SATURN" },
}

local DATA_CACHE = {
  eph = { stamp = nil, data = {} },
}
local ORB_CACHE_TTL = tonumber(os.getenv("GTEX62_OSA_ORB_CACHE_TTL")) or 60

local function command_output(cmd)
  local p = io.popen(cmd, "r")
  if not p then return nil end
  local out = p:read("*a") or ""
  p:close()
  out = out:gsub("%s+$", "")
  if out == "" then return nil end
  return out
end

local function read_keyvals(path)
  local out = {}
  local f = io.open(path, "r")
  if not f then
    return out
  end

  for line in f:lines() do
    local key, value = line:match("^%s*([A-Za-z0-9_]+)%s*=%s*(.-)%s*$")
    if key and value then
      local num = tonumber(value)
      out[key] = num or value
    end
  end

  f:close()
  return out
end

local function minute_stamp()
  return math.floor(os.time() / 60)
end

local function ephemeris_data()
  local stamp = minute_stamp()
  if DATA_CACHE.eph.stamp == stamp then
    return DATA_CACHE.eph.data
  end

  DATA_CACHE.eph.data = read_keyvals(SUITE_CACHE_DIR .. "/ephemeris.vars")

  DATA_CACHE.eph.stamp = stamp
  return DATA_CACHE.eph.data
end

local function hour_of_day(ts)
  local numeric = tonumber(ts)
  if not numeric then return nil end
  local parts = os.date("*t", numeric)
  return (parts.hour or 0) + ((parts.min or 0) / 60)
end

local function fmt_hhmm(ts)
  local numeric = tonumber(ts)
  if not numeric then return "--:--" end
  return os.date("%H%M", numeric)
end

local function display_heading(theta)
  local numeric = tonumber(theta)
  if numeric == nil then
    return nil
  end
  return (math.floor(numeric + 0.5) + 90) % 360
end

local function pick_numeric(primary, secondary, key)
  local value = primary[key]
  if value == nil then
    value = secondary[key]
  end
  return tonumber(value)
end

local function current_day_window()
  local now = os.date("*t")
  local start_ts = os.time({
    year = now.year,
    month = now.month,
    day = now.day,
    hour = 0,
    min = 0,
    sec = 0,
  })
  return start_ts, start_ts + 86400
end

local function cache_age_seconds(ts)
  local numeric = tonumber(ts)
  if not numeric then
    return nil
  end
  local age = os.time() - numeric
  if age < 0 then
    age = 0
  end
  return age
end

local function has_body_payload(data)
  if type(data) ~= "table" then
    return false
  end
  return data.SUN_ALT ~= nil
    or data.MOON_ALT ~= nil
    or data.MERCURY_ALT ~= nil
    or data.VENUS_ALT ~= nil
    or data.MARS_ALT ~= nil
    or data.JUPITER_ALT ~= nil
    or data.SATURN_ALT ~= nil
end

local function status_block()
  local eph = ephemeris_data()
  local eph_age = cache_age_seconds(eph.TS)

  local eph_ok = has_body_payload(eph) and eph_age ~= nil and eph_age <= (ORB_CACHE_TTL * 3)

  local orbital_state = eph_ok and "NOMINAL" or "DEGRADED"
  local ephemeris_state

  if not has_body_payload(eph) or eph_age == nil then
    ephemeris_state = "MISSING"
  elseif eph_age <= (ORB_CACHE_TTL * 2) then
    ephemeris_state = "ACTIVE"
  else
    ephemeris_state = "STALE"
  end

  return {
    orbital_state = orbital_state,
    ephemeris_state = ephemeris_state,
  }
end

local function ts_in_window(ts, start_ts, end_ts)
  local numeric = tonumber(ts)
  return numeric ~= nil and numeric >= start_ts and numeric < end_ts
end

local function pick_today_rise_set(source_a, source_b, key)
  local day_start, day_end = current_day_window()

  local prev_rise = pick_numeric(source_a, source_b, key .. "_PREV_RISE_TS")
  local next_rise = pick_numeric(source_a, source_b, key .. "_NEXT_RISE_TS")
  local prev_set = pick_numeric(source_a, source_b, key .. "_PREV_SET_TS")
  local next_set = pick_numeric(source_a, source_b, key .. "_NEXT_SET_TS")

  local rise_ts = nil
  if ts_in_window(prev_rise, day_start, day_end) then
    rise_ts = prev_rise
  elseif ts_in_window(next_rise, day_start, day_end) then
    rise_ts = next_rise
  end

  local set_ts = nil
  if ts_in_window(prev_set, day_start, day_end) then
    set_ts = prev_set
  elseif ts_in_window(next_set, day_start, day_end) then
    set_ts = next_set
  end

  if rise_ts ~= nil and set_ts ~= nil then
    return rise_ts, set_ts
  end

  -- Preserve the carryover segment when the body rose before midnight and
  -- sets during the current day. Show the pair regardless of whether the
  -- set has already passed (e.g. moon rose at 23:51 and set at 09:18).
  if rise_ts == nil and prev_rise ~= nil and set_ts ~= nil then
    if prev_rise < day_start then
      return prev_rise, set_ts
    end
  end

  -- Preserve the evening segment when the body rises today and sets tomorrow.
  if rise_ts ~= nil and set_ts == nil and next_set ~= nil then
    if next_set >= day_end then
      return rise_ts, next_set
    end
  end

  return rise_ts, set_ts
end

function M.status_lines()
  local status = status_block()
  return {
    "ORBITAL DATA // " .. status.orbital_state,
    "EPHEMERIS // " .. status.ephemeris_state,
  }
end

function M.celestial_box_title()
  return "CELESTIAL"
end

function M.terminator_box_title()
  return "TERMINATOR"
end

function M.legend_rows()
  return {
    {
      symbol = "[----]",
      label = "VISIBLE ABOVE HORIZON",
    },
    {
      symbol = "square",
      label = "CURRENT TIME",
    },
  }
end

function M.celestial_rows()
  local eph = ephemeris_data()
  local fallback = {}
  local rows = {}

  for _, row in ipairs(BODY_ROWS) do
    local key = row.key
    local theta = pick_numeric(eph, fallback, key .. "_THETA")
    local alt = pick_numeric(eph, fallback, key .. "_ALT")
    local rise_ts, set_ts = pick_today_rise_set(eph, fallback, key)

    local data_text
    if key == "SUN" or key == "MOON" then
      data_text = string.format("%s/%s", fmt_hhmm(rise_ts), fmt_hhmm(set_ts))
    else
      local heading_value = display_heading(theta)
      local alt_value = alt and math.floor(alt + (alt >= 0 and 0.5 or -0.5)) or 0
      data_text = string.format("%03d %+03d", heading_value or 0, alt_value)
    end

    rows[#rows + 1] = {
      body = row.body,
      data = data_text,
      start_hour = hour_of_day(rise_ts),
      end_hour = hour_of_day(set_ts),
      theta = theta,
      alt = alt,
      visible_now = alt ~= nil and alt > 0 or nil,
    }
  end

  return rows
end

function M.time_markers()
  return { "00", "03", "06", "09", "12", "15", "18", "21", "24" }
end

function M.current_hour()
  local now = os.date("*t")
  return (now.hour or 0) + ((now.min or 0) / 60)
end

return M
