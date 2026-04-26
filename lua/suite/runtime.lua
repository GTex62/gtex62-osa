local M = {}

local HOME = os.getenv("HOME") or ""
local SUITE_DIR = os.getenv("CONKY_SUITE_DIR") or (HOME .. "/.config/conky/gtex62-osa")

local PATHS = {
  theme = SUITE_DIR .. "/theme/osa-theme.lua",
  layout = SUITE_DIR .. "/theme/osa-layout.lua",
  panels = SUITE_DIR .. "/theme/panels.lua",
}

local CACHE = {
  theme = nil,
  layout = nil,
  panels = nil,
  mtimes = {},
  last_check = nil,
}

local function file_mtime(path)
  local candidates = {
    string.format("stat -c %%Y %q 2>/dev/null", path),
    string.format("stat -f %%m %q 2>/dev/null", path),
  }

  for _, cmd in ipairs(candidates) do
    local p = io.popen(cmd, "r")
    if p then
      local out = p:read("*a") or ""
      p:close()
      local mtime = tonumber(out:match("(%d+)"))
      if mtime ~= nil then
        return mtime
      end
    end
  end

  return nil
end

local function safe_dofile(path)
  local ok, value = pcall(dofile, path)
  if ok and type(value) == "table" then
    return value
  end
  return nil
end

local function load_key(key)
  local path = PATHS[key]
  local value = safe_dofile(path)
  if value ~= nil then
    CACHE[key] = value
    CACHE.mtimes[key] = file_mtime(path)
  end
end

local function refresh_if_needed()
  local now = os.time()
  if CACHE.last_check == now then
    return
  end
  CACHE.last_check = now

  for key, path in pairs(PATHS) do
    if CACHE[key] == nil then
      load_key(key)
    else
      local mtime = file_mtime(path)
      if mtime ~= nil and mtime ~= CACHE.mtimes[key] then
        load_key(key)
      end
    end
  end
end

function M.get_state()
  refresh_if_needed()
  return {
    theme = CACHE.theme or {},
    layout = CACHE.layout or {},
    panels = CACHE.panels or {},
  }
end

return M
