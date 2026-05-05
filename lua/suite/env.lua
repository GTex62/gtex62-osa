local M = {}

local HOME = os.getenv("HOME") or ""
local SUITE_DIR = os.getenv("CONKY_SUITE_DIR") or (HOME .. "/.config/conky/gtex62-osa")
local SHARED_ASSETS_DIR = os.getenv("GTEX62_SHARED_ASSETS") or os.getenv("GTEX62_SHARED_ASSETS_DIR") or (HOME .. "/.config/conky/gtex62-shared-assets")
local XDG_CACHE_HOME = os.getenv("XDG_CACHE_HOME") or (HOME .. "/.cache")
local RUNTIME_ROOT = os.getenv("GTEX62_CONFIG_DIR") or os.getenv("GTEX62_CONKY_CONFIG_DIR") or (HOME .. "/.config/gtex62-core")
local DEFAULT_ENGINE_CACHE_ROOT = os.getenv("GTEX62_CACHE_DIR") or os.getenv("GTEX62_CONKY_CACHE_DIR") or (XDG_CACHE_HOME .. "/gtex62-core")

local CACHE = {
  stamp = nil,
  air = nil,
  solar = nil,
  pollen = nil,
  pollen_csv = nil,
}

local function read_file(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return s
end

local function command_output(cmd)
  local p = io.popen(cmd, "r")
  if not p then return nil end
  local out = p:read("*a") or ""
  p:close()
  out = out:gsub("%s+$", "")
  if out == "" then return nil end
  return out
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
        local key, value = line:match("^([%w_%-]+)%s*=%s*(.+)$")
        if key and value then
          value = value:gsub('^"', ""):gsub('"$', "")
          if section then
            out[section][key] = value
          else
            out[key] = value
          end
        end
      end
    end
  end

  return out
end

local function engine_config()
  local cfg = parse_simple_toml(RUNTIME_ROOT .. "/core.toml")
  if next(cfg) ~= nil then return cfg end
  return parse_simple_toml(RUNTIME_ROOT .. "/engine.toml")
end

local function suite_config()
  return parse_simple_toml(RUNTIME_ROOT .. "/suites/osa.toml")
end

local function profile_id(domain, fallback)
  return ((suite_config().profiles or {})[domain]) or fallback
end

local function engine_cache_roots()
  local cfg = engine_config()
  local configured = (((cfg or {}).paths or {}).cache_root)
  local out = {}
  local seen = {}
  local function add(root)
    if root and root ~= "" and not seen[root] then
      seen[root] = true
      out[#out + 1] = root
    end
  end
  add(configured)
  add(DEFAULT_ENGINE_CACHE_ROOT)
  add(XDG_CACHE_HOME .. "/gtex62-core")
  return out
end

local function first_existing(paths)
  for _, path in ipairs(paths or {}) do
    if path and read_file(path) then
      return path
    end
  end
  return nil
end

local function json_query(path, filter)
  if not read_file(path) then return nil end
  local out = command_output(string.format("jq -r %q %q 2>/dev/null", filter, path))
  if not out or out == "" or out == "null" then return nil end
  return out
end

local function json_number(path, filter)
  return tonumber(json_query(path, filter))
end

local function shared_paths(domain, profile, filename)
  local paths = {}
  for _, root in ipairs(engine_cache_roots()) do
    paths[#paths + 1] = string.format("%s/shared/%s/%s/%s", root, domain, profile, filename)
  end
  return paths
end

local function air_current_paths()
  local profile = profile_id("air", "home")
  return shared_paths("air", profile, "current.json")
end

local function air_status_paths()
  local profile = profile_id("air", "home")
  return shared_paths("air", profile, "status.json")
end

local function solar_current_paths()
  local profile = profile_id("solar", "home")
  return shared_paths("solar", profile, "current.json")
end

local function solar_status_paths()
  local profile = profile_id("solar", "home")
  return shared_paths("solar", profile, "status.json")
end

local function parse_tsv(line)
  local fields = {}
  local idx = 1
  local start = 1
  line = line or ""
  while true do
    local tab = line:find("\t", start, true)
    if not tab then
      fields[idx] = line:sub(start)
      break
    end
    fields[idx] = line:sub(start, tab - 1)
    idx = idx + 1
    start = tab + 1
  end
  return fields
end

local function field_number(fields, idx)
  local v = fields and fields[idx]
  if v == nil or v == "" or v == "null" then return nil end
  return tonumber(v)
end

local function parse_iso_utc(text)
  local y, m, d, hh, mm, ss = tostring(text or ""):match("^(%d%d%d%d)%-(%d%d)%-(%d%d)T(%d%d):(%d%d):(%d%d)Z$")
  if not y then return nil end
  return tonumber(command_output(string.format(
    "date -ud '%s-%s-%s %s:%s:%s' +%%s 2>/dev/null",
    y, m, d, hh, mm, ss
  )))
end

local function parse_timestamp(value)
  local n = tonumber(value)
  if n and n > 0 then return n end
  return parse_iso_utc(value)
end

local function json_timestamp(path, filter)
  return parse_timestamp(json_query(path, filter))
end

local function first_status_state(paths)
  local path = first_existing(paths)
  if not path then return nil end
  return json_query(path, ".state // empty")
end

local function first_timestamp(paths, filter)
  for _, path in ipairs(paths or {}) do
    local ts = json_timestamp(path, filter)
    if ts then return ts end
  end
  return nil
end

local function sibling_status_path(current_path)
  if not current_path then return nil end
  local path = current_path:gsub("/current%.json$", "/status.json")
  if path ~= current_path and read_file(path) then
    return path
  end
  return nil
end

local function sibling_raw_path(current_path, filename)
  if not current_path then return nil end
  local path = current_path:gsub("/current%.json$", "/" .. filename)
  if path ~= current_path and read_file(path) then
    return path
  end
  return nil
end

local function round_int(value)
  local n = tonumber(value) or 0
  return math.floor(n + 0.5)
end

local function format_decimal(value, decimals)
  local n = tonumber(value) or 0
  return string.format("%." .. tostring(decimals or 0) .. "f", n)
end

local function owm_aqi_to_airnow(aqi)
  local n = tonumber(aqi)
  if not n then return 0 end
  if n <= 1 then return 25 end
  if n == 2 then return 75 end
  if n == 3 then return 125 end
  if n == 4 then return 175 end
  return 250
end

local function read_air()
  local path = first_existing(air_current_paths())
  if not path then
    return {
      available = false,
      status_state = first_status_state(air_status_paths()),
      updated_ts = first_timestamp(air_status_paths(), ".provider_updated_at // .generated_at // empty"),
    }
  end

  local out = command_output(string.format([[
jq -r '[
  (.airnow.aqi // ""),
  (.openweather.aqi // ""),
  (.selected.pm2_5 // ""),
  (.selected.o3 // ""),
  (.selected.pm10 // ""),
  (.selected.no2 // ""),
  (.selected.so2 // ""),
  (.selected.co // ""),
  (.selected.nh3 // "")
] | @tsv' %q 2>/dev/null]], path))
  local fields = parse_tsv(out)
  local owm_aqi = field_number(fields, 2)
  local status_path = sibling_status_path(path)
  local raw_obs_path = sibling_raw_path(path, "raw_airnow_observation.json")
  local raw_data_path = sibling_raw_path(path, "raw_airnow_data.json")
  local raw_airnow_aqi = raw_obs_path and json_number(raw_obs_path, "[.[].AQI? // empty] | max // empty") or nil
  local raw_airnow_pm25 = raw_data_path and json_number(
    raw_data_path,
    [[def epoch: if . == null then null elif type == "number" then . else (tostring | strptime("%Y-%m-%dT%H:%M")? | mktime) end; [.[]? | select((.Parameter // "" | ascii_upcase) == "PM2.5" or (.Parameter // "" | ascii_upcase) == "PM25") | {value:(.RawConcentration // .Value), ts:(.UTC | epoch)} | select(.value != null and (.value | tonumber) >= 0 and .ts != null)] | sort_by(.ts) | last.value // empty]]
  ) or nil

  return {
    available = true,
    path = path,
    status_state = status_path and json_query(status_path, ".state // empty") or nil,
    updated_ts = json_timestamp(path, ".provider_updated_at // .generated_at // .openweather.observed_ts // .airnow.latest_ts // empty")
      or (status_path and json_timestamp(status_path, ".provider_updated_at // .generated_at // empty")),
    airnow_ts = json_timestamp(path, ".airnow.aqi_ts // .airnow.latest_ts // .airnow.observed_ts // empty"),
    airnow_aqi = field_number(fields, 1) or raw_airnow_aqi,
    airnow_values = {
      pm2_5 = json_number(path, ".airnow.values.pm2_5 // empty") or raw_airnow_pm25,
      o3 = json_number(path, ".airnow.values.o3 // empty"),
      pm10 = json_number(path, ".airnow.values.pm10 // empty"),
      no2 = json_number(path, ".airnow.values.no2 // empty"),
      so2 = json_number(path, ".airnow.values.so2 // empty"),
      co = json_number(path, ".airnow.values.co // empty"),
      nh3 = json_number(path, ".airnow.values.nh3 // empty"),
    },
    owm_aqi = owm_aqi,
    owm_aqi_mapped = owm_aqi_to_airnow(owm_aqi),
    components = {
      pm2_5 = raw_airnow_pm25 or field_number(fields, 3),
      o3 = field_number(fields, 4),
      pm10 = field_number(fields, 5),
      no2 = field_number(fields, 6),
      so2 = field_number(fields, 7),
      co = field_number(fields, 8),
      nh3 = field_number(fields, 9),
    },
  }
end

local function read_solar()
  local path = first_existing(solar_current_paths())
  if not path then
    return {
      available = false,
      status_state = first_status_state(solar_status_paths()),
      updated_ts = first_timestamp(solar_status_paths(), ".provider_updated_at // .generated_at // empty"),
    }
  end

  local out = command_output(string.format([[
jq -r '[
  (.norm.UV // .normalized.UV // .values.UV // ""),
  (.norm.RAD // .normalized.RAD // .values.RAD // ""),
  (.values.UV // ""),
  (.values.RAD // ""),
  (.meta.uv_source // "synthetic")
] | @tsv' %q 2>/dev/null]], path))
  local fields = parse_tsv(out)
  local uv = field_number(fields, 1)
  local rad = field_number(fields, 2)
  local uv_value = field_number(fields, 3)
  local rad_value = field_number(fields, 4)
  local uv_source = fields[5] or "synthetic"

  if uv and uv <= 1 then uv = uv * 100 end
  if rad and rad <= 1 then rad = rad * 100 end
  if rad and rad > 100 then rad = rad / 10 end
  local status_path = sibling_status_path(path)

  return {
    available = true,
    path = path,
    status_state = status_path and json_query(status_path, ".state // empty") or nil,
    updated_ts = json_timestamp(path, ".provider_updated_at // .generated_at // .timestamp // empty")
      or (status_path and json_timestamp(status_path, ".provider_updated_at // .generated_at // empty")),
    uv = uv,
    rad = rad,
    uv_value = uv_value or uv,
    rad_value = rad_value or rad,
    uv_source = uv_source,
  }
end

local function pollen_csv_path()
  local candidates = {
    SHARED_ASSETS_DIR .. "/data/pollen/pollen_mem_v2.csv",
    SHARED_ASSETS_DIR .. "/data/pollen/pollen_mem_v1.csv",
  }
  return first_existing(candidates)
end

local function read_pollen()
  local path = pollen_csv_path()
  if not path then
    return { available = false, tree = 0, grass = 0, weed = 0, mold = 0 }
  end

  local doy = (os.date("*t") or {}).yday or tonumber(os.date("%j"))
  local f = io.open(path, "r")
  if not f then
    return { available = false, path = path, tree = 0, grass = 0, weed = 0, mold = 0 }
  end

  for line in f:lines() do
    local d, tree, grass, weed, mold = line:match("^(%d+),(%-?[%d%.]+),(%-?[%d%.]+),(%-?[%d%.]+),(%-?[%d%.]+)")
    if d and tonumber(d) == doy then
      f:close()
      return {
        available = true,
        path = path,
        tree = tonumber(tree) or 0,
        grass = tonumber(grass) or 0,
        weed = tonumber(weed) or 0,
        mold = tonumber(mold) or 0,
      }
    end
  end

  f:close()
  return { available = true, path = path, tree = 0, grass = 0, weed = 0, mold = 0 }
end

local function refresh()
  local stamp = math.floor(os.time() / 60)
  if CACHE.stamp == stamp then return end
  CACHE.stamp = stamp
  CACHE.air = read_air()
  CACHE.solar = read_solar()
  CACHE.pollen = read_pollen()
end

local function data_status()
  refresh()
  local air = CACHE.air or {}
  local pollen = CACHE.pollen or {}

  if air.status_state == "error" then
    return "FAULT", "AIR CACHE ERROR"
  end

  if not air.available then
    return "PARTIAL", "AIR CACHE MISSING"
  end

  if not pollen.available then
    return "PARTIAL", "POLLEN CSV MISSING"
  end

  if air.updated_ts and (os.time() - air.updated_ts) > 7200 then
    return "STALE", "AIR CACHE"
  end

  return "NOMINAL", nil
end

local function source_line()
  refresh()
  local air = CACHE.air or {}
  local parts = {}

  if air.airnow_aqi then
    parts[#parts + 1] = "AQI"
  end

  local values = air.airnow_values or {}
  local labels = {
    { key = "pm2_5", label = "PM2.5" },
    { key = "o3", label = "O3" },
    { key = "pm10", label = "PM10" },
    { key = "no2", label = "NO2" },
    { key = "so2", label = "SO2" },
    { key = "co", label = "CO" },
    { key = "nh3", label = "NH3" },
  }

  for _, item in ipairs(labels) do
    if values[item.key] ~= nil then
      parts[#parts + 1] = item.label
    end
  end

  local solar = CACHE.solar or {}
  local sol_tag = (solar.uv_source == "open-meteo") and "MET" or "DRV"

  if #parts == 0 then
    return "SRC // OWM BASE | ANW NONE | " .. sol_tag
  end

  return "SRC // OWM BASE | ANW " .. table.concat(parts, " ") .. " | " .. sol_tag
end

function M.status_lines()
  refresh()
  local state, reason = data_status()
  local data_line = "DATA // " .. state
  if reason and reason ~= "" then
    data_line = data_line .. " - " .. reason
  end
  return {
    data_line,
    source_line(),
  }
end

function M.atmos_box_title()
  return "ATMOS"
end

function M.aqi_airnow_value()
  refresh()
  local air = CACHE.air or {}
  return round_int(air.airnow_aqi or 0)
end

function M.aqi_owm_value()
  refresh()
  local air = CACHE.air or {}
  return round_int(air.owm_aqi or 0)
end

function M.solar_uv_value()
  refresh()
  return round_int((CACHE.solar or {}).uv or 0)
end

function M.solar_rad_value()
  refresh()
  return round_int((CACHE.solar or {}).rad or 0)
end

function M.solar_uv_text()
  refresh()
  return format_decimal((CACHE.solar or {}).uv_value or 0, 1)
end

function M.solar_rad_text()
  refresh()
  return string.format("%d", round_int((CACHE.solar or {}).rad_value or 0))
end

function M.pollution_rows()
  refresh()
  local c = (CACHE.air or {}).components or {}
  return {
    { label = "PARTICULATE MATTER 2.5", value = string.format("%03d", round_int(c.pm2_5)) },
    { label = "OZONE", value = string.format("%03d", round_int(c.o3)) },
    { label = "PARTICULATE MATTER 10", value = string.format("%03d", round_int(c.pm10)) },
    { label = "NITROGEN DIOXIDE", value = string.format("%03d", round_int(c.no2)) },
    { label = "SULFUR DIOXIDE", value = string.format("%03d", round_int(c.so2)) },
    { label = "CARBON MONOXIDE", value = string.format("%03d", round_int(c.co)) },
    { label = "AMMONIA", value = string.format("%03d", round_int(c.nh3)) },
  }
end

function M.pollen_rows()
  refresh()
  local p = CACHE.pollen or {}
  return {
    { label = "TREE", value = string.format("%03d", round_int(p.tree)) },
    { label = "GRASS", value = string.format("%03d", round_int(p.grass)) },
    { label = "WEED", value = string.format("%03d", round_int(p.weed)) },
    { label = "MOLD", value = string.format("%03d", round_int(p.mold)) },
  }
end

return M
