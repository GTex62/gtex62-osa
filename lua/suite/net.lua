local M = {}
local HOME = os.getenv("HOME") or ""
local SUITE_ID = os.getenv("GTEX62_SUITE_ID") or os.getenv("GTEX62_CONKY_SUITE_ID") or "osa"
local CACHE_ROOT = os.getenv("GTEX62_CACHE_DIR") or os.getenv("GTEX62_CONKY_CACHE_DIR") or (HOME .. "/.cache/gtex62-core")
local NET_CACHE_DIR = string.format("%s/suites/%s/net", CACHE_ROOT, SUITE_ID)

local CACHE = {
  tick = nil,
  state = {},
  vlan_rows = {},
}

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

local function read_file(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return s
end

local function read_keyvals(path)
  local out = {}
  local s = read_file(path)
  if not s then
    return out
  end
  for line in s:gmatch("[^\r\n]+") do
    local key, value = line:match("^%s*([A-Za-z0-9_]+)%s*=%s*(.-)%s*$")
    if key and value then
      local numeric = tonumber(value)
      out[key] = numeric or value
    end
  end
  return out
end

local function read_tsv_rows(path)
  local rows = {}
  local s = read_file(path)
  if not s then
    return rows
  end
  for line in s:gmatch("[^\r\n]+") do
    local gateway, speed_ratio, ms = line:match("^([^\t]*)\t([^\t]*)\t([^\t]*)$")
    if gateway then
      rows[#rows + 1] = {
        gateway = gateway,
        speed_ratio = tonumber(speed_ratio) or 0,
        ms = ms ~= "" and ms or "---",
      }
    end
  end
  return rows
end

local function second_stamp()
  return os.time()
end

local function refresh_cache()
  local tick = second_stamp()
  if CACHE.tick == tick then
    return
  end

  CACHE.state = read_keyvals(NET_CACHE_DIR .. "/state.vars")
  CACHE.vlan_rows = read_tsv_rows(NET_CACHE_DIR .. "/vlan.tsv")
  CACHE.tick = tick
end

local function cached_value(key, fallback)
  refresh_cache()
  local value = CACHE.state[key]
  if value == nil or value == "" then
    return fallback
  end
  return value
end

local function parse_ping_ms(host)
  local out = command_output(
    string.format("ping -n -c1 -W1 %q 2>/dev/null | grep -o 'time=[0-9.]*' | head -n1 | cut -d= -f2", host)
  )
  return tonumber(out)
end

local function speedtest_pair()
  local suite_dir = os.getenv("CONKY_SUITE_DIR") or ((os.getenv("HOME") or "") .. "/.config/conky/gtex62-osa")
  local out = command_output(string.format("%q bars 500 0 2>/dev/null", suite_dir .. "/scripts/speedtest_snapshot.sh"))
  if not out then
    return 500, 0
  end
  local down, up = out:match("^(%d+)|(%d+)$")
  return tonumber(down) or 500, tonumber(up) or 0
end

local function conky_numeric(expr)
  if type(conky_parse) ~= "function" then
    return nil
  end

  local raw = conky_parse(expr) or ""
  raw = raw:gsub(",", ".")
  return tonumber(raw:match("(%d+%.?%d*)"))
end

local function vlan_speed_ratio(ms)
  local numeric = tonumber(ms)
  if not numeric then
    return 0
  end

  local min_ms = 0
  local max_ms = 0.5
  local clamped = math.max(min_ms, math.min(max_ms, numeric))
  return 1 - (clamped / max_ms)
end

local VLAN_GATEWAYS = {
  "192.168.10.1",
  "192.168.20.1",
  "192.168.30.1",
  "192.168.40.1",
  "192.168.50.1",
}

local function primary_iface()
  local cached_iface = cached_value("IFACE", nil)
  if cached_iface and cached_iface ~= "" then
    return cached_iface
  end

  local env_iface = os.getenv("GTEX62_NET_PRIMARY_IFACE") or os.getenv("NET_PRIMARY_IFACE")
  if env_iface and env_iface ~= "" then
    return env_iface
  end

  local route_iface = command_output(
    "ip route show default 2>/dev/null | awk '/default/ {for (i=1; i<=NF; i++) if ($i==\"dev\") {print $(i+1); exit}}'"
  )
  if route_iface and route_iface ~= "" then
    return route_iface
  end

  return "eno1"
end

function M.net_box_title()
  return normalize_spaces(tostring(cached_value("TITLE", "NIC UNKNOWN")))
end

function M.net_status_lines()
  local status = normalize_spaces(tostring(cached_value("STATUS", "OFFLINE"))):upper()
  local speed = tostring(cached_value("SPEEDTEST_DOWN", "500"))

  return {
    "GONION NETWORK // " .. status,
    "SPEEDTEST // " .. speed,
  }
end

function M.net_live_percent()
  return tonumber(cached_value("LIVE_PERCENT", 0)) or 0
end

function M.live_download_kib()
  local iface = primary_iface()
  return conky_numeric(string.format("${downspeedf %s}", iface)) or 0
end

function M.live_upload_kib()
  local iface = primary_iface()
  return conky_numeric(string.format("${upspeedf %s}", iface)) or 0
end

function M.speedtest_download_mbps()
  local down = speedtest_pair()
  return down
end

function M.speedtest_upload_mbps()
  local _, up = speedtest_pair()
  return up
end

function M.ping_1111_ms()
  return tonumber(cached_value("CF_1111_MS", 0)) or 0
end

function M.ping_8888_ms()
  return tonumber(cached_value("GOOGLE_8888_MS", 0)) or 0
end

function M.net_node_rows()
  return {
    { name = "WAN IP", value = normalize_spaces(tostring(cached_value("WAN_IP", "-"))) },
    { name = "LAN IP", value = normalize_spaces(tostring(cached_value("LAN_IP", "-"))) },
    { name = "DNS", value = normalize_spaces(tostring(cached_value("DNS", "-"))) },
    { name = "SUBNET", value = normalize_spaces(tostring(cached_value("SUBNET", "-"))) },
    { name = "GATEWAY", value = normalize_spaces(tostring(cached_value("GATEWAY", "-"))) },
  }
end

function M.vlan_rows()
  refresh_cache()
  if #CACHE.vlan_rows > 0 then
    return CACHE.vlan_rows
  end

  local rows = {}
  for _, gateway in ipairs(VLAN_GATEWAYS) do
    rows[#rows + 1] = {
      gateway = gateway,
      speed_ratio = 0,
      ms = "---",
    }
  end
  return rows
end

function M.vlan_box_title()
  return "VLAN"
end

return M
