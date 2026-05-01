local M = {}

local function command_output(cmd)
  local p = io.popen(cmd, "r")
  if not p then return nil end
  local out = p:read("*a") or ""
  p:close()
  out = out:gsub("%s+$", "")
  if out == "" then return nil end
  return out
end

local function normalize_spaces(s)
  return (s or ""):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
end

local HOME = os.getenv("HOME") or ""
local RUNTIME_ROOT = os.getenv("GTEX62_CONFIG_DIR") or os.getenv("GTEX62_CONKY_CONFIG_DIR") or (HOME .. "/.config/gtex62-core")
local DEFAULT_ENGINE_CACHE_ROOT = os.getenv("GTEX62_CACHE_DIR") or os.getenv("GTEX62_CONKY_CACHE_DIR") or (HOME .. "/.cache/gtex62-core")
local DEFAULT_EXTRA_EVENTS = RUNTIME_ROOT .. "/state/events_extra.txt"
local SUN_EVENT_LOOKAHEAD_SECONDS = 3600

local function read_file(path)
  if not path or path == "" then return nil end
  local f = io.open(path, "r")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return s
end

local function parse_simple_toml(path)
  local out = {}
  local section = nil
  local s = read_file(path)
  if not s then return out end

  for line in s:gmatch("[^\r\n]+") do
    line = line:gsub("#.*$", ""):gsub("^%s+", ""):gsub("%s+$", "")
    if line ~= "" then
      local sec = line:match("^%[([%w_%-]+)%]$")
      if sec then
        section = sec
        out[section] = out[section] or {}
      else
        local k, v = line:match("^([%w_%-]+)%s*=%s*(.+)$")
        if k and v then
          v = v:gsub('^"', ""):gsub('"$', "")
          if section then
            out[section][k] = v
          else
            out[k] = v
          end
        end
      end
    end
  end

  return out
end

local function calendar_profile()
  return parse_simple_toml(RUNTIME_ROOT .. "/profiles/calendar/local.toml")
end

local function engine_config()
  local cfg = parse_simple_toml(RUNTIME_ROOT .. "/core.toml")
  if next(cfg) ~= nil then
    return cfg
  end
  return parse_simple_toml(RUNTIME_ROOT .. "/engine.toml")
end

local function suite_config()
  return parse_simple_toml(RUNTIME_ROOT .. "/suites/osa.toml")
end

local function engine_cache_root()
  local cfg = engine_config()
  return (((cfg or {}).paths or {}).cache_root) or DEFAULT_ENGINE_CACHE_ROOT
end

local function calendar_profile_id()
  return ((suite_config().profiles or {}).calendar) or "local"
end

local function astro_profile_id()
  return ((suite_config().profiles or {}).astro) or "home"
end

local function calendar_shared_dir()
  return string.format("%s/shared/calendar/%s", engine_cache_root(), calendar_profile_id())
end

local function astro_shared_dir()
  return string.format("%s/shared/astro/%s", engine_cache_root(), astro_profile_id())
end

local function time_profile_id()
  return ((suite_config().profiles or {}).time) or "local"
end

local function time_shared_dir()
  return string.format("%s/shared/time/%s", engine_cache_root(), time_profile_id())
end

local function calendar_events_json_path()
  return calendar_shared_dir() .. "/events.json"
end

local function calendar_status_json_path()
  return calendar_shared_dir() .. "/status.json"
end

local function astro_current_json_path()
  return astro_shared_dir() .. "/current.json"
end

local function time_current_json_path()
  return time_shared_dir() .. "/current.json"
end

local function event_cache_path()
  local profile = calendar_profile()
  local events = profile.events or {}
  return events.cache_file
end

local function extra_events_path()
  local profile = calendar_profile()
  local events = profile.events or {}
  return events.extra_events_file or DEFAULT_EXTRA_EVENTS
end

local function parse_event_lines(path, store)
  local s = read_file(path)
  if not s then return end
  for line in s:gmatch("[^\r\n]+") do
    line = line:gsub("#.*$", ""):gsub("^%s+", ""):gsub("%s+$", "")
    if line ~= "" then
      local date_str, name = line:match("^(%d%d%d%d%-%d%d%-%d%d)|([^|]+)")
      if date_str and name then
        store[date_str .. "|" .. name] = {
          date = date_str,
          name = normalize_spaces(name),
        }
      end
    end
  end
end

local function parse_json_events(path, store)
  local s = read_file(path)
  if not s then return false end
  local cmd = string.format("jq -r '.events[]? | [.date, .name] | @tsv' %q 2>/dev/null", path)
  local out = command_output(cmd)
  if not out then
    return false
  end
  for line in out:gmatch("[^\r\n]+") do
    local date_str, name = line:match("^([^\t]+)\t(.+)$")
    if date_str and name then
      store[date_str .. "|" .. name] = {
        date = date_str,
        name = normalize_spaces(name),
      }
    end
  end
  return true
end

local function parse_calendar_status(path)
  local s = read_file(path)
  if not s then
    return nil
  end

  local out = command_output(string.format("jq -r '[.state, .note] | @tsv' %q 2>/dev/null", path))
  if not out or out == "null" then
    return nil
  end

  local state, note = out:match("^([^\t]*)\t(.*)$")
  if not state then
    return nil
  end

  return {
    state = normalize_spaces(state),
    note = normalize_spaces(note),
  }
end

local function days_from_today(date_str)
  local y, m, d = date_str:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
  if not y then return nil end

  local now = os.date("*t") --[[@as osdate]]
  local today = os.time { year = now.year, month = now.month, day = now.day, hour = 12 }
  local event_day = os.time { year = y, month = m, day = d, hour = 12 }
  if not today or not event_day then return nil end

  return math.floor((event_day - today) / 86400)
end

local function format_countdown(seconds)
  seconds = math.max(0, math.floor(tonumber(seconds) or 0))
  local hours = math.floor(seconds / 3600)
  local minutes = math.floor((seconds % 3600) / 60)
  return string.format("-%02d:%02d", hours, minutes)
end

local function sun_event_status_line()
  local path = astro_current_json_path()
  if not read_file(path) then
    return nil
  end

  local out = command_output(string.format("jq -r '[.sun.next_rise_ts, .sun.next_set_ts] | @tsv' %q 2>/dev/null", path))
  if not out then
    return nil
  end

  local rise_text, set_text = out:match("^([^\t]*)\t([^\t]*)$")
  local now = os.time()
  local candidates = {
    { label = "SUNRISE", ts = tonumber(rise_text) },
    { label = "SUNSET", ts = tonumber(set_text) },
  }

  local next_event = nil
  for _, candidate in ipairs(candidates) do
    if candidate.ts and candidate.ts > now then
      local remaining = candidate.ts - now
      if remaining <= SUN_EVENT_LOOKAHEAD_SECONDS and (not next_event or remaining < next_event.remaining) then
        next_event = {
          label = candidate.label,
          remaining = remaining,
        }
      end
    end
  end

  if not next_event then
    return nil
  end

  return string.format("EVT // %s IN %s", next_event.label, format_countdown(next_event.remaining))
end

local function event_status_line()
  local status = parse_calendar_status(calendar_status_json_path())
  if status and status.state ~= "" and status.state ~= "ok" then
    local note = status.note ~= "" and (" - " .. status.note) or ""
    return string.upper("EVT // CAL " .. status.state .. note)
  end

  local sun_line = sun_event_status_line()
  if sun_line then
    return sun_line
  end

  local store = {}
  local loaded = parse_json_events(calendar_events_json_path(), store)
  if not loaded then
    parse_event_lines(event_cache_path(), store)
    parse_event_lines(extra_events_path(), store)
  end

  local today_key = tostring(os.date("%Y-%m-%d"))
  local next_event = nil
  for _, event in pairs(store) do
    if event.date >= today_key and (not next_event or event.date < next_event.date or (event.date == next_event.date and event.name < next_event.name)) then
      next_event = event
    end
  end

  if not next_event then
    if not loaded then
      return "EVT // CAL CACHE MISSING"
    end
    return "EVT // NONE"
  end

  local y, m, d = next_event.date:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
  local month = y and string.upper(tostring(os.date("%b", os.time { year = y, month = m, day = d }))) or next_event.date:sub(6, 7)
  local delta = days_from_today(next_event.date)
  local suffix = ""
  if delta == 0 then
    suffix = " TODAY"
  elseif delta and delta > 0 then
    suffix = string.format(" +%dD", delta)
  end

  return string.upper(string.format("EVT // %s %s %s%s", month, d or next_event.date, next_event.name, suffix))
end

local function days_in_month(y, m)
  local nm, ny = m + 1, y
  if nm == 13 then
    nm, ny = 1, y + 1
  end
  local t = os.time { year = ny, month = nm, day = 0 }
  local dt = os.date("*t", t) --[[@as osdate]]
  return dt.day
end

local function weekday_su0(y, m, d)
  local dt = os.date("*t", os.time { year = y, month = m, day = d }) --[[@as osdate]]
  return dt.wday - 1
end

local function build_weeks(y, m)
  local dim = days_in_month(y, m)
  local pm = (m == 1) and 12 or (m - 1)
  local py = (m == 1) and (y - 1) or y
  local prev_dim = days_in_month(py, pm)
  local nm = (m == 12) and 1 or (m + 1)
  local ny = (m == 12) and (y + 1) or y
  local first_col = weekday_su0(y, m, 1)
  local weeks, row = {}, {}

  for i = first_col, 1, -1 do
    row[#row + 1] = {
      day = prev_dim - i + 1,
      in_month = false,
      year = py,
      month = pm,
    }
  end

  for d = 1, dim do
    row[#row + 1] = {
      day = d,
      in_month = true,
      year = y,
      month = m,
    }
    if #row == 7 then
      weeks[#weeks + 1] = row
      row = {}
    end
  end

  local next_day = 1
  if #row > 0 then
    while #row < 7 do
      row[#row + 1] = {
        day = next_day,
        in_month = false,
        year = ny,
        month = nm,
      }
      next_day = next_day + 1
    end
    weeks[#weeks + 1] = row
  end

  local fill_month = nm
  local fill_year = ny
  while #weeks < 6 do
    local fill = {}
    for _ = 1, 7 do
      fill[#fill + 1] = {
        day = next_day,
        in_month = false,
        year = fill_year,
        month = fill_month,
      }
      next_day = next_day + 1
      if next_day > days_in_month(fill_year, fill_month) then
        next_day = 1
        if fill_month == 12 then
          fill_month = 1
          fill_year = fill_year + 1
        else
          fill_month = fill_month + 1
        end
      end
    end
    weeks[#weeks + 1] = fill
  end

  return weeks
end

local function tz_date_parts(tz)
  local out = command_output(string.format(
    "TZ=%q date +'%%Z|%%z|%%H:%%M|%%b %%d' 2>/dev/null",
    tz
  ))
  if not out then
    return nil
  end

  local zone_text, raw_off, time_text, date_text = out:match("^([^|]*)|([%+%-]%d%d%d%d)|([^|]+)|(.+)$")
  if not raw_off then
    return nil
  end

  return {
    zone = string.upper(normalize_spaces(zone_text or "")),
    off = raw_off:sub(1, 3),
    time = normalize_spaces(time_text or ""),
    date = string.upper(normalize_spaces(date_text or "")),
  }
end

local function parse_time_rows(path)
  local s = read_file(path)
  if not s then
    return nil
  end

  local out = command_output(string.format("jq -r '.rows[]? | [.zone, .off, .time, .date, .name] | @tsv' %q 2>/dev/null", path))
  if not out then
    return nil
  end

  local rows = {}
  for line in out:gmatch("[^\r\n]+") do
    local zone, off, time_text, date_text, name = line:match("^([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)$")
    if zone then
      rows[#rows + 1] = {
        zone = zone,
        off = off,
        time = time_text,
        date = date_text,
        name = name,
      }
    end
  end

  return rows
end

local function parse_time_local(path)
  local s = read_file(path)
  if not s then
    return nil
  end
  local out = command_output(string.format("jq -r '[.local.zone, .local.time, .local.date] | @tsv' %q 2>/dev/null", path))
  if not out or out == "null" then
    return nil
  end
  local zone, time_text, date_text = out:match("^([^\t]*)\t([^\t]*)\t([^\t]*)$")
  if not zone then
    return nil
  end
  return {
    zone = zone,
    time = time_text,
    date = date_text,
  }
end

function M.status_lines()
  local evt_line = event_status_line()
  local local_time = parse_time_local(time_current_json_path())
  local zone = (local_time and local_time.zone ~= "" and local_time.zone)
    or string.upper(tostring(os.date("%Z")))
  local date_str = (local_time and local_time.date ~= "" and local_time.date)
    or string.upper(tostring(os.date("%a, %b %d, %Y")))
  return {
    string.format("%s // %s", zone, tostring(os.date("%H:%M:%S"))),
    string.format("CAL // %s", date_str),
    evt_line,
  }
end

function M.clock_box_title()
  return "CLOCK"
end

function M.calendar_box_title()
  return "CALENDAR"
end

function M.clock_rows()
  local rows = parse_time_rows(time_current_json_path())
  if rows and #rows > 0 then
    return rows
  end

  local DISPLAY_ZONES = {
    { zone = "UTC", tz = "UTC", name = "UNIVERSAL TIME COORDINATED" },
    { zone = "CT", tz = "America/Chicago", name = "CENTRAL TIME" },
    { zone = "PT", tz = "America/Los_Angeles", name = "PACIFIC TIME" },
    { zone = "CET", tz = "Europe/Berlin", name = "CENTRAL EUROPEAN TIME" },
    { zone = "JST", tz = "Asia/Tokyo", name = "JAPAN STANDARD TIME" },
  }

  rows = {}
  for _, spec in ipairs(DISPLAY_ZONES) do
    local parts = tz_date_parts(spec.tz) or {}
    rows[#rows + 1] = {
      zone = parts.zone or spec.zone,
      off = parts.off or "",
      time = parts.time or "",
      date = parts.date or "",
      name = string.upper(spec.name),
    }
  end
  return rows
end

function M.calendar_title()
  return string.upper(tostring(os.date("%B %Y")))
end

function M.calendar_weeks()
  local now = os.date("*t") --[[@as osdate]]
  return build_weeks(now.year, now.month)
end

function M.calendar_today()
  local now = os.date("*t") --[[@as osdate]]
  return now.day
end

function M.calendar_events()
  local weeks = M.calendar_weeks()
  local first = weeks[1] and weeks[1][1]
  local last = weeks[6] and weeks[6][7]
  if not first or not last then return {} end

  local start_key = string.format("%04d-%02d-%02d", first.year, first.month, first.day)
  local end_key = string.format("%04d-%02d-%02d", last.year, last.month, last.day)
  local store = {}
  if not parse_json_events(calendar_events_json_path(), store) then
    parse_event_lines(event_cache_path(), store)
    parse_event_lines(extra_events_path(), store)
  end

  local events = {}
  for _, event in pairs(store) do
    if event.date >= start_key and event.date <= end_key then
      events[#events + 1] = {
        date = event.date,
        text = string.upper(string.format("%s - %s", event.date:sub(9, 10), event.name)),
      }
    end
  end

  table.sort(events, function(a, b)
    if a.date == b.date then return a.text < b.text end
    return a.date < b.date
  end)

  return events
end

function M.calendar_event_dates()
  local map = {}
  for _, event in ipairs(M.calendar_events()) do
    map[event.date] = true
  end
  return map
end

return M
