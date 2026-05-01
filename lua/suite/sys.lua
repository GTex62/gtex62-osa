local M = {}

local HOME = os.getenv("HOME") or ""
local RUNTIME_ROOT = os.getenv("GTEX62_CONFIG_DIR") or os.getenv("GTEX62_CONKY_CONFIG_DIR") or (HOME .. "/.config/gtex62-core")
local DEFAULT_ENGINE_CACHE_ROOT = os.getenv("GTEX62_CACHE_DIR") or os.getenv("GTEX62_CONKY_CACHE_DIR") or (HOME .. "/.cache/gtex62-core")

local CACHE = {
  tick = nil,
  shared = nil,
}

local GPU_STATS_CACHE = {
  tick = nil,
  data = nil,
}

local CPU_TEMP_CACHE = {
  tick = nil,
  value = nil,
}

local PROCESS_ROWS_CACHE = {
  tick = nil,
  rows = nil,
  max_rows = nil,
  max_chars = nil,
}

local STORAGE_SPECS = {
  { label = "/ROOT", kind = "fs", path = "/" },
  { label = "/SWAP", kind = "swap", path = "swap" },
  { label = "/EFT", kind = "fs", path = "/boot/efi" },
  { label = "/NAS", kind = "mount", path = "/mnt/NAS_Data" },
  { label = "/WD", kind = "mount", path = os.getenv("WD_BLACK_PATH") or "/mnt/WD_Black" },
}

local read_gpu_stats
local fallback_cpu_temp_celsius
local fallback_gpu_temp_celsius

local function read_file(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return s
end

local function file_exists(path)
  return read_file(path) ~= nil
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

local function normalize_spaces(s)
  return (s or ""):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
end

local function second_stamp()
  return math.floor(os.time() / 5)
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

local function system_profile_id()
  return ((suite_config().profiles or {}).system) or "local"
end

local function engine_cache_root()
  local cfg = engine_config()
  return (((cfg or {}).paths or {}).cache_root) or DEFAULT_ENGINE_CACHE_ROOT
end

local function system_shared_dir()
  return string.format("%s/shared/system/%s", engine_cache_root(), system_profile_id())
end

local function shared_paths()
  local dir = system_shared_dir()
  return {
    current = dir .. "/current.json",
    status = dir .. "/status.json",
    processes = dir .. "/processes.json",
    storage = dir .. "/storage.json",
  }
end

local function first_existing_path(paths)
  for _, path in ipairs(paths) do
    if file_exists(path) then
      return path
    end
  end
  return nil
end

local function json_query(paths, filter)
  local path = first_existing_path(paths)
  if not path then
    return nil
  end

  local cmd = string.format("jq -r %q %q 2>/dev/null", filter, path)
  local out = command_output(cmd)
  if not out or out == "null" or out == "" then
    return nil
  end
  return out
end

local function json_number(paths, filter)
  return tonumber(json_query(paths, filter))
end

local function storage_fault_line(paths)
  local out = json_query(paths, [[
    def rows:
      .storage.filesystems // .filesystems // .storage.mounts // .mounts // .storage.disks // .disks // [];
    rows
    | if type == "array" then .[] else empty end
    | select((.label // .disk // "") == "/NAS" or (.label // .disk // "") == "/WD")
    | select(((.size_bytes // .bytes_total // .total_bytes // .size // 0) | tonumber) <= 0)
    | (.label // .disk // .mount // .mount_point // .path // "DISK")
  ]])

  if out then
    local label = out:match("([^\r\n]+)") or out
    label = normalize_spaces(label)
    if label ~= "" then
      return string.format("DISK // %s OFFLINE", label)
    end
  end

  return nil
end

local function gpu_tool_fault_line()
  local has_nvidia = command_output("lspci 2>/dev/null | grep -qi nvidia && echo yes")
  if not has_nvidia then
    return nil
  end

  local has_smi = command_output("command -v nvidia-smi >/dev/null 2>&1 && echo yes")
  if not has_smi then
    return "GPU // NVIDIA-SMI MISSING"
  end

  if not read_gpu_stats() then
    return "GPU // NVIDIA-SMI FAULT"
  end

  return nil
end

local function temp_fault_line(cpu_temp, gpu_temp)
  local cpu = tonumber(cpu_temp)
  local gpu = tonumber(gpu_temp)

  if cpu and cpu >= 90 then
    return string.format("TEMP // CPU %03dC HIGH", math.floor(cpu + 0.5))
  end

  if gpu and gpu >= 85 then
    return string.format("TEMP // GPU %03dC HIGH", math.floor(gpu + 0.5))
  end

  return nil
end

local function provider_fault_line(paths)
  local out = json_query(paths, "[.state, .note] | @tsv")
  if not out then
    return nil
  end

  local state, note = out:match("^([^\t]*)\t(.*)$")
  state = normalize_spaces(state)
  note = normalize_spaces(note)
  if state == "" or state == "ok" then
    return nil
  end

  if note ~= "" then
    return string.upper("SYS // " .. state .. " - " .. note)
  end
  return string.upper("SYS // " .. state)
end

local function human_size(bytes)
  local value = tonumber(bytes)
  if not value or value < 0 then
    return ""
  end

  local units = {
    { "T", 1024 ^ 4 },
    { "G", 1024 ^ 3 },
    { "M", 1024 ^ 2 },
    { "K", 1024 },
  }

  for _, unit in ipairs(units) do
    local suffix, scale = unit[1], unit[2]
    if value >= scale then
      local amount = value / scale
      if amount >= 10 then
        return string.format("%.0f%s", amount, suffix)
      end
      return string.format("%.1f%s", amount, suffix)
    end
  end

  return string.format("%.0fB", value)
end

local function format_hms(total_seconds)
  if not total_seconds then
    return "00:00"
  end
  total_seconds = math.floor(total_seconds)
  local hours = math.floor(total_seconds / 3600)
  local minutes = math.floor((total_seconds % 3600) / 60)
  return string.format("%02d:%02d", hours, minutes)
end

local function display_size(value)
  local numeric = tonumber(value)
  if numeric then
    return human_size(numeric)
  end
  return normalize_spaces(tostring(value or ""))
end

local function display_percent(value)
  local numeric = tonumber(value)
  if numeric == nil then
    return ""
  end
  return string.format("%03d", math.max(0, math.min(999, math.floor(numeric + 0.5))))
end

local function format_intel_core(model)
  local family, sku, ghz = model:match("[Cc]ore%(%u?TM%)%s*([Ii]%d)%-(%w+).-%@%s*([%d%.]+)%s*[Gg][Hh][Zz]")
  if family and sku and ghz then
    return string.upper(family) .. " " .. string.upper(sku) .. " @ " .. ghz .. "GHZ"
  end
  return nil
end

local function generic_format(model)
  local cleaned = normalize_spaces(model)
    :gsub("Intel%(R%)", "")
    :gsub("Core%(TM%)", "")
    :gsub("%s+CPU", "")
    :gsub("%s+Processor", "")
  cleaned = normalize_spaces(cleaned)
  cleaned = cleaned:gsub("%s*@%s*", " @ ")
  cleaned = cleaned:gsub("GHz", "GHZ"):gsub("ghz", "GHZ")
  return cleaned
end

local function format_gpu_model(model)
  local cleaned = normalize_spaces(model)
    :gsub("^NVIDIA%s+", "")
    :gsub("^GeForce%s+", "")
    :gsub("^NVIDIA%s+GeForce%s+", "")
  cleaned = normalize_spaces(cleaned)
  cleaned = cleaned:upper()
  cleaned = cleaned:gsub("%s+TI", "TI")
  cleaned = cleaned:gsub("%s+SUPER", "SUPER")
  return cleaned
end

local function read_cpu_model()
  local f = io.open("/proc/cpuinfo", "r")
  if not f then return nil end

  for line in f:lines() do
    local model = line:match("^model name%s*:%s*(.+)$")
    if model and model ~= "" then
      f:close()
      return model
    end
  end

  f:close()
  return nil
end

local function read_os_release()
  local f = io.open("/etc/os-release", "r")
  if not f then return {} end

  local out = {}
  for line in f:lines() do
    local k, v = line:match("^([A-Z0-9_]+)=(.+)$")
    if k and v then
      v = v:gsub('^"', ""):gsub('"$', "")
      out[k] = v
    end
  end

  f:close()
  return out
end

local function read_uptime_seconds()
  local f = io.open("/proc/uptime", "r")
  if not f then return nil end
  local line = f:read("*l") or ""
  f:close()
  return tonumber(line:match("^(%d+%.?%d*)"))
end

local function read_fs_usage(path)
  local out = command_output(string.format("df -B1 --output=size,used,avail,pcent %q 2>/dev/null | awk 'NR==2 {print $1, $2, $3, $4}'", path))
  if not out then
    return nil
  end

  local size, used, avail, pct = out:match("^(%d+)%s+(%d+)%s+(%d+)%s+(%d+)%%$")
  if not size then
    return nil
  end

  return {
    size = tonumber(size),
    used = tonumber(used),
    avail = tonumber(avail),
    pct = tonumber(pct),
  }
end

local function read_swap_usage()
  local f = io.open("/proc/meminfo", "r")
  if not f then
    return nil
  end

  local total_kib, free_kib
  for line in f:lines() do
    total_kib = total_kib or tonumber(line:match("^SwapTotal:%s+(%d+)"))
    free_kib = free_kib or tonumber(line:match("^SwapFree:%s+(%d+)"))
  end
  f:close()

  if not total_kib or total_kib <= 0 then
    return nil
  end

  local used_kib = total_kib - (free_kib or 0)
  local pct = math.floor(((used_kib / total_kib) * 100) + 0.5)

  return {
    size = total_kib * 1024,
    used = used_kib * 1024,
    avail = (free_kib or 0) * 1024,
    pct = pct,
  }
end

local function read_gpu_model()
  local smi = command_output("nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -n1")
  if smi then
    local smi_lc = smi:lower()
    if not smi_lc:match("nvidia%-smi has failed")
      and not smi_lc:match("couldn't communicate with the nvidia driver")
      and not smi_lc:match("failed because")
    then
      return smi
    end
  end

  local lspci = command_output("lspci 2>/dev/null | rg -i 'vga|3d|display' | head -n1")
  if not lspci then
    return nil
  end

  local bracketed = lspci:match("%[([^%]]+)%]")
  if bracketed and bracketed ~= "" then
    return bracketed
  end

  return lspci:match(": .-$")
end

read_gpu_stats = function()
  local now = math.floor(os.time() / 2)
  if GPU_STATS_CACHE.tick == now and GPU_STATS_CACHE.data ~= nil then
    return GPU_STATS_CACHE.data
  end

  local out = command_output(
    "nvidia-smi --query-gpu=utilization.gpu,memory.used,memory.total,temperature.gpu,driver_version,power.draw --format=csv,noheader,nounits 2>/dev/null | head -n1"
  )
  if not out then
    GPU_STATS_CACHE.tick = now
    GPU_STATS_CACHE.data = nil
    return nil
  end

  local parts = {}
  for field in out:gmatch("([^,]+)") do
    parts[#parts + 1] = normalize_spaces(field)
  end

  local data = {
    util = tonumber(parts[1]),
    mem_used = tonumber(parts[2]),
    mem_total = tonumber(parts[3]),
    temp = tonumber(parts[4]),
    driver = parts[5],
    power = tonumber(parts[6]),
  }

  GPU_STATS_CACHE.tick = now
  GPU_STATS_CACHE.data = data
  return data
end

local function fallback_cpu_box_title()
  local model = read_cpu_model()
  if not model then
    return "CPU MODEL UNKNOWN"
  end

  local intel = format_intel_core(model)
  if intel then
    return intel
  end

  return generic_format(model)
end

local function fallback_gpu_box_title()
  local model = read_gpu_model()
  if not model then
    return "GPU MODEL UNKNOWN"
  end
  return format_gpu_model(model)
end

local function fallback_footer_lines()
  local board = command_output("cat /sys/class/dmi/id/board_name 2>/dev/null") or "UNKNOWN"
  local bios = command_output("cat /sys/class/dmi/id/bios_version 2>/dev/null") or "UNKNOWN"

  return {
    "MBD // " .. normalize_spaces(board),
    "BIOS // " .. normalize_spaces(bios),
  }
end

local function fallback_storage_rows()
  local rows = {}

  for _, spec in ipairs(STORAGE_SPECS) do
    local usage
    if spec.kind == "swap" then
      usage = read_swap_usage()
    else
      usage = read_fs_usage(spec.path)
    end

    rows[#rows + 1] = {
      disk = spec.label,
      size = usage and human_size(usage.size) or "",
      used = usage and human_size(usage.used) or "",
      avail = usage and human_size(usage.avail) or "",
      use_pct = usage and display_percent(usage.pct) or "",
    }
  end

  rows[#rows + 1] = {
    disk = "",
    size = "",
    used = "",
    avail = "",
    use_pct = "",
  }

  return rows
end

local function fallback_status_lines()
  local osr = read_os_release()
  local codename = (osr.VERSION_CODENAME or osr.UBUNTU_CODENAME or "unknown"):upper()
  local version = osr.VERSION_ID or "?.?"
  local kernel = command_output("uname -r") or "UNKNOWN"
  kernel = kernel:gsub("%-generic$", "-G")
  local uptime = format_hms(read_uptime_seconds())
  local condition = temp_fault_line(fallback_cpu_temp_celsius(), fallback_gpu_temp_celsius())
    or gpu_tool_fault_line()

  return {
    "OS LM // " .. codename .. " " .. version,
    "KERNEL // " .. kernel,
    condition or ("UPTIME // " .. uptime),
  }
end

local function fallback_cpu_usage_percent()
  if type(conky_parse) == "function" then
    local value = tonumber((conky_parse("${cpu}") or ""):match("(%d+%.?%d*)"))
    if value ~= nil then
      return value
    end
  end
  return nil
end

local function fallback_ram_usage_percent()
  if type(conky_parse) == "function" then
    local value = tonumber((conky_parse("${memperc}") or ""):match("(%d+%.?%d*)"))
    if value ~= nil then
      return value
    end
  end
  return nil
end

fallback_cpu_temp_celsius = function()
  local now = math.floor(os.time() / 2)
  if CPU_TEMP_CACHE.tick == now then
    return CPU_TEMP_CACHE.value
  end

  local value = nil
  local sensors = command_output("sensors 2>/dev/null")
  if sensors then
    local core_sum = 0
    local core_count = 0

    for temp in sensors:gmatch("Core%s+%d+:%s*%+?(%d+%.?%d*)") do
      local numeric = tonumber(temp)
      if numeric then
        core_sum = core_sum + numeric
        core_count = core_count + 1
      end
    end

    if core_count > 0 then
      value = core_sum / core_count
      CPU_TEMP_CACHE.tick = now
      CPU_TEMP_CACHE.value = value
      return value
    end

    for _, pattern in ipairs({
      "Package id 0:%s*%+?(%d+%.?%d*)",
      "Tctl:%s*%+?(%d+%.?%d*)",
      "Tdie:%s*%+?(%d+%.?%d*)",
      "CPU Temp:%s*%+?(%d+%.?%d*)",
    }) do
      local match = sensors:match(pattern)
      if match then
        value = tonumber(match)
        CPU_TEMP_CACHE.tick = now
        CPU_TEMP_CACHE.value = value
        return value
      end
    end
  end

  if type(conky_parse) == "function" then
    value = tonumber((conky_parse("${hwmon temp 1}") or ""):match("(%d+%.?%d*)"))
    if value ~= nil then
      CPU_TEMP_CACHE.tick = now
      CPU_TEMP_CACHE.value = value
      return value
    end
  end

  CPU_TEMP_CACHE.tick = now
  CPU_TEMP_CACHE.value = nil
  return nil
end

local function fallback_gpu_usage_percent()
  local stats = read_gpu_stats()
  return stats and stats.util or nil
end

local function fallback_gpu_vram_percent()
  local stats = read_gpu_stats()
  if not stats or not stats.mem_used or not stats.mem_total or stats.mem_total <= 0 then
    return nil
  end
  return (stats.mem_used * 100) / stats.mem_total
end

fallback_gpu_temp_celsius = function()
  local stats = read_gpu_stats()
  return stats and stats.temp or nil
end

local function fallback_gpu_component_rows()
  local stats = read_gpu_stats()
  if not stats then
    return {}
  end

  local rows = {}
  if stats.driver and stats.driver ~= "" then
    rows[#rows + 1] = {
      name = "DRIVER",
      value = stats.driver,
    }
  end

  if stats.power ~= nil then
    rows[#rows + 1] = {
      name = "POWER",
      value = string.format("%.2fW", stats.power),
    }
  end

  return rows
end

local function fallback_process_rows(max_rows, max_chars)
  local rows = {}
  local target_rows = tonumber(max_rows) or 6
  local max_len = tonumber(max_chars) or 18
  if type(conky_parse) == "function" then
    for i = 1, target_rows do
      local raw_name = conky_parse(string.format("${top name %d}", i)) or ""
      local raw_pct = conky_parse(string.format("${top cpu %d}", i)) or ""
      local name = normalize_spaces(raw_name)
      local pct = tonumber((raw_pct:gsub("%s+", "")):match("(%d+%.?%d*)"))

      if name ~= "" and pct ~= nil then
        if #name > max_len then
          name = name:sub(1, max_len)
        end
        rows[#rows + 1] = {
          name = name:upper(),
          pct = string.format("%.2f", pct),
        }
      end
    end
    return rows
  end

  local out = command_output("ps -eo comm=,pcpu= --sort=-pcpu | head -n 40")
  if not out then
    return rows
  end

  for line in out:gmatch("[^\n]+") do
    local name, pct = line:match("^%s*(.-)%s+([%d%.]+)%s*$")
    local numeric = tonumber(pct)
    if name and name ~= "" and numeric then
      if name ~= "ps" and name ~= "head" and name ~= "bash" then
        name = normalize_spaces(name)
        if #name > max_len then
          name = name:sub(1, max_len)
        end
        rows[#rows + 1] = {
          name = name:upper(),
          pct = string.format("%.2f", numeric),
        }
        if #rows >= target_rows then
          break
        end
      end
    end
  end

  return rows
end

local function decode_storage_row(paths, spec)
  local filter
  if spec.kind == "swap" then
    filter = [[
      def swap_row:
        .storage.swap // .swap //
        ((.storage.filesystems // .filesystems // .storage.mounts // .mounts // [])
          | if type == "array" then map(select((.kind // .type // "") == "swap"))[0] else empty end);
      swap_row
      | if . == null then empty else [(.size_bytes // .bytes_total // .total_bytes // .size // ""), (.used_bytes // .bytes_used // .used // ""), (.avail_bytes // .bytes_available // .available // .avail // ""), (.use_percent // .used_percent // .pct // .percent // "")] | @tsv end
    ]]
  else
    filter = string.format([[
      def rows:
        .storage.filesystems // .filesystems // .storage.mounts // .mounts // .storage.disks // .disks // [];
      rows
      | if type == "array" then map(select((.mount // .mount_point // .path // .target // "") == %q))[0] else empty end
      | if . == null then empty else [(.size_bytes // .bytes_total // .total_bytes // .size // ""), (.used_bytes // .bytes_used // .used // ""), (.avail_bytes // .bytes_available // .available // .avail // ""), (.use_percent // .used_percent // .pct // .percent // "")] | @tsv end
    ]], spec.path)
  end

  local out = json_query(paths, filter)
  if not out then
    return {
      disk = spec.label,
      size = "",
      used = "",
      avail = "",
      use_pct = "",
    }
  end

  local size, used, avail, pct = out:match("^([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)$")
  return {
    disk = spec.label,
    size = display_size(size),
    used = display_size(used),
    avail = display_size(avail),
    use_pct = display_percent(pct),
  }
end

local function decode_process_rows(paths)
  local out = json_query(paths, [[
    def rows:
      .cpu.top_processes // .processes.top_cpu // .processes // .top_cpu // [];
    rows
    | if type == "array" then .[:12] else [] end
    | .[]
    | [(.name // .process // .command // ""), (.cpu_percent // .usage_percent // .percent // .value // "")]
    | @tsv
  ]])

  local rows = {}
  if not out then
    return rows
  end

  for line in out:gmatch("[^\r\n]+") do
    local name, pct = line:match("^([^\t]*)\t([^\t]*)$")
    local numeric = tonumber(pct)
    name = normalize_spaces(name)
    if name ~= "" and numeric ~= nil then
      rows[#rows + 1] = {
        name = string.upper(name),
        pct = string.format("%.2f", numeric),
      }
    end
  end

  return rows
end

local function build_shared_snapshot()
  local paths = shared_paths()
  local json_paths = { paths.current, paths.status }
  local process_paths = { paths.processes, paths.current }
  local storage_paths = { paths.storage, paths.current }
  local has_shared = first_existing_path({
    paths.current,
    paths.status,
    paths.processes,
    paths.storage,
  }) ~= nil

  local snapshot = {
    available = has_shared,
  }

  if not has_shared then
    return snapshot
  end

  local cpu_model = json_query(json_paths, ".cpu.model // .cpu.name // .hardware.cpu.model // empty")
  if cpu_model then
    snapshot.cpu_box_title = generic_format(cpu_model)
  end

  local gpu_model = json_query(json_paths, ".gpu.model // .gpu.name // .hardware.gpu.model // empty")
  if gpu_model then
    snapshot.gpu_box_title = format_gpu_model(gpu_model)
  end

  snapshot.cpu_usage_percent = json_number(json_paths, ".cpu.usage_percent // .cpu.usage.percent // .cpu.percent // empty")
  snapshot.ram_usage_percent = json_number(json_paths, ".memory.usage_percent // .memory.used_percent // .memory.percent // .ram.usage_percent // .ram.percent // empty")
  snapshot.cpu_temp_celsius = json_number(json_paths, ".cpu.temperature_c // .cpu.temp_c // .cpu.temperature_celsius // .cpu.temperatures.avg_c // .cpu.temperatures.package_c // empty")
  snapshot.gpu_usage_percent = json_number(json_paths, ".gpu.usage_percent // .gpu.utilization_percent // .gpu.util_percent // empty")
  snapshot.gpu_temp_celsius = json_number(json_paths, ".gpu.temperature_c // .gpu.temp_c // .gpu.temperature_celsius // empty")
  snapshot.gpu_vram_percent = json_number(json_paths, ".gpu.vram_percent // .gpu.memory.percent // .gpu.memory_usage_percent // empty")

  if snapshot.gpu_vram_percent == nil then
    local gpu_vram_used = json_number(json_paths, ".gpu.memory.used_mb // .gpu.vram_used_mb // .gpu.memory.used // empty")
    local gpu_vram_total = json_number(json_paths, ".gpu.memory.total_mb // .gpu.vram_total_mb // .gpu.memory.total // empty")
    if gpu_vram_used and gpu_vram_total and gpu_vram_total > 0 then
      snapshot.gpu_vram_percent = (gpu_vram_used * 100) / gpu_vram_total
    end
  end

  local driver = json_query(json_paths, ".gpu.driver_version // .gpu.driver // empty")
  local power_w = json_number(json_paths, ".gpu.power_w // .gpu.power.draw_w // .gpu.power.draw // empty")
  snapshot.gpu_component_rows = {}
  if driver then
    snapshot.gpu_component_rows[#snapshot.gpu_component_rows + 1] = {
      name = "DRIVER",
      value = driver,
    }
  end
  if power_w ~= nil then
    snapshot.gpu_component_rows[#snapshot.gpu_component_rows + 1] = {
      name = "POWER",
      value = string.format("%.2fW", power_w),
    }
  end

  local board = json_query(json_paths, ".motherboard.name // .board.name // .hardware.board.name // empty")
  local bios = json_query(json_paths, ".bios.version // .firmware.bios.version // empty")
  snapshot.footer_lines = {
    "MBD // " .. (board and normalize_spaces(board) or "UNKNOWN"),
    "BIOS // " .. (bios and normalize_spaces(bios) or "UNKNOWN"),
  }

  local codename = json_query(json_paths, ".os.codename // .os.version_codename // .distribution.codename // empty")
  local version = json_query(json_paths, ".os.version_id // .os.version // .distribution.version // empty")
  local os_name = json_query(json_paths, ".os.name // .os.pretty_name // .distribution.name // .distribution.pretty_name // empty")
  local kernel = json_query(json_paths, ".kernel.release // .kernel.version // .os.kernel // empty")
  local uptime_seconds = json_number(json_paths, ".uptime_seconds // .uptime.seconds // .system.uptime_seconds // empty")
  local condition = provider_fault_line({ paths.status })
    or storage_fault_line(storage_paths)
    or temp_fault_line(snapshot.cpu_temp_celsius or fallback_cpu_temp_celsius(), snapshot.gpu_temp_celsius or fallback_gpu_temp_celsius())
    or gpu_tool_fault_line()

  local os_label
  if codename or version then
    os_label = string.format(
      "%s %s",
      string.upper(codename or "UNKNOWN"),
      normalize_spaces(version or "")
    ):gsub("%s+$", "")
  elseif os_name then
    os_label = string.upper(normalize_spaces(os_name))
  else
    os_label = "UNKNOWN"
  end

  snapshot.status_lines = {
    "OS LM // " .. os_label,
    "KERNEL // " .. normalize_spaces(kernel or "UNKNOWN"),
    condition or ("UPTIME // " .. format_hms(uptime_seconds)),
  }

  snapshot.process_rows = decode_process_rows(process_paths)
  snapshot.storage_rows = {}
  for _, spec in ipairs(STORAGE_SPECS) do
    snapshot.storage_rows[#snapshot.storage_rows + 1] = decode_storage_row(storage_paths, spec)
  end
  snapshot.storage_rows[#snapshot.storage_rows + 1] = {
    disk = "",
    size = "",
    used = "",
    avail = "",
    use_pct = "",
  }

  return snapshot
end

local function shared_snapshot()
  local tick = second_stamp()
  if CACHE.tick ~= tick then
    CACHE.shared = build_shared_snapshot()
    CACHE.tick = tick
  end
  return CACHE.shared or { available = false }
end

function M.cpu_box_title()
  local shared = shared_snapshot()
  return shared.cpu_box_title or fallback_cpu_box_title()
end

function M.gpu_box_title()
  local shared = shared_snapshot()
  return shared.gpu_box_title or fallback_gpu_box_title()
end

function M.gpu_usage_percent()
  return fallback_gpu_usage_percent()
end

function M.gpu_vram_percent()
  return fallback_gpu_vram_percent()
end

function M.gpu_temp_celsius()
  return fallback_gpu_temp_celsius()
end

function M.gpu_component_rows()
  local shared = shared_snapshot()
  if shared.gpu_component_rows and #shared.gpu_component_rows > 0 then
    local merged = {}
    local seen = {}

    for _, row in ipairs(shared.gpu_component_rows) do
      local name = normalize_spaces(row.name or "")
      if name ~= "" then
        merged[#merged + 1] = row
        seen[name] = true
      end
    end

    for _, row in ipairs(fallback_gpu_component_rows()) do
      local name = normalize_spaces(row.name or "")
      if name ~= "" and not seen[name] then
        merged[#merged + 1] = row
        seen[name] = true
      end
    end

    return merged
  end
  return fallback_gpu_component_rows()
end

function M.storage_box_title()
  return "STORAGE"
end

function M.footer_lines()
  local shared = shared_snapshot()
  if shared.footer_lines then
    return shared.footer_lines
  end
  return fallback_footer_lines()
end

function M.storage_rows()
  local shared = shared_snapshot()
  if shared.storage_rows and #shared.storage_rows > 0 then
    return shared.storage_rows
  end
  return fallback_storage_rows()
end

function M.status_lines()
  local shared = shared_snapshot()
  if shared.status_lines then
    return shared.status_lines
  end
  return fallback_status_lines()
end

function M.cpu_usage_percent()
  return fallback_cpu_usage_percent()
end

function M.ram_usage_percent()
  return fallback_ram_usage_percent()
end

function M.cpu_temp_celsius()
  return fallback_cpu_temp_celsius()
end

function M.process_rows(max_rows, max_chars)
  local target_rows = tonumber(max_rows) or 6
  local max_len = tonumber(max_chars) or 18
  local tick = math.floor(os.time() / 3)

  if PROCESS_ROWS_CACHE.tick == tick
    and PROCESS_ROWS_CACHE.rows ~= nil
    and PROCESS_ROWS_CACHE.max_rows == target_rows
    and PROCESS_ROWS_CACHE.max_chars == max_len then
    return PROCESS_ROWS_CACHE.rows
  end

  PROCESS_ROWS_CACHE.tick = tick
  PROCESS_ROWS_CACHE.max_rows = target_rows
  PROCESS_ROWS_CACHE.max_chars = max_len
  PROCESS_ROWS_CACHE.rows = fallback_process_rows(target_rows, max_len)
  return PROCESS_ROWS_CACHE.rows
end

return M
