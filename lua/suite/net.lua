local M = {}
local HOME = os.getenv("HOME") or ""
local SUITE_ID = os.getenv("GTEX62_SUITE_ID") or os.getenv("GTEX62_CONKY_SUITE_ID") or "osa"
local CACHE_ROOT = os.getenv("GTEX62_CACHE_DIR") or os.getenv("GTEX62_CONKY_CACHE_DIR") or (HOME .. "/.cache/gtex62-core")
local NET_CACHE_DIR
local RUNTIME_ROOT = os.getenv("GTEX62_CONFIG_DIR") or os.getenv("GTEX62_CONKY_CONFIG_DIR") or (HOME .. "/.config/gtex62-core")
local CORE_DIR = os.getenv("GTEX62_CORE_DIR") or os.getenv("GTEX62_CONKY_ENGINE_DIR") or (HOME .. "/.config/conky/gtex62-core")
local SUITE_DIR = os.getenv("CONKY_SUITE_DIR") or (HOME .. "/.config/conky/gtex62-osa")

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

local function screenshot_override(key)
  local ok, theme = pcall(dofile, SUITE_DIR .. "/theme/osa-theme.lua")
  if not ok or type(theme) ~= "table" then
    return nil
  end

  local value = ((theme.screenshot or {})[key])
  value = normalize_spaces(tostring(value or ""))
  if value ~= "" then
    return value
  end
  return nil
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

local function connectivity_profile_id()
  local cfg = parse_simple_toml(RUNTIME_ROOT .. "/suites/" .. SUITE_ID .. ".toml")
  return ((cfg.profiles or {}).connectivity) or "default"
end

local function net_cache_dir()
  if not NET_CACHE_DIR then
    local cfg = parse_simple_toml(RUNTIME_ROOT .. "/suites/" .. SUITE_ID .. ".toml")
    local profile = ((cfg.profiles or {}).net) or "local"
    NET_CACHE_DIR = string.format("%s/shared/net/%s", CACHE_ROOT, profile)
  end
  return NET_CACHE_DIR
end

local function json_query(path, filter)
  if not read_file(path) then return nil end
  return command_output(string.format("jq -r %q %q 2>/dev/null", filter, path))
end

local function second_stamp()
  return os.time()
end

local function refresh_cache()
  local tick = second_stamp()
  if CACHE.tick == tick then
    return
  end

  CACHE.state = read_keyvals(net_cache_dir() .. "/state.vars")
  CACHE.vlan_rows = read_tsv_rows(net_cache_dir() .. "/vlan.tsv")
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
  local path = string.format("%s/shared/connectivity/%s/current.json", CACHE_ROOT, connectivity_profile_id())
  local out = json_query(path, '[.speedtest.display_down_mbps // .speedtest.download_mbps // 500, .speedtest.upload_mbps // 0] | @tsv')
  if out then
    local down, up = out:match("^([^\t]+)\t([^\t]+)$")
    if down then
      return tonumber(down) or 500, tonumber(up) or 0
    end
  end

  local out = command_output(string.format("%q bars 500 0 2>/dev/null", CORE_DIR .. "/providers/connectivity/speedtest_snapshot.sh"))
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
  local speed_age = tostring(cached_value("SPEEDTEST_AGE", cached_value("SPEEDTEST_DAYS", "--:--")))
  local speed_delta = tostring(cached_value("SPEEDTEST_DELTA", "---"))
  local ssh_tripped = tostring(cached_value("SSH_TRIPPED", "0"))
  local speed_line = string.format("%s | %s | %s", speed, speed_age, speed_delta)

  if ssh_tripped == "1" then
    local reason = normalize_spaces(tostring(cached_value("SSH_REASON", "PF_SSH_FAIL")))
    local left = normalize_spaces(tostring(cached_value("SSH_LEFT", "0")))
    return {
      string.format("SSH PAUSED - %s - %ss", reason ~= "" and reason or "PF_SSH_FAIL", left ~= "" and left or "0"),
      "GONION NETWORK // " .. status,
    }
  end

  return {
    "GONION NETWORK // " .. status,
    "SPEEDTEST // " .. speed_line,
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
  local wan_ip = screenshot_override("wan_ip") or normalize_spaces(tostring(cached_value("WAN_IP", "-")))
  local wan_label = normalize_spaces(tostring(cached_value("VPN_STATE", "UNKNOWN"))) == "ON" and "VPN IP" or "WAN IP"
  return {
    { name = wan_label, value = wan_ip },
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
