local M = {}

local HOME = os.getenv("HOME") or ""
local SUITE_DIR = os.getenv("CONKY_SUITE_DIR") or (HOME .. "/.config/conky/gtex62-osa")
local RUNTIME_ROOT = os.getenv("GTEX62_CONFIG_DIR") or os.getenv("GTEX62_CONKY_CONFIG_DIR") or (HOME .. "/.config/gtex62-core")
local DEFAULT_ENGINE_CACHE_ROOT = os.getenv("GTEX62_CACHE_DIR") or os.getenv("GTEX62_CONKY_CACHE_DIR") or (HOME .. "/.cache/gtex62-core")

local WEATHER_CODES = nil
local load_weather_codes
local read_aviation_text
local CACHE = {
  stamp = nil,
  current = nil,
  metar_lines = nil,
  station_model = nil,
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

local function minute_stamp()
  return math.floor(os.time() / 60)
end

local function parse_simple_toml(path)
  local out = {}
  local section = nil
  local s = read_file(path)
  if not s then
    return out
  end

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

local function load_theme()
  local ok, theme = pcall(dofile, SUITE_DIR .. "/theme/osa-theme.lua")
  if ok and type(theme) == "table" then
    return theme
  end
  return {}
end

local function current_box_cfg()
  local theme = load_theme()
  return (((theme or {}).wxr or {}).current or {})
end

local function forecast_box_cfg()
  local theme = load_theme()
  return (((theme or {}).wxr or {}).forecast or {})
end

local function station_model_box_cfg()
  local theme = load_theme()
  return (((theme or {}).wxr or {}).station_model or {})
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

local function profile_config(domain, fallback)
  local profile_id = ((suite_config().profiles or {})[domain]) or fallback
  return profile_id, parse_simple_toml(string.format("%s/profiles/%s/%s.toml", RUNTIME_ROOT, domain, profile_id))
end

local function engine_cache_root()
  local cfg = engine_config()
  return (((cfg or {}).paths or {}).cache_root) or DEFAULT_ENGINE_CACHE_ROOT
end

local function weather_profile_id()
  local profile_id = profile_config("weather", "home")
  return profile_id
end

local function aviation_profile_id()
  local profile_id = profile_config("aviation", "home")
  return profile_id
end

local function aviation_station(kind)
  local _, cfg = profile_config("aviation", "home")
  local stations = cfg.stations or {}
  if stations[kind] then return string.upper(stations[kind]) end
  if kind == "station_model" then
    local site = parse_simple_toml(string.format("%s/site.toml", RUNTIME_ROOT))
    local av = (site.aviation or {})
    local id = av.station_model or av.metar or av.primary
    if id and id ~= "" then return string.upper(id) end
  end
  return string.upper(stations.primary or "KMEM")
end

local function weather_shared_dir()
  return string.format("%s/shared/weather/%s", engine_cache_root(), weather_profile_id())
end

local function aviation_shared_dir()
  return string.format("%s/shared/aviation/%s", engine_cache_root(), aviation_profile_id())
end

local function weather_current_path()
  return weather_shared_dir() .. "/current.json"
end

local function weather_forecast_path()
  return weather_shared_dir() .. "/forecast_daily.json"
end

local function weather_status_path()
  return weather_shared_dir() .. "/status.json"
end

local function aviation_current_path()
  return aviation_shared_dir() .. "/current.json"
end

local function aviation_status_path()
  return aviation_shared_dir() .. "/status.json"
end

local function json_query(path, filter)
  if not read_file(path) then
    return nil
  end
  local cmd = string.format("jq -r %q %q 2>/dev/null", filter, path)
  local out = command_output(cmd)
  if not out or out == "null" or out == "" then
    return nil
  end
  return out
end

local function json_number(path, filter)
  return tonumber(json_query(path, filter))
end

local function normalize_spaces(s)
  return (s or ""):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
end

local function parse_iso_utc(text)
  local y, m, d, hh, mm, ss = tostring(text or ""):match("^(%d%d%d%d)%-(%d%d)%-(%d%d)T(%d%d):(%d%d):(%d%d)Z$")
  if not y then return nil end
  local epoch = command_output(string.format(
    "date -ud '%s-%s-%s %s:%s:%s' +%%s 2>/dev/null",
    y, m, d, hh, mm, ss
  ))
  return tonumber(epoch)
end

local function parse_timestamp(value)
  local n = tonumber(value)
  if n and n > 0 then
    return n
  end
  return parse_iso_utc(value)
end

local function json_timestamp(path, filter)
  return parse_timestamp(json_query(path, filter))
end

local function format_hhmm_local(ts)
  if not ts then return "--:--" end
  return os.date("%H:%M", ts)
end

local function format_hhmm_utc(ts)
  if not ts then return "--:--" end
  return os.date("!%H:%M", ts)
end

local function file_exists(path)
  return read_file(path) ~= nil
end

local function metar_observation_ts(raw)
  local token = tostring(raw or ""):match("%f[%w](%d%d%d%d%d%dZ)%f[%W]")
  if not token then return nil end
  local dd, hh, mm = token:match("^(%d%d)(%d%d)(%d%d)Z$")
  dd, hh, mm = tonumber(dd), tonumber(hh), tonumber(mm)
  if not dd or not hh or not mm then return nil end
  local now = os.date("!*t")
  local year, month = now.year, now.month
  if dd > now.day + 15 then
    month = month - 1
    if month < 1 then
      month = 12
      year = year - 1
    end
  end
  local epoch = command_output(string.format(
    "date -ud '%04d-%02d-%02d %02d:%02d:00' +%%s 2>/dev/null",
    year, month, dd, hh, mm
  ))
  return tonumber(epoch)
end

local function taf_issue_ts(raw)
  local token = tostring(raw or ""):match("^TAF%s+%w+%s+(%d%d%d%d%d%dZ)")
    or tostring(raw or ""):match("%f[%w]TAF%s+%w+%s+(%d%d%d%d%d%dZ)")
  if not token then return nil end
  local dd, hh, mm = token:match("^(%d%d)(%d%d)(%d%d)Z$")
  dd, hh, mm = tonumber(dd), tonumber(hh), tonumber(mm)
  if not dd or not hh or not mm then return nil end
  local now = os.date("!*t")
  local year, month = now.year, now.month
  if dd > now.day + 15 then
    month = month - 1
    if month < 1 then
      month = 12
      year = year - 1
    end
  end
  local epoch = command_output(string.format(
    "date -ud '%04d-%02d-%02d %02d:%02d:00' +%%s 2>/dev/null",
    year, month, dd, hh, mm
  ))
  return tonumber(epoch)
end

local function weather_data_state()
  local weather_status_state = json_query(weather_status_path(), ".state // empty")
  local aviation_status_state = json_query(aviation_status_path(), ".state // empty")
  local weather_current_ok = file_exists(weather_current_path())
  local weather_forecast_ok = file_exists(weather_forecast_path())
  local aviation_ok = file_exists(aviation_current_path())
  local complete = weather_current_ok and weather_forecast_ok and aviation_ok

  local weather_provider_ts = json_timestamp(weather_status_path(), ".provider_updated_at // .generated_at // empty")
  local aviation_generated_ts = json_timestamp(aviation_current_path(), ".generated_at // empty")
  local newest_age = nil
  local ages = {}
  if weather_provider_ts then ages[#ages + 1] = os.time() - weather_provider_ts end
  if aviation_generated_ts then ages[#ages + 1] = os.time() - aviation_generated_ts end
  if #ages > 0 then
    newest_age = ages[1]
    for i = 2, #ages do
      newest_age = math.max(newest_age, ages[i])
    end
  end

  if weather_status_state == "error" or aviation_status_state == "error" then
    return "FAULT"
  end
  if not complete then
    return "PARTIAL"
  end
  if newest_age and newest_age > 7200 then
    return "STALE"
  end
  return "NOMINAL"
end

local function aviation_data_state()
  local aviation_status_state = json_query(aviation_status_path(), ".state // empty")
  local cur = file_exists(aviation_current_path())
  local metar = file_exists(aviation_shared_dir() .. "/metar_raw.txt")
  local taf = file_exists(aviation_shared_dir() .. "/taf_raw.txt")
  local complete = cur and metar and taf

  local metar_ts = metar_observation_ts(read_aviation_text("metar") or "")
  local taf_ts = taf_issue_ts(read_aviation_text("taf") or "")
  local newest_age = nil
  if metar_ts and taf_ts then
    newest_age = math.max(os.time() - metar_ts, os.time() - taf_ts)
  elseif metar_ts then
    newest_age = os.time() - metar_ts
  elseif taf_ts then
    newest_age = os.time() - taf_ts
  end

  if aviation_status_state == "error" then
    return "FAULT"
  end
  if not complete then
    return "PARTIAL"
  end
  if newest_age and newest_age > 43200 then
    return "STALE"
  end
  return "NOMINAL"
end

local function format_temp_3(value)
  local n = tonumber(value)
  if not n then return "---" end
  return string.format("%03d", math.floor(n + 0.5))
end

local function forecast_date_label(index, raw_date)
  local text = tostring(raw_date or "")
  local year = os.date("*t").year
  local y, m, d = text:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)")
  if y and m and d then
    local ts = os.time({ year = y, month = m, day = d, hour = 12 })
    if ts then
      return string.upper(tostring(os.date("%b %d", ts)))
    end
  end

  m, d = text:match("^(%d%d)%.(%d%d)$")
  if m and d then
    local ts = os.time({ year = year, month = m, day = d, hour = 12 })
    if ts then
      return string.upper(tostring(os.date("%b %d", ts)))
    end
  end

  if text ~= "" then
    return string.upper(text)
  end

  local base = os.date("*t")
  local ts = os.time({
    year = base.year,
    month = base.month,
    day = base.day + tonumber(index or 0),
    hour = 12,
  })
  return string.upper(tostring(os.date("%b %d", ts)))
end

local function forecast_glyphs(icon, cloud_percent, wx_id)
  local weather_codes = load_weather_codes()
  local cloud_info = nil
  local wx_info = nil
  local cloud_numeric = tonumber(cloud_percent)

  if weather_codes then
    if weather_codes.cloud_from_percent and cloud_numeric ~= nil then
      cloud_info = weather_codes.cloud_from_percent(cloud_numeric)
    end
    if weather_codes.wx_from_owm then
      wx_info = weather_codes.wx_from_owm(wx_id)
    end
  end

  local code = tostring(icon or ""):match("^(%d%d)")
  local sky_fallback = {
    ["01"] = "N_0",
    ["02"] = "N_2",
    ["03"] = "N_4",
    ["04"] = "N_8",
    ["09"] = "N_8",
    ["10"] = "N_6",
    ["11"] = "N_6",
    ["13"] = "N_8",
    ["50"] = "N_2",
  }
  local wx_fallback = {
    ["09"] = "shower",
    ["10"] = "rain",
    ["11"] = "thunder",
    ["13"] = "snow",
    ["50"] = "haze",
  }

  local sky = cloud_info and cloud_info.glyph or nil
  if (not sky or sky == "") and weather_codes and weather_codes.CLOUD_GLYPHS then
    sky = weather_codes.CLOUD_GLYPHS[sky_fallback[code or ""] or "N_Slash"]
  end

  local wx = wx_info and wx_info.glyph or nil
  if (not wx or wx == "") and weather_codes and weather_codes.WX_GLYPHS then
    wx = weather_codes.WX_GLYPHS[wx_fallback[code or ""] or "none"] or ""
  end

  return sky or "---", wx or ""
end

load_weather_codes = function()
  if WEATHER_CODES ~= nil then
    return WEATHER_CODES
  end

  local ok, mod = pcall(dofile, SUITE_DIR .. "/lua/lib/weather_codes.lua")
  if ok and type(mod) == "table" then
    WEATHER_CODES = mod
  else
    WEATHER_CODES = false
  end

  return WEATHER_CODES
end

local function utf8_char(codepoint)
  if utf8 and utf8.char then
    return utf8.char(codepoint)
  end
  if codepoint <= 0x7F then
    return string.char(codepoint)
  elseif codepoint <= 0x7FF then
    local b1 = 0xC0 + math.floor(codepoint / 0x40)
    local b2 = 0x80 + (codepoint % 0x40)
    return string.char(b1, b2)
  elseif codepoint <= 0xFFFF then
    local b1 = 0xE0 + math.floor(codepoint / 0x1000)
    local b2 = 0x80 + (math.floor(codepoint / 0x40) % 0x40)
    local b3 = 0x80 + (codepoint % 0x40)
    return string.char(b1, b2, b3)
  end
  local b1 = 0xF0 + math.floor(codepoint / 0x40000)
  local b2 = 0x80 + (math.floor(codepoint / 0x1000) % 0x40)
  local b3 = 0x80 + (math.floor(codepoint / 0x40) % 0x40)
  local b4 = 0x80 + (codepoint % 0x40)
  return string.char(b1, b2, b3, b4)
end

local function extract_ob_line(raw)
  if not raw or raw == "" then return "" end
  for line in raw:gmatch("[^\r\n]+") do
    local ob = line:match("^ob:%s*(.+)$")
    if ob and ob ~= "" then
      return normalize_spaces(ob)
    end
  end
  return normalize_spaces(raw)
end

local function temp_to_num(s)
  if not s then return nil end
  local neg = s:sub(1, 1) == "M"
  local v = tonumber(neg and s:sub(2) or s)
  if v == nil then return nil end
  return neg and -v or v
end

local function slp_code_from_hpa(hpa)
  if not hpa then return nil end
  return string.format("%03d", math.floor((hpa * 10) + 0.5) % 1000)
end

local function hpa_from_slp_code(code)
  if not code then return nil end
  local n = tonumber(code)
  if not n then return nil end
  return (n >= 500 and 900 or 1000) + (n / 10.0)
end

local function inhg_to_hpa(inhg)
  if not inhg then return nil end
  return inhg * 33.8639
end

local function hpa_to_inhg(hpa)
  if not hpa then return nil end
  return hpa * 0.0295299830714
end

local function parse_wind(tokens)
  for _, tok in ipairs(tokens) do
    local dir_g, spd_g, gust_g = tok:match("^(%d%d%d)(%d+)G(%d+)KT$")
    if dir_g then
      return tonumber(dir_g), tonumber(spd_g), tonumber(gust_g), false
    end
    local dir, spd = tok:match("^(%d%d%d)(%d+)KT$")
    if dir then
      return tonumber(dir), tonumber(spd), nil, false
    end
    local vrb_spd_g, vrb_gust_g = tok:match("^VRB(%d+)G(%d+)KT$")
    if vrb_spd_g then
      return nil, tonumber(vrb_spd_g), tonumber(vrb_gust_g), true
    end
    local vrb_spd = tok:match("^VRB(%d+)KT$")
    if vrb_spd then
      return nil, tonumber(vrb_spd), nil, true
    end
  end
  return nil, nil, nil, false
end

local function parse_visibility(tokens)
  for i, tok in ipairs(tokens) do
    if tok:match("SM$") then
      local raw = tok
      local prev = tokens[i - 1]
      if prev and prev:match("^%d+$") and tok:match("^%d/%dSM$") then
        raw = prev .. " " .. tok
      end
      return raw:gsub("SM$", "")
    end
  end
  return nil
end

local function parse_temp_dew(tokens)
  for _, tok in ipairs(tokens) do
    local t, d = tok:match("^(M?%d%d)/(M?%d%d)$")
    if t then
      return temp_to_num(t), temp_to_num(d)
    end
  end
  return nil, nil
end

local function parse_altimeter(tokens)
  for _, tok in ipairs(tokens) do
    local a = tok:match("^A(%d%d%d%d)$")
    if a then
      return tonumber(a) / 100.0, nil
    end
    local q = tok:match("^Q(%d%d%d%d)$")
    if q then
      return nil, tonumber(q)
    end
  end
  return nil, nil
end

local function parse_clouds(tokens)
  local highest = nil
  local clear = false
  for _, tok in ipairs(tokens) do
    if tok:match("^VV") or tok == "OVX" then
      return "N_9"
    end
    if tok == "SKC" or tok == "CLR" or tok == "NSC" or tok == "NCD" or tok == "CAVOK" then
      clear = true
    end
    local cov = tok:match("^(FEW)") or tok:match("^(SCT)") or tok:match("^(BKN)") or tok:match("^(OVC)")
    if cov == "FEW" then
      highest = math.max(highest or 0, 2)
    elseif cov == "SCT" then
      highest = math.max(highest or 0, 4)
    elseif cov == "BKN" then
      highest = math.max(highest or 0, 6)
    elseif cov == "OVC" then
      highest = math.max(highest or 0, 8)
    end
  end
  if highest then return "N_" .. tostring(highest) end
  if clear then return "N_0" end
  return "N_Slash"
end

local PHENOMENA = {
  "DZ", "RA", "SN", "SG", "IC", "PL", "GR", "GS", "UP",
  "BR", "FG", "FU", "VA", "DU", "SA", "HZ", "PY", "PO",
  "SQ", "FC", "SS", "DS",
}

local function has_any(list, s)
  for _, code in ipairs(list) do
    if s:find(code, 1, true) then
      return true
    end
  end
  return false
end

local function is_wx_token(tok)
  if tok == "RMK" or tok == "NOSIG" or tok == "AUTO" or tok == "COR" then
    return false
  end
  if tok:match("^%d%d%d%d%d?Z$") or tok:match("KT$") or tok:match("SM$") then
    return false
  end
  if tok:match("^(M?%d%d)/(M?%d%d)$") then return false end
  if tok:match("^A%d%d%d%d$") or tok:match("^Q%d%d%d%d$") then return false end
  if tok:match("^(FEW|SCT|BKN|OVC|VV|OVX|SKC|CLR|NSC|NCD)") then return false end
  if tok:match("^R%d%d") then return false end
  local t = tok
  if t:sub(1, 1) == "+" or t:sub(1, 1) == "-" then
    t = t:sub(2)
  end
  if t:sub(1, 2) == "VC" then
    t = t:sub(3)
  end
  if t:find("TS", 1, true) then return true end
  if not t:match("%a") then return false end
  return has_any(PHENOMENA, t)
end

local function parse_wx_tokens(tokens)
  local out = {}
  for _, tok in ipairs(tokens) do
    if is_wx_token(tok) then
      out[#out + 1] = tok
    end
  end
  return out
end

local function parse_rmk(tokens)
  local rmk = { slp = nil, tend_a = nil, tend_ppp = nil, precip_1h_in = nil }
  for _, tok in ipairs(tokens) do
    local slp = tok:match("^SLP(%d%d%d)$")
    if slp then rmk.slp = slp end
    local a, ppp = tok:match("^5(%d)(%d%d%d)$")
    if a then
      rmk.tend_a = tonumber(a)
      rmk.tend_ppp = tonumber(ppp)
    end
    local precip = tok:match("^P(%d%d%d%d)$")
    if precip then
      rmk.precip_1h_in = tonumber(precip) / 100.0
    end
  end
  return rmk
end

local function split_rmk(tokens)
  local main = {}
  local rmk = {}
  local in_rmk = false
  for _, tok in ipairs(tokens) do
    if tok == "RMK" then
      in_rmk = true
    elseif in_rmk then
      rmk[#rmk + 1] = tok
    else
      main[#main + 1] = tok
    end
  end
  return main, rmk
end

local function tendency_sign(a)
  if a == nil then return "" end
  if a >= 0 and a <= 3 then return "+" end
  if a >= 5 and a <= 8 then return "-" end
  return ""
end

local function tendency_glyph(a)
  if a == nil then return nil end
  if a >= 0 and a <= 3 then return utf8_char(0xE030) end
  if a == 4 then return utf8_char(0xE031) end
  if a >= 5 and a <= 8 then return utf8_char(0xE032) end
  return nil
end

local function wx_glyph_for(kind, intensity, token)
  if kind == "TS" then return utf8_char(0xE004) end
  if kind == "FZRA" then
    return intensity == "-" and utf8_char(0xE016) or utf8_char(0xE017)
  end
  if kind == "FZDZ" then
    return intensity == "-" and utf8_char(0xE00C) or utf8_char(0xE00D)
  end
  if kind == "SN" then
    if intensity == "-" then return utf8_char(0xE01A) end
    if intensity == "+" then return utf8_char(0xE01E) end
    return utf8_char(0xE01C)
  end
  if kind == "PL" then return utf8_char(0xE01F) end
  if kind == "RAIN" then
    if token and token:find("DZ", 1, true) and not token:find("RA", 1, true) then
      if intensity == "-" then return utf8_char(0xE007) end
      if intensity == "+" then return utf8_char(0xE00B) end
      return utf8_char(0xE009)
    end
    if token and token:find("SH", 1, true) then
      if intensity == "-" then return utf8_char(0xE020) end
      if intensity == "+" then return utf8_char(0xE022) end
      return utf8_char(0xE021)
    end
    if intensity == "-" then return utf8_char(0xE011) end
    if intensity == "+" then return utf8_char(0xE015) end
    return utf8_char(0xE013)
  end
  if kind == "FG" or kind == "BR" then return utf8_char(0xE003) end
  if kind == "HZ" then
    if token and token:find("FU", 1, true) then return utf8_char(0xE000) end
    return utf8_char(0xE001)
  end
  return nil
end

local function classify_wx_token(tok)
  local intensity
  local t = tok
  local first = t:sub(1, 1)
  if first == "+" or first == "-" then
    intensity = first
    t = t:sub(2)
  end
  if t:sub(1, 2) == "VC" then
    t = t:sub(3)
  end
  if t:find("TS", 1, true) then
    return { rank = 1, kind = "TS", intensity = intensity, token = t }
  end
  if t:find("FZRA", 1, true) or (t:find("FZ", 1, true) and t:find("RA", 1, true)) then
    return { rank = 2, kind = "FZRA", intensity = intensity, token = t }
  end
  if t:find("FZDZ", 1, true) or (t:find("FZ", 1, true) and t:find("DZ", 1, true)) then
    return { rank = 2, kind = "FZDZ", intensity = intensity, token = t }
  end
  if t:find("SN", 1, true) then
    return { rank = 3, kind = "SN", intensity = intensity, token = t }
  end
  if t:find("PL", 1, true) then
    return { rank = 4, kind = "PL", intensity = intensity, token = t }
  end
  if t:find("RA", 1, true) or t:find("DZ", 1, true) or t:find("SH", 1, true) then
    return { rank = 5, kind = "RAIN", intensity = intensity, token = t }
  end
  if t:find("FG", 1, true) then
    return { rank = 6, kind = "FG", intensity = intensity, token = t }
  end
  if t:find("BR", 1, true) then
    return { rank = 7, kind = "BR", intensity = intensity, token = t }
  end
  if t:find("HZ", 1, true) or t:find("FU", 1, true) then
    return { rank = 8, kind = "HZ", intensity = intensity, token = t }
  end
  return nil
end

local function select_present_weather(tokens)
  local best = nil
  for _, tok in ipairs(tokens or {}) do
    local cand = classify_wx_token(tok)
    if cand and (not best or cand.rank < best.rank) then
      best = cand
    end
  end
  if not best then return nil end
  best.glyph = wx_glyph_for(best.kind, best.intensity, best.token)
  return best
end

local function format_station_value(value)
  if value == nil or value == "" then return "/" end
  return tostring(value)
end

local function format_visibility_sm(value)
  if value == nil or value == "" then return value end

  local function decimal_from_fraction(whole, frac)
    local num, den = frac:match("^(%d+)/(%d+)$")
    if not num or tonumber(den) == 0 then return nil end
    local val = (tonumber(whole) or 0) + (tonumber(num) / tonumber(den))
    local txt = string.format("%.2f", val)
    txt = txt:gsub("0+$", ""):gsub("%.$", "")
    if txt:sub(1, 2) == "0." then
      return txt:sub(2)
    end
    return txt
  end

  local less_than = false
  local v = tostring(value)
  if v:sub(1, 1) == "M" then
    less_than = true
    v = v:sub(2)
  end

  local txt = v
  if v:match("^%d+%s+%d+/%d+$") then
    local whole, frac = v:match("^(%d+)%s+(%d+/%d+)$")
    txt = decimal_from_fraction(whole, frac) or v
  elseif v:match("^%d+/%d+$") then
    txt = decimal_from_fraction(0, v) or v
  end

  if less_than then
    return "<" .. txt
  end
  return txt
end

local function format_precip_inches(value)
  if value == nil or value == "" then return nil end
  local num = tonumber(value)
  if not num then return tostring(value) end
  local txt = string.format("%.2f", num)
  if txt:sub(1, 2) == "0." then
    return txt:sub(2)
  end
  return txt
end

local function format_pressure_hpa(value)
  if value == nil or value == "" then return nil end
  local num = tonumber(value)
  if not num then return tostring(value) end
  return string.format("%.1f", num)
end

local function format_pressure_inhg(value)
  if value == nil or value == "" then return nil end
  local num = tonumber(value)
  if not num then return tostring(value) end
  return string.format("%.2f", num)
end

local function parse_station_model(raw)
  local out = {
    raw = raw or "",
    wind_dir_deg = nil,
    wind_speed_kt = nil,
    wind_gust_kt = nil,
    wind_is_vrb = false,
    vis_sm = nil,
    temp_c = nil,
    dew_c = nil,
    altimeter_inhg = nil,
    altimeter_hpa = nil,
    cloud_code = "N_Slash",
    slp_code = nil,
    slp_code_source = nil,
    tendency_char = nil,
    tendency_dhpa = nil,
    precip_1h_in = nil,
    present_wx = nil,
  }
  if out.raw == "" then return out end
  local tokens = {}
  for tok in out.raw:gmatch("%S+") do
    tokens[#tokens + 1] = tok
  end
  local main, rmk = split_rmk(tokens)
  out.wind_dir_deg, out.wind_speed_kt, out.wind_gust_kt, out.wind_is_vrb = parse_wind(main)
  out.vis_sm = parse_visibility(main)
  out.temp_c, out.dew_c = parse_temp_dew(main)
  out.altimeter_inhg, out.altimeter_hpa = parse_altimeter(main)
  out.cloud_code = parse_clouds(main)
  out.present_wx = select_present_weather(parse_wx_tokens(main))
  local remarks = parse_rmk(rmk)
  out.slp_code = remarks.slp
  if out.slp_code then
    out.slp_code_source = "remark"
  end
  out.tendency_char = remarks.tend_a
  if remarks.tend_ppp then
    out.tendency_dhpa = remarks.tend_ppp / 10.0
  end
  out.precip_1h_in = remarks.precip_1h_in
  if not out.slp_code then
    if out.altimeter_hpa then
      out.slp_code = slp_code_from_hpa(out.altimeter_hpa)
      out.slp_code_source = "altimeter"
    elseif out.altimeter_inhg then
      out.slp_code = slp_code_from_hpa(inhg_to_hpa(out.altimeter_inhg))
      out.slp_code_source = "altimeter"
    end
  end
  return out
end

local function decode_station_model()
  local weather_codes = load_weather_codes()
  local parsed = parse_station_model(extract_ob_line(read_aviation_text("station_model") or ""))
  local cloud_glyph = nil
  if weather_codes and weather_codes.CLOUD_GLYPHS then
    cloud_glyph = weather_codes.CLOUD_GLYPHS[parsed.cloud_code or "N_Slash"]
  end
  local tendency_value = nil
  if parsed.tendency_dhpa ~= nil then
    tendency_value = string.format("%s%d", tendency_sign(parsed.tendency_char), math.floor((parsed.tendency_dhpa * 10) + 0.5))
  end
  local precip_value = nil
  if parsed.precip_1h_in ~= nil then
    precip_value = format_precip_inches(parsed.precip_1h_in)
  end
  local slp_hpa = nil
  if parsed.slp_code_source == "remark" then
    slp_hpa = hpa_from_slp_code(parsed.slp_code)
  else
    slp_hpa = parsed.altimeter_hpa or inhg_to_hpa(parsed.altimeter_inhg)
  end
  local slp_inhg = slp_hpa and hpa_to_inhg(slp_hpa) or parsed.altimeter_inhg
  return {
    station = aviation_station("station_model"),
    cloud_glyph = cloud_glyph or "---",
    wx_glyph = (parsed.present_wx and parsed.present_wx.glyph) or "",
    visibility = format_station_value(format_visibility_sm(parsed.vis_sm)),
    temp = format_station_value(parsed.temp_c),
    dew = format_station_value(parsed.dew_c),
    slp = format_station_value(parsed.slp_code),
    slp_hpa = format_station_value(format_pressure_hpa(slp_hpa)),
    slp_hpa_value = slp_hpa,
    slp_inhg = format_station_value(format_pressure_inhg(slp_inhg)),
    tendency_value = tendency_value,
    tendency_glyph = parsed.tendency_char ~= nil and (tendency_glyph(parsed.tendency_char) or "") or nil,
    precip = precip_value,
    wind_dir_deg = parsed.wind_dir_deg,
    wind_speed_kt = parsed.wind_speed_kt,
    wind_gust_kt = parsed.wind_gust_kt,
    wind_is_vrb = parsed.wind_is_vrb,
  }
end

local function wrap_lines(text, width, max_lines)
  local lines = {}
  local wrap_col = math.max(8, tonumber(width) or 42)
  local limit = math.max(1, tonumber(max_lines) or 7)

  local function emit_segment(segment)
    local s = normalize_spaces(segment)
    while s ~= "" do
      if #s <= wrap_col then
        lines[#lines + 1] = s
        return
      end

      local split = wrap_col
      for i = wrap_col, 2, -1 do
        if s:sub(i, i) == " " then
          split = i - 1
          break
        end
      end

      lines[#lines + 1] = s:sub(1, split)
      s = s:sub(split + 1):gsub("^%s+", "")
    end
  end

  local rmk_pos = text and text:find(" RMK ", 1, true) or nil
  if rmk_pos then
    emit_segment(text:sub(1, rmk_pos - 1))
    emit_segment(text:sub(rmk_pos + 1))
  else
    emit_segment(text or "")
  end

  if #lines > limit then
    lines[limit] = (lines[limit] or "") .. "..."
    while #lines > limit do
      table.remove(lines)
    end
  end

  return lines
end

local function decode_current()
  local path = weather_current_path()
  local weather_codes = load_weather_codes()
  local cloud_percent = json_number(path, ".cloud_percent // .cloud_cover_percent // .clouds.percent // .clouds.all // .current.cloud_percent // .current.cloud_cover_percent // .current.clouds.percent // .current.clouds.all // empty")
  local wx_id = json_number(path, ".wx_code // .weather_code // .weather[0].id // .current.wx_code // .current.weather_code // .current.weather[0].id // empty")
  local temp = json_number(path, ".temp_f // .temperature_f // .temp // .main.temp // .current.temp_f // .current.temperature_f // .current.temp // .current.main.temp // empty")
  local humidity = json_number(path, ".humidity_pct // .humidity // .main.humidity // .current.humidity_pct // .current.humidity // .current.main.humidity // empty")
  local wind_deg = json_number(path, ".wind_deg // .wind.direction_deg // .wind.deg // .current.wind_deg // .current.wind.direction_deg // .current.wind.deg // empty")
  local wind_speed = json_number(path, ".wind_mph // .wind_speed_mph // .wind.speed_mph // .wind.speed // .current.wind_mph // .current.wind_speed_mph // .current.wind.speed_mph // .current.wind.speed // empty")

  local cloud_info = weather_codes and weather_codes.cloud_from_percent and weather_codes.cloud_from_percent(cloud_percent) or nil
  local wx_info = weather_codes and weather_codes.wx_from_owm and weather_codes.wx_from_owm(wx_id) or nil

  return {
    sky = (cloud_info and cloud_info.glyph) or "---",
    wx = (wx_info and wx_info.glyph) or "",
    temp = temp and string.format("%03d", math.floor(temp + 0.5)) or "---",
    humidity = humidity and string.format("%03d", math.floor(humidity + 0.5)) or "---",
    wind = (wind_deg and wind_speed) and string.format(
      "%03d/%02d",
      math.floor(wind_deg + 0.5) % 360,
      math.floor(wind_speed + 0.5)
    ) or "---/--",
  }
end

read_aviation_text = function(kind)
  local json_path = aviation_current_path()
  local filter
  if kind == "metar" then
    filter = ".metar_raw // .metar // .current.metar_raw // .current.metar // empty"
  elseif kind == "station_model" then
    filter = ".station_model_raw // .metar_raw // .metar // .current.metar_raw // .current.metar // empty"
  else
    filter = ".taf_raw // .taf // .current.taf_raw // .current.taf // empty"
  end

  local value = json_query(json_path, filter)
  if value and value ~= "" then
    return value
  end

  local txt_path = string.format("%s/%s.txt", aviation_shared_dir(), kind)
  return read_file(txt_path)
end

local function decode_metar_lines()
  local cfg = current_box_cfg()
  local raw = read_aviation_text("metar") or ""
  raw = raw:gsub("\r", ""):gsub("^%s+", ""):gsub("%s+$", "")
  if raw == "" then
    return { "METAR UNAVAILABLE" }
  end

  local ob = raw:match("\nob:%s*(.-)\n") or raw:match("^ob:%s*(.-)\n") or raw
  ob = normalize_spaces(ob)
  if ob == "" then
    ob = string.format("%s METAR UNAVAILABLE", aviation_station("metar"))
  end

  return wrap_lines(
    ob,
    tonumber(cfg.metar_wrap_col) or 42,
    tonumber(cfg.metar_max_lines) or 7
  )
end

local function decode_forecast_rows()
  local path = weather_forecast_path()
  local raw = json_query(path, 'def rows: if type == "array" then . elif .days then .days elif .daily then .daily elif .forecast then .forecast else [] end; rows | .[:5] | to_entries[] | [(.key|tostring), (.value.day_name // .value.day // .value.name // ""), (.value.date_label // .value.date // .value.local_date // ""), (.value.cloud_percent // .value.cloud_cover_percent // .value.clouds.percent // .value.clouds.all // ""), (.value.wx_code // .value.weather_code // .value.weather[0].id // ""), (.value.icon // .value.icon_code // .value.weather[0].icon // ""), (.value.high_f // .value.temp_high_f // .value.high // .value.hi // .value.temp.max_f // .value.temp.max // ""), (.value.low_f // .value.temp_low_f // .value.low // .value.lo // .value.temp.min_f // .value.temp.min // "")] | @tsv')
  local rows = {}

  if raw then
    for line in raw:gmatch("[^\r\n]+") do
      local idx, day, date, cloud, wx_id, icon, hi, lo = line:match("^([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)$")
      local row_index = tonumber(idx) or #rows
      local sky, wx = forecast_glyphs(icon, cloud, wx_id)
      rows[#rows + 1] = {
        day = string.upper(day ~= "" and day or tostring(os.date("%a", os.time() + (row_index * 86400)))),
        date = forecast_date_label(row_index, date),
        sky = sky,
        wx = wx,
        high = format_temp_3(hi),
        low = format_temp_3(lo),
      }
    end
  end

  return rows
end

local function decode_taf_lines()
  local cfg = forecast_box_cfg()
  local raw = read_aviation_text("taf") or ""
  raw = raw:gsub("\r", ""):gsub("\n=%s*$", ""):gsub("\n=", "")
  if raw == "" then
    return { "TAF UNAVAILABLE" }
  end

  local one_line = raw:gsub("\n", " "):gsub("%s+", " "):gsub("%s+$", "")
  one_line = one_line:gsub("^.*%f[%w]TAF%s+", "")

  local segments = {}
  local marked = one_line
    :gsub("%s+(FM%d%d%d%d%d%d)", "\n%1")
    :gsub("%s+(TEMPO)", "\n%1")
    :gsub("%s+(PROB%d%d)", "\n%1")
    :gsub("%s+(BECMG)", "\n%1")

  for line in marked:gmatch("[^\n]+") do
    local trimmed = line:gsub("^%s+", ""):gsub("%s+$", "")
    if trimmed ~= "" then
      segments[#segments + 1] = trimmed
    end
  end

  local wrap_col = tonumber(cfg.taf_wrap_col) or 64
  local max_lines = tonumber(cfg.taf_max_lines) or 7
  local indent_cols = tonumber(cfg.taf_indent_cols) or 2
  local indent = string.rep(" ", indent_cols)
  local lines = {}

  local function emit_wrapped(text, prefix)
    local s = text
    while s ~= "" do
      local limit = wrap_col - #prefix
      if #s <= limit then
        lines[#lines + 1] = prefix .. s
        return
      end
      local split = limit
      for i = limit, 2, -1 do
        if s:sub(i, i) == " " then
          split = i - 1
          break
        end
      end
      lines[#lines + 1] = prefix .. s:sub(1, split)
      s = s:sub(split + 1):gsub("^%s+", "")
      if #lines >= max_lines then
        return
      end
      prefix = indent
    end
  end

  for i, segment in ipairs(segments) do
    emit_wrapped(segment, i == 1 and "" or indent)
    if #lines >= max_lines then
      break
    end
  end

  if #lines == 0 then
    return { "TAF UNAVAILABLE" }
  end
  if #lines > max_lines then
    lines[max_lines] = (lines[max_lines] or "") .. "..."
    while #lines > max_lines do
      table.remove(lines)
    end
  end

  return lines
end

local function refresh()
  local stamp = minute_stamp()
  if CACHE.stamp == stamp then
    return
  end

  CACHE.current = decode_current()
  CACHE.metar_lines = decode_metar_lines()
  CACHE.forecast_rows = decode_forecast_rows()
  CACHE.taf_lines = decode_taf_lines()
  CACHE.station_model = decode_station_model()
  CACHE.stamp = stamp
end

function M.status_lines()
  local owm_ts = json_timestamp(weather_status_path(), ".provider_updated_at // .generated_at // empty")
  local metar_raw = read_aviation_text("metar") or ""
  local taf_raw = read_aviation_text("taf") or ""
  local mtr_ts = metar_observation_ts(metar_raw)
  local taf_ts = taf_issue_ts(taf_raw)
  local src_line = string.format("SRC // OWM %s", format_hhmm_local(owm_ts))

  return {
    "DATA // " .. weather_data_state(),
    src_line,
    string.format("AVT // MTR %sZ | TAF %sZ", format_hhmm_utc(mtr_ts), format_hhmm_utc(taf_ts)),
  }
end

function M.current_box_title()
  return "CURRENT"
end

function M.forecast_box_title()
  return "FORECAST"
end

function M.station_model_box_title()
  return "WEATHER STATION MODEL"
end

function M.current_headers()
  return { "SKY", "WX", "TEMP", "HUM", "WIND" }
end

function M.current_row()
  refresh()
  return CACHE.current or {
    sky = "---",
    wx = "",
    temp = "---",
    humidity = "---",
    wind = "---/--",
  }
end

function M.current_metar_lines()
  refresh()
  return CACHE.metar_lines or { "METAR UNAVAILABLE" }
end

function M.forecast_headers()
  return { "DAY", "DATE", "SKY", "WX", "HIGH", "LOW" }
end

function M.forecast_rows()
  refresh()
  return CACHE.forecast_rows or {}
end

function M.forecast_taf_lines()
  refresh()
  return CACHE.taf_lines or { "TAF UNAVAILABLE" }
end

function M.station_model()
  refresh()
  return CACHE.station_model or {
    station = aviation_station("station_model"),
    cloud_glyph = "---",
    wx_glyph = "",
    visibility = "/",
    temp = "/",
    dew = "/",
    slp = "/",
    slp_hpa = "/",
    slp_hpa_value = nil,
    slp_inhg = "/",
    tendency_value = nil,
    tendency_glyph = nil,
    precip = nil,
    wind_dir_deg = nil,
    wind_speed_kt = nil,
    wind_gust_kt = nil,
    wind_is_vrb = false,
  }
end

return M
