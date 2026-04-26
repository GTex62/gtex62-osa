local M = {}

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

local CLOUD_GLYPHS = {
  N_0 = utf8_char(0xE03A),
  N_1 = utf8_char(0xE03B),
  N_2 = utf8_char(0xE03C),
  N_3 = utf8_char(0xE03D),
  N_4 = utf8_char(0xE03E),
  N_5 = utf8_char(0xE03F),
  N_6 = utf8_char(0xE040),
  N_7 = utf8_char(0xE041),
  N_8 = utf8_char(0xE042),
  N_9 = utf8_char(0xE043),
  N_Slash = utf8_char(0xE044),
}

local WX_GLYPHS = {
  unknown = utf8_char(0xE02F),
  none = "",
  smoke = utf8_char(0xE000),
  haze = utf8_char(0xE001),
  fog = utf8_char(0xE003),
  thunder = utf8_char(0xE004),
  drizzle_light = utf8_char(0xE007),
  drizzle = utf8_char(0xE009),
  drizzle_heavy = utf8_char(0xE00B),
  rain_light = utf8_char(0xE011),
  rain = utf8_char(0xE013),
  rain_heavy = utf8_char(0xE015),
  freezing_rain = utf8_char(0xE017),
  snow_light = utf8_char(0xE01A),
  snow = utf8_char(0xE01C),
  snow_heavy = utf8_char(0xE01E),
  sleet = utf8_char(0xE01F),
  shower = utf8_char(0xE021),
}

function M.cloud_from_percent(cloud_percent)
  local p = tonumber(cloud_percent)
  if not p then
    return {
      label = "N/A",
      code = "N_Slash",
      glyph = CLOUD_GLYPHS.N_Slash,
      percent = nil,
    }
  end

  if p <= 0 then
    return { label = "CLR", code = "N_0", glyph = CLOUD_GLYPHS.N_0, percent = p }
  elseif p <= 30 then
    return { label = "FEW", code = "N_2", glyph = CLOUD_GLYPHS.N_2, percent = p }
  elseif p <= 50 then
    return { label = "SCT", code = "N_4", glyph = CLOUD_GLYPHS.N_4, percent = p }
  elseif p <= 89 then
    return { label = "BKN", code = "N_6", glyph = CLOUD_GLYPHS.N_6, percent = p }
  end

  return { label = "OVC", code = "N_8", glyph = CLOUD_GLYPHS.N_8, percent = p }
end

function M.wx_from_owm(id)
  local n = tonumber(id)
  if not n then
    return { key = "none", glyph = WX_GLYPHS.none, id = nil }
  end

  if n >= 200 and n < 300 then
    return { key = "thunder", glyph = WX_GLYPHS.thunder, id = n }
  elseif n >= 300 and n < 400 then
    if n >= 310 then
      return { key = "drizzle", glyph = WX_GLYPHS.drizzle, id = n }
    end
    return { key = "drizzle_light", glyph = WX_GLYPHS.drizzle_light, id = n }
  elseif n >= 500 and n < 600 then
    if n == 500 then
      return { key = "rain_light", glyph = WX_GLYPHS.rain_light, id = n }
    elseif n == 501 then
      return { key = "rain", glyph = WX_GLYPHS.rain, id = n }
    elseif n >= 502 and n <= 504 then
      return { key = "rain_heavy", glyph = WX_GLYPHS.rain_heavy, id = n }
    elseif n == 511 then
      return { key = "freezing_rain", glyph = WX_GLYPHS.freezing_rain, id = n }
    elseif n >= 520 then
      return { key = "shower", glyph = WX_GLYPHS.shower, id = n }
    end
    return { key = "rain", glyph = WX_GLYPHS.rain, id = n }
  elseif n >= 600 and n < 700 then
    if n == 611 or n == 612 or n == 613 or n == 615 or n == 616 then
      return { key = "sleet", glyph = WX_GLYPHS.sleet, id = n }
    elseif n == 600 or n == 620 then
      return { key = "snow_light", glyph = WX_GLYPHS.snow_light, id = n }
    elseif n >= 601 and n <= 602 then
      return { key = "snow", glyph = WX_GLYPHS.snow, id = n }
    end
    return { key = "snow_heavy", glyph = WX_GLYPHS.snow_heavy, id = n }
  elseif n >= 700 and n < 800 then
    if n == 741 then
      return { key = "fog", glyph = WX_GLYPHS.fog, id = n }
    elseif n == 711 then
      return { key = "smoke", glyph = WX_GLYPHS.smoke, id = n }
    end
    return { key = "haze", glyph = WX_GLYPHS.haze, id = n }
  elseif n >= 800 and n < 900 then
    return { key = "none", glyph = WX_GLYPHS.none, id = n }
  end

  return { key = "unknown", glyph = WX_GLYPHS.unknown, id = n }
end

M.CLOUD_GLYPHS = CLOUD_GLYPHS
M.WX_GLYPHS = WX_GLYPHS

return M
