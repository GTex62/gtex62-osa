-- See run-tests.sh. Each case builds a fresh env.lua instance at a faked clock position.
local SC = os.getenv("SC")
local ENV_LUA = os.getenv("CONKY_SUITE_DIR") .. "/lua/suite/env.lua"
local passes, fails = 0, 0
local function check(label, cond, detail)
  if cond then passes = passes + 1; print("[PASS] " .. label)
  else fails = fails + 1; print("[FAIL] " .. label .. (detail and (" - " .. tostring(detail)) or "")) end
end
local real_time = os.time
local function write(path, s) local f = assert(io.open(path, "w")); f:write(s); f:close() end
local iso = function(ts) return os.date("!%Y-%m-%dT%H:%M:%SZ", ts) end

-- ---------------------------------------------------------------- fixtures
local function set_suite(bound)
  write(SC .. "/cfg/suites/osa.toml", '[profiles]\nair = "home"\nsolar = "home"\n' .. (bound and 'airgradient = "indoor"\n' or ''))
end
local function air_files(provider_pm, raw_rows, air_state)
  local now = real_time()
  local vals = provider_pm and ('{"pm2_5":' .. provider_pm .. '}') or '{}'
  write(SC .. "/cache/shared/air/home/current.json", string.format(
    '{"generated_at":"%s","provider_updated_at":"%s","airnow":{"aqi":43,"values":%s},"openweather":{"aqi":2},' ..
    '"selected":{"pm2_5":%s,"o3":50,"pm10":14,"no2":7,"so2":1,"co":200,"nh3":2}}',
    iso(now), iso(now), vals, provider_pm or 13.3))
  local parts = {}
  for _, r in ipairs(raw_rows or {}) do
    parts[#parts + 1] = string.format('{"Parameter":"PM2.5","UTC":"%s","Value":%s,"RawConcentration":%s,"Unit":"UG/M3"}',
      os.date("!%Y-%m-%dT%H:%M", now - r.age), r.value, r.raw)
  end
  write(SC .. "/cache/shared/air/home/raw_airnow_data.json", "[" .. table.concat(parts, ",") .. "]")
  write(SC .. "/cache/shared/air/home/status.json", air_state or '{"state":"ok"}')
  write(SC .. "/cache/shared/solar/home/current.json",
    '{"provider_updated_at":"' .. iso(now) .. '","norm":{"UV":0.1,"RAD":0.2},"values":{"UV":2.9,"RAD":457},"meta":{"uv_source":"open-meteo"}}')
  write(SC .. "/cache/shared/solar/home/status.json", '{"state":"ok"}')
end
local TREND_FROM_HA = false
local function trend_json(t)
  if not t then return "" end
  local parts = {}
  for _, k in ipairs({"co2_ppm", "pm25_ugm3", "pm10_ugm3", "pm1_ugm3", "pm03_per_dl", "voc_index", "nox_index"}) do
    local v = t[k] or {}
    parts[#parts + 1] = string.format('"%s":{"h1_pct":%s,"h24_pct":%s}', k, v[1] == nil and "null" or tostring(v[1]), v[2] == nil and "null" or tostring(v[2]))
  end
  return ',"trend":{' .. table.concat(parts, ",") .. '},"trend_from_ha":' .. tostring(TREND_FROM_HA)
end

local function notices_json(list)
  if not list then return "" end
  local parts = {}
  for _, text in ipairs(list) do parts[#parts + 1] = string.format('{"type":"x","text":"%s"}', text) end
  return ',"notices":[' .. table.concat(parts, ",") .. "]"
end

local function ag_status(o)
  o = o or {}
  local now = real_time()
  local gen = o.gen_age and (now - o.gen_age) or (now - 5)
  write(SC .. "/cache/shared/airgradient/indoor/status.json", string.format(
    [[{"state":"%s","label":"%s","generated_at":%s,"co2_ppm":%s,"pm":{"pm03_per_dl":%s,"pm1_ugm3":%s,"pm25_ugm3":%s,"pm10_ugm3":%s},"voc_index":%s,"nox_index":%s,"ventilation":{"alert_visible":%s,"alert_text":"%s"}%s}]],
    o.state or "ok", o.label or "CAVE", o.no_gen and "null" or ('"' .. iso(gen) .. '"'),
    o.co2 or 482, o.pm03 or 500, o.pm1 or 4.4, o.pm25 or 4.9, o.pm10 or 7.1, o.voc or 22, o.nox or 3,
    o.alert and "true" or "false", o.alert or "", trend_json(o.trend) .. notices_json(o.notices)))
end

local base = math.floor(real_time() / 30) * 30
local base60 = math.floor(real_time() / 60) * 60
local function load_env(phase, cfg, b)
  b = b or base
  os.time = function() return b + phase end
  local E = dofile(ENV_LUA)
  if cfg ~= nil then E.configure(cfg) end
  return E
end

air_files()

-- ---------------------------------------------------------------- not bound: exactly the old behavior
set_suite(false); ag_status()
local E = load_env(20)
check("unbound: title POLLUTION, outdoor first row, DATA/SRC lines unchanged",
  E.pollution_title() == "POLLUTION" and E.pollution_rows()[1].label == "PM 2.5"
  and E.status_lines()[1] == "DATA // NOMINAL" and E.status_lines()[2]:match("^SRC // OWM BASE") ~= nil, E.status_lines()[1])
set_suite(true)

-- ---------------------------------------------------------------- rotation, rows, scaling
ag_status()
for _, ph in ipairs({0, 7, 14}) do check("phase " .. ph .. ": outdoor", load_env(ph).pollution_title() == "POLLUTION") end
for _, ph in ipairs({15, 22, 29}) do check("phase " .. ph .. ": indoor", load_env(ph).pollution_title() == "INDOOR", load_env(ph).pollution_title()) end
E = load_env(20)
local rows = E.pollution_rows()
local want = {{"CO2 (PPM)", "482"}, {"PM 2.5", "4.90"}, {"PM 10", "7.10"},
  {"PM 1", "4.40"}, {"PM 0.3 (/DL)", "500"}, {"VOC INDEX", "22"}, {"NOX INDEX", "3"}}
check("seven indoor rows", #rows == 7)
for i, w in ipairs(want) do check("row " .. i .. " " .. w[1] .. " = " .. w[2], rows[i].label == w[1] and rows[i].value == w[2], rows[i].label .. "=" .. rows[i].value) end
for _, r in ipairs(rows) do
  check("label is short enough for the narrowed label column: " .. r.label, #r.label <= 13)
end
check("indoor SRC line and DATA line", E.status_lines()[2] == "SRC // AG CAVE" and E.status_lines()[1] == "DATA // NOMINAL")
ag_status({co2 = 1150, pm03 = 3389}); rows = load_env(20).pollution_rows()
check("CO2 1150 and PM0.3 3389 show unscaled, with a thousands separator", rows[1].value == "1,150" and rows[5].value == "3,389")
ag_status({co2 = 1999, voc = 1200, pm25 = 2500}); rows = load_env(20).pollution_rows()
check("1,999 fits; VOC 1200 and PM2.5 2500 show whole, with separators", rows[1].value == "1,999" and rows[6].value == "1,200" and rows[2].value == "2,500")
ag_status({co2 = 99999, pm03 = 99999}); rows = load_env(20).pollution_rows()
check("every row caps at 9,999", rows[1].value == "9,999" and rows[5].value == "9,999")
ag_status({pm25 = 5.274, pm10 = 99.996, pm1 = 123.456, voc = 7, nox = 0}); rows = load_env(20).pollution_rows()
check("real format: 2 decimals under 100 (5.27), 99.996 rolls to 100.0, one decimal under 1,000 (123.5)",
  rows[2].value == "5.27" and rows[3].value == "100.0" and rows[4].value == "123.5" and rows[6].value == "7" and rows[7].value == "0", rows[2].value .. " " .. rows[3].value .. " " .. rows[4].value)
ag_status({pm25 = 999.96}); check("999.96 rolls to 1,000, never 1000.0", load_env(20).pollution_rows()[2].value == "1,000")
check("no value is longer than five characters", (function() ag_status({co2 = 99999, pm25 = 99999, pm10 = 999.4, pm1 = 99.9, pm03 = 99999, voc = 99999, nox = 99999}) for _, r in ipairs(load_env(20).pollution_rows()) do if #r.value > 5 then return false end end return true end)())
ag_status({co2 = 515, pm03 = 1339}); rows = load_env(20).pollution_rows()
check("no leading zeros: 515 and 1,339", rows[1].value == "515" and rows[5].value == "1,339")
ag_status({co2 = 0}); check("CO2 0 is a value, not missing", load_env(20).pollution_rows()[1].value == "0")
write(SC .. "/cache/shared/airgradient/indoor/status.json", '{"state":"ok","generated_at":"' .. iso(real_time() - 3) .. '","label":"X","ventilation":{"alert_visible":false}}')
rows = load_env(20).pollution_rows(); check("missing readings show dashes", rows[1].value == "---" and rows[6].value == "---")
ag_status({label = ""}); E = load_env(20)
check("no label: title and SRC line lose it", E.pollution_title() == "INDOOR" and E.status_lines()[2] == "SRC // AG")

-- ---------------------------------------------------------------- trend columns
ag_status({trend = {co2_ppm = {3, -4}, pm25_ugm3 = {-12, 85}, pm10_ugm3 = {0, 0}, pm1_ugm3 = {1500, -1500}, pm03_per_dl = {nil, 7}, voc_index = {nil, nil}, nox_index = {-1, 0}}})
rows = load_env(20).pollution_rows()
check("trend cells: +3%/-4%, -12%/+85%, 0%/0%", rows[1].t1 == "+3%" and rows[1].t24 == "-4%" and rows[2].t1 == "-12%" and rows[2].t24 == "+85%" and rows[3].t1 == "0%" and rows[3].t24 == "0%",
  rows[1].t1 .. " " .. rows[1].t24 .. " " .. rows[2].t1 .. " " .. rows[2].t24)
check("trend cells: capped at +/-999%, a missing comparison is --", rows[4].t1 == "+999%" and rows[4].t24 == "-999%" and rows[5].t1 == "--" and rows[5].t24 == "+7%" and rows[6].t1 == "--" and rows[6].t24 == "--", rows[4].t1 .. " " .. rows[5].t1 .. " " .. rows[6].t24)
check("trend cells: NOx -1% and 0%", rows[7].t1 == "-1%" and rows[7].t24 == "0%")
ag_status({trend = {co2_ppm = {1, 2}}}); check("no HA data behind the trend: the SRC line is just AG CAVE", load_env(20).status_lines()[2] == "SRC // AG CAVE")
TREND_FROM_HA = true
ag_status({trend = {co2_ppm = {1, 2}}}); check("trend compared against Home Assistant history: SRC // AG CAVE | HA", load_env(20).status_lines()[2] == "SRC // AG CAVE | HA", load_env(20).status_lines()[2])
check("...but not in the outdoor view", load_env(5).status_lines()[2]:match("^SRC // OWM") ~= nil and not load_env(5).status_lines()[2]:match("HA"))
TREND_FROM_HA = false
ag_status(); rows = load_env(20).pollution_rows()
check("a status.json from before the trend block: every cell shows --, never an error", rows[1].t1 == "--" and rows[1].t24 == "--" and rows[7].t24 == "--")
check("the outdoor rows have no trend cells (blank columns)", (function() set_suite(false) local r = load_env(5).pollution_rows() set_suite(true) return r[1].t1 == nil and r[1].t24 == nil end)())

-- ---------------------------------------------------------------- event notices
ag_status({notices = {"PM SPIKE // 2.5: 99"}})
check("a notice takes the DATA line when there is no alert", load_env(5).status_lines()[1] == "DATA // PM SPIKE // 2.5: 99", load_env(5).status_lines()[1])
check("...in the outdoor phase too", load_env(20).status_lines()[1] == "DATA // PM SPIKE // 2.5: 99")
ag_status({notices = {"PM SPIKE // 2.5: 99"}, alert = "OPEN WIN // PM2.5 66.9"})
check("an advisor alert wins over a notice", load_env(5).status_lines()[1] == "DATA // OPEN WIN // PM2.5 66.9")
ag_status({notices = {"PM SPIKE // 2.5: 99"}})
check("when the alert ends the notice shows in its place", load_env(5).status_lines()[1] == "DATA // PM SPIKE // 2.5: 99")
ag_status({notices = {"PM SPIKE // 2.5: 99"}, gen_age = 400})
check("a stale reading says AG STALE, not the old notice", load_env(5).status_lines()[1] == "DATA // AG STALE")
ag_status({notices = {"PM SPIKE // 2.5: 99"}}); air_files(nil, nil, '{"state":"error"}')
check("an outdoor air fault outranks a notice", load_env(5).status_lines()[1]:match("FAULT") ~= nil, load_env(5).status_lines()[1])
air_files()
ag_status({notices = {"PM SPIKE // 2.5: 99", "VOC SPIKE // 485"}})
local first, second = load_env(0).status_lines()[1], load_env(10).status_lines()[1]
check("two notices take turns every 10 seconds", first ~= second and (first:match("PM SPIKE") or first:match("VOC SPIKE")) and (second:match("PM SPIKE") or second:match("VOC SPIKE")), first .. " / " .. second)
ag_status({notices = {"PM SPIKE // 2.5: 99"}})
check("show_notices = false: NOMINAL", load_env(5, {show_notices = false}).status_lines()[1] == "DATA // NOMINAL")
ag_status({notices = {string.rep("X", 40)}})
check("a notice is cut to 29 characters", #load_env(5).status_lines()[1] == #"DATA // " + 29)
ag_status()
check("no notices: NOMINAL", load_env(5).status_lines()[1] == "DATA // NOMINAL")
write(SC .. "/cache/shared/airgradient/indoor/status.json", '{"state":"ok","generated_at":"' .. iso(real_time() - 3) .. '","label":"X","notices":null,"ventilation":{"alert_visible":false}}')
check("a null notices field is no notice, no error", load_env(5).status_lines()[1] == "DATA // NOMINAL")

-- ---------------------------------------------------------------- alerts
ag_status({alert = "OPEN WIN // CO2 1150 PPM", co2 = 1150})
for _, ph in ipairs({0, 12, 25}) do check("alert on the DATA line at phase " .. ph, load_env(ph).status_lines()[1] == "DATA // OPEN WIN // CO2 1150 PPM") end
check("with an alert phase 9 is outdoor, 10 and 14 are indoor",
  load_env(9).pollution_title() == "POLLUTION" and load_env(10).pollution_title() ~= "POLLUTION" and load_env(14).pollution_title() ~= "POLLUTION")
ag_status({alert = string.rep("X", 40)}); check("alert text clipped to 29 characters", #load_env(0).status_lines()[1] == #"DATA // " + 29)

-- ---------------------------------------------------------------- staleness and states
ag_status({gen_age = 400, alert = "OPEN WIN // VOC 263"}); E = load_env(20)
check("stale: AG STALE, outdoor view, outdoor SRC", E.status_lines()[1] == "DATA // AG STALE" and E.pollution_title() == "POLLUTION" and E.status_lines()[2]:match("^SRC // OWM") ~= nil)
ag_status({state = "partial"}); check("partial still shows the indoor view", load_env(20).pollution_title() == "INDOOR")
ag_status({state = "partial", gen_age = 400}); E = load_env(20)
check("partial and stale: AG STALE, outdoor", E.status_lines()[1] == "DATA // AG STALE" and E.pollution_title() == "POLLUTION")
ag_status({state = "degraded", gen_age = 60}); check("degraded but recent: indoor", load_env(20).pollution_title() == "INDOOR")
ag_status({state = "degraded", gen_age = 400}); E = load_env(20)
check("degraded and stale: AG STALE, outdoor", E.status_lines()[1] == "DATA // AG STALE" and E.pollution_title() == "POLLUTION")
ag_status({state = "disabled", no_gen = true, alert = "OPEN WIN // X"}); E = load_env(20)
check("disabled: nothing from AirGradient", E.pollution_title() == "POLLUTION" and E.status_lines()[1] == "DATA // NOMINAL")
ag_status({state = "error", no_gen = true}); check("error: nothing from AirGradient", load_env(20).status_lines()[1] == "DATA // NOMINAL")
ag_status({no_gen = true}); E = load_env(20)
check("ok state without generated_at is stale", E.status_lines()[1] == "DATA // AG STALE" and E.pollution_title() == "POLLUTION")
os.remove(SC .. "/cache/shared/airgradient/indoor/status.json"); E = load_env(20)
check("no status.json: normal outdoor view", E.pollution_title() == "POLLUTION" and E.status_lines()[1] == "DATA // NOMINAL")
write(SC .. "/cache/shared/airgradient/indoor/status.json", "{not json"); E = load_env(20)
check("garbage status.json: normal outdoor view, no error", E.pollution_title() == "POLLUTION" and E.status_lines()[1] == "DATA // NOMINAL")
ag_status({alert = "OPEN WIN // VOC 263"}); air_files(nil, nil, '{"state":"error"}'); E = load_env(0)
check("an outdoor air fault outranks the advice", E.status_lines()[1] == "DATA // FAULT - AIR CACHE ERROR", E.status_lines()[1])
air_files()

-- ---------------------------------------------------------------- outdoor PM2.5: provider value first, bounded raw fallback
set_suite(false)
air_files(6.7, {{age = 3000, value = 9.7, raw = 9.7}, {age = 3000, value = 12.4, raw = 12.4}}); E = load_env(5)
check("provider value (nearest monitor) beats a different newest raw row: 6.70", E.pollution_rows()[1].value == "6.70", E.pollution_rows()[1].value)
check("SRC line lists PM2.5 as AirNow", E.status_lines()[2]:match("PM2%.5") ~= nil)
air_files(nil, {{age = 3000, value = 8.2, raw = -999.0}}); E = load_env(5)
check("overlay empty: raw fallback uses Value when raw is -999 (8.20)", E.pollution_rows()[1].value == "8.20", E.pollution_rows()[1].value)
air_files(nil, {{age = 9000, value = 8.2, raw = 8.2}}); E = load_env(5)
check("overlay empty and raw older than 2 h: OpenWeather (13.30), SRC drops PM2.5", E.pollution_rows()[1].value == "13.30" and not E.status_lines()[2]:match("PM2%.5"))
air_files(nil, {{age = 3000, value = 9.7, raw = 9.7}, {age = 5000, value = 7.1, raw = 7.1}}); check("raw fallback takes the newest row (9.70)", load_env(5).pollution_rows()[1].value == "9.70")
air_files(nil, {}); check("no AirNow data: OpenWeather value (13.30)", load_env(5).pollution_rows()[1].value == "13.30")
air_files(); set_suite(true)

-- ---------------------------------------------------------------- knobs: theme.env.airgradient via M.configure
ag_status()
E = load_env(20, {label = "office"})
check("label knob overrides the provider's (upper-cased): the SRC line shows it, the header drops a name that does not fit", E.pollution_title() == "INDOOR" and E.status_lines()[2] == "SRC // AG OFFICE")
check("a short title leaves room for the name in the header: IN // CAVE", load_env(20, {title = "in"}).pollution_title() == "IN // CAVE")
check("exactly 12 characters fits (AIR // CAVE is 11, INDOOR // 42 is 12)", load_env(20, {title = "air"}).pollution_title() == "AIR // CAVE" and load_env(20, {label = 42}).pollution_title() == "INDOOR // 42")
check("13 characters does not: INDOOR // 421 shows the title alone", load_env(20, {label = 421}).pollution_title() == "INDOOR")
E = load_env(20, {label = ""}); check("label \"\" shows no name", E.pollution_title() == "INDOOR" and E.status_lines()[2] == "SRC // AG")
check("a long label is clamped to 8 characters (the SRC line shows it)", load_env(20, {label = "abcdefghij"}).status_lines()[2] == "SRC // AG ABCDEFGH")
check("label absent uses the provider's", load_env(20, {}).pollution_title() == "INDOOR")
E = load_env(20, {title = "air", source_tag = "iaq"})
check("title and source_tag knobs", E.pollution_title() == "AIR // CAVE" and E.status_lines()[2] == "SRC // IAQ CAVE")
E = load_env(20, {title = "   ", source_tag = "toolongtag"})
check("blank title falls back to INDOOR; long source_tag clamped to 6", E.pollution_title() == "INDOOR" and E.status_lines()[2] == "SRC // TOOLON CAVE")
for _, c in ipairs({{39, false}, {40, true}, {59, true}, {0, false}}) do
  check(("cycle 60 / outdoor 40: phase %d is %s"):format(c[1], c[2] and "indoor" or "outdoor"),
    (load_env(c[1], {cycle_sec = 60, outdoor_sec = 40}, base60).pollution_title() ~= "POLLUTION") == c[2])
end
ag_status({alert = "OPEN WIN // VOC 263"})
check("alert_outdoor_sec 5: phase 4 outdoor, phase 5 indoor",
  load_env(4, {alert_outdoor_sec = 5}).pollution_title() == "POLLUTION" and load_env(5, {alert_outdoor_sec = 5}).pollution_title() ~= "POLLUTION")
check("alert_outdoor_sec 25: phase 14 still outdoor", load_env(14, {outdoor_sec = 15, alert_outdoor_sec = 25}).pollution_title() == "POLLUTION")
ag_status()
check("outdoor_sec beyond the cycle is clamped: the indoor phase never comes", load_env(19, {cycle_sec = 20, outdoor_sec = 99}, base60).pollution_title() == "POLLUTION")
check("outdoor_sec = 0: indoor all the time", load_env(0, {outdoor_sec = 0}).pollution_title() == "INDOOR")
ag_status({alert = "OPEN WIN // CO2 1150 PPM", co2 = 1150})
E = load_env(20, {enabled = false})
check("enabled = false: outdoor view, normal SRC, DATA untouched even with an alert",
  E.pollution_title() == "POLLUTION" and E.status_lines()[2]:match("^SRC // OWM") ~= nil and E.status_lines()[1] == "DATA // NOMINAL")
E = load_env(20, {show_alerts = false})
check("show_alerts = false: no advice on the DATA line, indoor view still rotates", E.status_lines()[1] == "DATA // NOMINAL" and E.pollution_title() ~= "POLLUTION")
check("show_alerts = false also drops the shortened outdoor share (phase 14 is outdoor)", load_env(14, {show_alerts = false}).pollution_title() == "POLLUTION")
ag_status({gen_age = 400}); E = load_env(20, {show_stale = false})
check("show_stale = false: a stale reading is silent", E.status_lines()[1] == "DATA // NOMINAL" and E.pollution_title() == "POLLUTION")
E = load_env(20, {stale_sec = 600}); check("stale_sec = 600: a 400 s old reading is fresh", E.pollution_title() ~= "POLLUTION" and E.status_lines()[1] == "DATA // NOMINAL")
ag_status({gen_age = 60}); E = load_env(20, {stale_sec = 30})
check("stale_sec = 30: a 60 s old reading is stale", E.status_lines()[1] == "DATA // AG STALE" and E.pollution_title() == "POLLUTION")
ag_status({co2 = 500}); local clock = base + 20
os.time = function() return clock end
E = dofile(ENV_LUA); E.configure({refresh_sec = 1})
local first = E.pollution_rows()[1].value
ag_status({co2 = 800}); clock = clock + 2
check("refresh_sec = 1: a change shows up two seconds later", first == "500" and E.pollution_rows()[1].value == "800")
ag_status({co2 = 500}); clock = base + 20
E = dofile(ENV_LUA); E.configure({refresh_sec = 15}); first = E.pollution_rows()[1].value
ag_status({co2 = 800}); clock = clock + 2
check("refresh_sec = 15: the same change is not re-read after two seconds", E.pollution_rows()[1].value == first)
ag_status()
E = load_env(20, {cycle_sec = "abc", outdoor_sec = -5, alert_outdoor_sec = {}, stale_sec = 0, refresh_sec = -1, enabled = "yes", label = 42})
check("invalid values never raise and fall back or clamp (label 42 becomes \"42\")", E.pollution_title() == "INDOOR // 42", E.pollution_title())
check("a non-table config is ignored", load_env(20, 5).pollution_title() == "INDOOR")
E = load_env(20, {label = "OFFICE"}); E.configure(nil)
check("configure(nil) (a theme without the block) resets to the defaults", E.pollution_title() == "INDOOR")
os.time = function() return base + 20 end
check("never configured: shipped defaults apply", dofile(ENV_LUA).pollution_title() == "INDOOR")

print(string.format("\n%d passed, %d failed", passes, fails))
os.exit(fails == 0 and 0 or 1)
