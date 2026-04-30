---@diagnostic disable: undefined-global

local M = {}
local HOME = os.getenv("HOME") or ""
local ORB_COAST_RINGS = nil
local SUITE_DIR = os.getenv("CONKY_SUITE_DIR") or (HOME .. "/.config/conky/gtex62-osa")
local RUNTIME_ROOT = os.getenv("GTEX62_CONFIG_DIR") or os.getenv("GTEX62_CONKY_CONFIG_DIR") or (HOME .. "/.config/gtex62-core")
local SHARED_ASSETS_DIR = os.getenv("GTEX62_SHARED_ASSETS_DIR")
  or os.getenv("GTEX62_SHARED_ASSETS")
  or os.getenv("GTEX62_CONKY_SHARED_ASSETS")
  or (HOME .. "/.config/conky/gtex62-shared-assets")

local FOOTER_VERSION_CACHE = {
  tick = nil,
  label = nil,
}

local function read_file(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return s
end

local function simple_toml_value(path, key)
  local s = read_file(path)
  if not s then return nil end

  for line in s:gmatch("[^\r\n]+") do
    line = line:gsub("#.*$", ""):gsub("^%s+", ""):gsub("%s+$", "")
    local parsed_key, value = line:match("^([%w_%-]+)%s*=%s*(.+)$")
    if parsed_key == key then
      return value:gsub('^"', ""):gsub('"$', "")
    end
  end

  return nil
end

local function machine_identity_label()
  local user = os.getenv("USER") or os.getenv("LOGNAME") or "USER"
  local host = os.getenv("HOSTNAME")

  if not host or host == "" then
    local handle = io.popen("hostname 2>/dev/null")
    if handle then
      host = handle:read("*l")
      handle:close()
    end
  end

  host = host or "MACHINE"
  host = host:gsub("%..*$", "")

  return string.upper(user) .. "@" .. string.upper(host)
end

local function version_identity_label()
  local tick = os.time()
  if FOOTER_VERSION_CACHE.tick == tick and FOOTER_VERSION_CACHE.label then
    return FOOTER_VERSION_CACHE.label
  end

  local engine_version = simple_toml_value(RUNTIME_ROOT .. "/core.toml", "version")
    or simple_toml_value(RUNTIME_ROOT .. "/engine.toml", "version")
    or "UNKNOWN"
  local suite_version = simple_toml_value(SUITE_DIR .. "/suite.toml", "version")
    or simple_toml_value(RUNTIME_ROOT .. "/suites/osa.toml", "version")
    or "UNKNOWN"

  FOOTER_VERSION_CACHE.tick = tick
  FOOTER_VERSION_CACHE.label = string.format(
    "CORE %s // OSA %s",
    string.upper(engine_version),
    string.upper(suite_version)
  )

  return FOOTER_VERSION_CACHE.label
end

local function set_rgb(cr, color)
  cairo_set_source_rgb(cr, color[1], color[2], color[3])
end

local function draw_rect(cr, x, y, w, h, line_width, color)
  cairo_set_line_width(cr, line_width)
  set_rgb(cr, color)
  cairo_rectangle(cr, x + 0.5, y + 0.5, w - 1, h - 1)
  cairo_stroke(cr)
end

local function fill_rect(cr, x, y, w, h, color)
  set_rgb(cr, color)
  cairo_rectangle(cr, x, y, w, h)
  cairo_fill(cr)
end

local function draw_title(cr, panel, theme, frame)
  local title_font = theme.fonts.title
  local title_pt = theme.text.panel_title_pt
  local pad_x = theme.spacing.title_pad_x
  local clearance = theme.spacing.title_clearance
  local title = panel.title
  local x = frame.x + panel.x + pad_x
  local y = frame.y + panel.y

  cairo_select_font_face(cr, title_font, CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_BOLD)
  cairo_set_font_size(cr, title_pt)

  local ext = cairo_text_extents_t:create()
  cairo_text_extents(cr, title, ext)

  -- Mask the top stroke behind the title so it reads like the measured sketch.
  set_rgb(cr, theme.colors.bg)
  cairo_rectangle(
    cr,
    x - clearance,
    y - (title_pt * 0.55),
    ext.width + clearance * 2,
    title_pt + clearance
  )
  cairo_fill(cr)

  set_rgb(cr, theme.colors.fg)
  cairo_move_to(cr, x, y + (title_pt * 0.35))
  cairo_show_text(cr, title)
end

local function draw_panel_boxes(cr, panel, theme, frame)
  local boxes = panel.boxes
  if type(boxes) ~= "table" then return end

  for _, box in pairs(boxes) do
    draw_rect(
      cr,
      frame.x + panel.x + box.x,
      frame.y + panel.y + box.y,
      box.width,
      box.height,
      theme.strokes.line,
      theme.colors.fg
    )
  end
end

local function draw_box_title(cr, x, y, txt, theme)
  if not txt or txt == "" then return end
  txt = string.upper(txt)

  local title_font = theme.fonts.title
  local title_pt = theme.text.body_sm_pt
  local clearance = theme.spacing.title_clearance

  cairo_select_font_face(cr, title_font, CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_BOLD)
  cairo_set_font_size(cr, title_pt)

  local ext = cairo_text_extents_t:create()
  cairo_text_extents(cr, txt, ext)

  set_rgb(cr, theme.colors.bg)
  cairo_rectangle(
    cr,
    x - clearance,
    y - (title_pt * 0.55),
    ext.width + clearance * 2,
    title_pt + clearance
  )
  cairo_fill(cr)

  set_rgb(cr, theme.colors.fg)
  cairo_move_to(cr, x, y + (title_pt * 0.35))
  cairo_show_text(cr, txt)
end

local function draw_panel_box_titles(cr, panel, theme, frame, panel_data)
  local boxes = panel.boxes
  if type(boxes) ~= "table" or type(panel_data) ~= "table" then return end

  for _, box in pairs(boxes) do
    local source = box and box.title_source
    local provider = source and panel_data[source]
    if type(provider) == "function" then
      draw_box_title(
        cr,
        frame.x + panel.x + box.x + (theme.spacing.box_title_x or 20),
        frame.y + panel.y + box.y,
        provider(),
        theme
      )
    end
  end
end

local function draw_text_left(cr, x, y, txt, font_face, font_size, color, weight)
  if not txt or txt == "" then return end
  set_rgb(cr, color)
  cairo_select_font_face(
    cr,
    font_face,
    CAIRO_FONT_SLANT_NORMAL,
    weight or CAIRO_FONT_WEIGHT_NORMAL
  )
  cairo_set_font_size(cr, font_size)
  cairo_move_to(cr, x, y)
  cairo_show_text(cr, txt)
end

local function draw_text_left_mid(cr, x, y, txt, font_face, font_size, color, weight)
  if not txt or txt == "" then return end
  set_rgb(cr, color)
  cairo_select_font_face(
    cr,
    font_face,
    CAIRO_FONT_SLANT_NORMAL,
    weight or CAIRO_FONT_WEIGHT_NORMAL
  )
  cairo_set_font_size(cr, font_size)
  local ext = cairo_text_extents_t:create()
  cairo_text_extents(cr, txt, ext)
  cairo_move_to(cr, x, y + (ext.height / 2))
  cairo_show_text(cr, txt)
end

local function draw_text_center_mid(cr, x, y, txt, font_face, font_size, color, weight)
  if not txt or txt == "" then return end
  set_rgb(cr, color)
  cairo_select_font_face(
    cr,
    font_face,
    CAIRO_FONT_SLANT_NORMAL,
    weight or CAIRO_FONT_WEIGHT_NORMAL
  )
  cairo_set_font_size(cr, font_size)
  local ext = cairo_text_extents_t:create()
  cairo_text_extents(cr, txt, ext)
  cairo_move_to(cr, x - (ext.width / 2 + ext.x_bearing), y + (ext.height / 2))
  cairo_show_text(cr, txt)
end

local function draw_panel_footer_label(cr, panel, theme, frame)
  local label = panel.footer_label
  if not label or label == "" then return end

  local center_x = frame.x + panel.x + (panel.width / 2)
  local label_y = frame.y + panel.y + panel.height + (tonumber(panel.footer_label_y) or 36)

  draw_text_center_mid(
    cr,
    center_x,
    label_y,
    string.upper(label),
    theme.fonts.title,
    tonumber(panel.footer_label_font_pt) or theme.text.panel_title_pt,
    theme.colors.fg,
    CAIRO_FONT_WEIGHT_BOLD
  )

  draw_text_center_mid(
    cr,
    center_x,
    label_y + (tonumber(panel.footer_machine_label_gap) or 22),
    machine_identity_label(),
    theme.fonts.title,
    tonumber(panel.footer_machine_label_font_pt) or tonumber(panel.footer_label_font_pt) or theme.text.panel_title_pt,
    theme.colors.fg,
    CAIRO_FONT_WEIGHT_BOLD
  )

  draw_text_center_mid(
    cr,
    center_x,
    label_y + (tonumber(panel.footer_version_label_gap) or 40),
    version_identity_label(),
    theme.fonts.title,
    tonumber(panel.footer_version_label_font_pt) or tonumber(panel.footer_machine_label_font_pt) or theme.text.micro_pt,
    theme.colors.fg,
    CAIRO_FONT_WEIGHT_BOLD
  )
end

local function draw_text_center_mid_alpha(cr, x, y, txt, font_face, font_size, color, alpha, weight)
  if not txt or txt == "" then return end
  cairo_select_font_face(
    cr,
    font_face,
    CAIRO_FONT_SLANT_NORMAL,
    weight or CAIRO_FONT_WEIGHT_NORMAL
  )
  cairo_set_font_size(cr, font_size)
  cairo_set_source_rgba(
    cr,
    color[1] or 1.0,
    color[2] or 1.0,
    color[3] or 1.0,
    alpha or 1.0
  )
  local ext = cairo_text_extents_t:create()
  cairo_text_extents(cr, txt, ext)
  cairo_move_to(cr, x - (ext.width / 2 + ext.x_bearing), y + (ext.height / 2))
  cairo_show_text(cr, txt)
end

local function draw_text_right(cr, x, y, txt, font_face, font_size, color, weight)
  if not txt or txt == "" then return end
  set_rgb(cr, color)
  cairo_select_font_face(
    cr,
    font_face,
    CAIRO_FONT_SLANT_NORMAL,
    weight or CAIRO_FONT_WEIGHT_NORMAL
  )
  cairo_set_font_size(cr, font_size)
  local ext = cairo_text_extents_t:create()
  cairo_text_extents(cr, txt, ext)
  cairo_move_to(cr, x - (ext.width + ext.x_bearing), y)
  cairo_show_text(cr, txt)
end

local function draw_text_right_mid(cr, x, y, txt, font_face, font_size, color, weight)
  if not txt or txt == "" then return end
  set_rgb(cr, color)
  cairo_select_font_face(
    cr,
    font_face,
    CAIRO_FONT_SLANT_NORMAL,
    weight or CAIRO_FONT_WEIGHT_NORMAL
  )
  cairo_set_font_size(cr, font_size)
  local ext = cairo_text_extents_t:create()
  cairo_text_extents(cr, txt, ext)
  cairo_move_to(cr, x - (ext.width + ext.x_bearing), y + (ext.height / 2))
  cairo_show_text(cr, txt)
end

local function draw_text_block_left(cr, x, y, lines, font_face, font_size, color, line_step, weight)
  if type(lines) ~= "table" then return end
  local step = tonumber(line_step) or font_size
  for i, line in ipairs(lines) do
    draw_text_left(
      cr,
      x,
      y + ((i - 1) * step),
      line,
      font_face,
      font_size,
      color,
      weight
    )
  end
end

local function draw_meter_header(cr, x, y, w, h, label, font_pt, vertical_h, marks, theme)
  fill_rect(cr, x, y, w, h, theme.colors.fg)
  draw_text_center_mid(
    cr,
    x + (w / 2),
    y + (h / 2),
    label,
    theme.fonts.data,
    font_pt,
    theme.colors.ink,
    CAIRO_FONT_WEIGHT_NORMAL
  )

  vertical_h = tonumber(vertical_h) or 128
  marks = marks or {}

  draw_rect(
    cr,
    x,
    y + h + 1,
    w,
    1,
    theme.strokes.line,
    theme.colors.fg
  )

  draw_rect(
    cr,
    x + w - 1,
    y + h + 2,
    1,
    vertical_h,
    theme.strokes.line,
    theme.colors.fg
  )

  draw_rect(
    cr,
    x,
    y + h + 1 + vertical_h,
    w,
    1,
    theme.strokes.line,
    theme.colors.fg
  )

  local tick_x = x + w - 1
  local tick_top = y + h + 2
  local short = tonumber(marks.short) or 4
  local medium = tonumber(marks.medium) or 6
  local long = tonumber(marks.long) or 8

  for i = 1, 7 do
    local len = short
    if i == 4 then
      len = long
    elseif i == 2 or i == 6 then
      len = medium
    end

    local tick_y = tick_top + math.floor((vertical_h * (i / 8)) + 0.5)
    draw_rect(
      cr,
      tick_x - len + 1,
      tick_y,
      len,
      1,
      theme.strokes.line,
      theme.colors.fg
    )
  end
end

local function draw_meter_value(cr, x, y, value, font_pt, color, theme)
  local numeric = tonumber(value) or 0
  draw_text_left_mid(
    cr,
    x,
    y,
    string.format("%03d", math.floor(numeric + 0.5)),
    theme.fonts.data,
    font_pt,
    color,
    CAIRO_FONT_WEIGHT_NORMAL
  )
end

local function draw_meter_value_center(cr, x, y, value, font_pt, color, theme)
  local numeric = tonumber(value) or 0
  draw_text_center_mid(
    cr,
    x,
    y,
    string.format("%03d", math.floor(numeric + 0.5)),
    theme.fonts.data,
    font_pt,
    color,
    CAIRO_FONT_WEIGHT_NORMAL
  )
end

local function draw_meter_text_center(cr, x, y, text, font_pt, color, theme)
  draw_text_center_mid(
    cr,
    x,
    y,
    tostring(text or ""),
    theme.fonts.data,
    font_pt,
    color,
    CAIRO_FONT_WEIGHT_NORMAL
  )
end

local function draw_meter_text(cr, x, y, text, font_pt, color, theme)
  draw_text_left_mid(
    cr,
    x,
    y,
    tostring(text or ""),
    theme.fonts.data,
    font_pt,
    color,
    CAIRO_FONT_WEIGHT_NORMAL
  )
end

local function draw_meter_bar(cr, x, y_top, y_bottom, value, max_value, width, color)
  local numeric = tonumber(value) or 0
  local max_v = tonumber(max_value) or 100
  if max_v <= 0 then return end

  local clamped = math.max(0, math.min(numeric, max_v))
  local track_h = math.max(0, y_bottom - y_top)
  local fill_h = math.floor((track_h * (clamped / max_v)) + 0.5)
  if fill_h <= 0 then return end

  fill_rect(
    cr,
    x,
    y_bottom - fill_h,
    width,
    fill_h,
    color
  )
end

local function draw_table_header(cr, x, y, w, h, label, font_pt, theme)
  fill_rect(cr, x, y, w, h, theme.colors.fg)
  draw_text_center_mid(
    cr,
    x + (w / 2),
    y + (h / 2),
    label,
    theme.fonts.data,
    font_pt,
    theme.colors.ink,
    CAIRO_FONT_WEIGHT_NORMAL
  )
end

local function draw_split_table_header(cr, x, y, left_w, gap_w, right_w, h, left_label, right_label, font_pt, theme)
  draw_table_header(cr, x, y, left_w, h, left_label, font_pt, theme)
  draw_table_header(cr, x + left_w + gap_w, y, right_w, h, right_label, font_pt, theme)
end

local function draw_hbar(cr, x, y, w, h, ratio, color)
  local numeric = tonumber(ratio) or 0
  local clamped = math.max(0, math.min(1, numeric))
  local fill_w = math.floor((w * clamped) + 0.5)
  if fill_w <= 0 then return end
  fill_rect(cr, x, y, fill_w, h, color)
end

local function draw_env_meter(cr, theme, x, y, w, cfg, label, value, bar_specs, footer_left, footer_right)
  local header_h = tonumber(cfg.header_h) or 16
  local footer_h = tonumber(cfg.footer_h) or 16
  local footer_gap = tonumber(cfg.footer_gap) or 2
  local font_pt = tonumber(cfg.header_font_pt) or theme.text.body_xs_pt
  local value_y = tonumber(cfg.meter_value_y) or 92
  local bar_w = tonumber(cfg.meter_bar_w) or 8
  local meter_bottom = y + (tonumber(cfg.height) or 216)
  local footer_y = meter_bottom - footer_h
  local body_top = y + header_h + 2
  local body_h = math.max(0, footer_y - body_top)
  local center_x = x + math.floor(w / 2)
  local marks = cfg.meter_marks or {}
  local short = tonumber(marks.short) or 5
  local medium = tonumber(marks.medium) or 8
  local long = tonumber(marks.long) or 11

  draw_table_header(cr, x, y, w, header_h, label, font_pt, theme)
  draw_rect(cr, x, y + header_h + 1, w, 1, theme.strokes.line, theme.colors.fg)
  draw_rect(cr, center_x, body_top, 1, body_h, theme.strokes.line, theme.colors.fg)

  for i = 1, 11 do
    local len = short
    if i == 6 then
      len = long
    elseif i == 3 or i == 9 then
      len = medium
    end
    local tick_y = body_top + math.floor((body_h * (i / 12)) + 0.5)
    draw_rect(cr, center_x - math.floor(len / 2), tick_y, len, 1, theme.strokes.line, theme.colors.fg)
  end

  if type(bar_specs) == "table" then
    local count = #bar_specs
    local gap = tonumber(cfg.meter_bar_gap) or 16
    local total_w = (count * bar_w) + (math.max(0, count - 1) * gap)
    local first_x = center_x - (total_w / 2)
    for i, spec in ipairs(bar_specs) do
      local bar_x = first_x + ((i - 1) * (bar_w + gap))
      draw_meter_bar(
        cr,
        bar_x,
        body_top,
        footer_y,
        spec.value,
        spec.max_value,
        bar_w,
        theme.colors.fg
      )
      if spec.show_value ~= false then
        local font_pt = tonumber(spec.value_font_pt) or tonumber(cfg.meter_value_font_pt) or 20
        local text_y = y + (tonumber(spec.value_y) or value_y)
        local value_text = spec.value_text
        if spec.value_center_x then
          if value_text ~= nil then
            draw_meter_text_center(
              cr,
              tonumber(spec.value_center_x) or (bar_x + (bar_w / 2)),
              text_y,
              value_text,
              font_pt,
              theme.colors.fg,
              theme
            )
          else
            draw_meter_value_center(
              cr,
              tonumber(spec.value_center_x) or (bar_x + (bar_w / 2)),
              text_y,
              spec.value,
              font_pt,
              theme.colors.fg,
              theme
            )
          end
        else
          if value_text ~= nil then
            draw_meter_text(
              cr,
              tonumber(spec.value_x) or (bar_x - 10),
              text_y,
              value_text,
              font_pt,
              theme.colors.fg,
              theme
            )
          else
            draw_meter_value(
              cr,
              tonumber(spec.value_x) or (bar_x - 10),
              text_y,
              spec.value,
              font_pt,
              theme.colors.fg,
              theme
            )
          end
        end
      end
    end
  end

  if value ~= nil then
    draw_meter_value(
      cr,
      x + math.floor(w * 0.5) - 20,
      y + value_y,
      value,
      tonumber(cfg.meter_value_font_pt) or 20,
      theme.colors.fg,
      theme
    )
  end

  local footer_w = (w - footer_gap) / 2
  draw_table_header(cr, x, footer_y, footer_w, footer_h, footer_left, font_pt, theme)
  draw_table_header(cr, x + footer_w + footer_gap, footer_y, footer_w, footer_h, footer_right, font_pt, theme)
end

local function draw_env_atmos_table(cr, theme, x, y, w, cfg, title, rows, row_limit)
  local header_h = tonumber(cfg.header_h) or 16
  local header_gap = tonumber(cfg.header_gap) or 2
  local value_w = tonumber(cfg.table_value_w) or 36
  local label_w = w - value_w - header_gap
  local header_font_pt = tonumber(cfg.header_font_pt) or theme.text.body_xs_pt
  local row_font_pt = tonumber(cfg.row_font_pt) or theme.text.micro_pt
  local row_h = tonumber(cfg.row_h) or 16
  local row_y = y + header_h + 12

  draw_split_table_header(cr, x, y, label_w, header_gap, value_w, header_h, title, "(V)", header_font_pt, theme)
  draw_rect(cr, x, y + header_h + 1, w, 1, theme.strokes.line, theme.colors.fg)

  rows = rows or {}
  for i = 1, math.min(#rows, tonumber(row_limit) or #rows) do
    local row = rows[i] or {}
    local mid_y = row_y + ((i - 1) * row_h)
    draw_text_left_mid(
      cr,
      x,
      mid_y,
      string.upper(row.label or ""),
      theme.fonts.data,
      row_font_pt,
      theme.colors.fg,
      CAIRO_FONT_WEIGHT_NORMAL
    )
    draw_text_center_mid(
      cr,
      x + label_w + header_gap + (value_w / 2),
      mid_y,
      string.upper(tostring(row.value or "")),
      theme.fonts.data,
      row_font_pt,
      theme.colors.fg,
      CAIRO_FONT_WEIGHT_NORMAL
    )
  end
end

local function draw_station_wind_barb(cr, cx, cy, data, cfg, color)
  local spd = tonumber(data.wind_speed_kt)
  if not spd or spd <= 0 then return end

  local staff_len = tonumber(cfg.wind_staff_len) or 44
  local staff_start = tonumber(cfg.wind_staff_start) or 18
  local line_width = tonumber(cfg.wind_line_width) or 2
  local barb_len = tonumber(cfg.wind_barb_len) or 12
  local half_len = tonumber(cfg.wind_half_len) or 7
  local barb_spacing = tonumber(cfg.wind_spacing) or 7
  local barb_angle = math.rad(tonumber(cfg.wind_angle_deg) or 60)
  local pennant_len = tonumber(cfg.wind_pennant_len) or 15
  local pennant_width = tonumber(cfg.wind_pennant_width) or 8

  local dir = data.wind_dir_deg
  if data.wind_is_vrb then dir = 0 end
  local angle = ((dir or 0) - 90) * math.pi / 180
  local ux, uy = math.cos(angle), math.sin(angle)

  local start_x = cx + ux * staff_start
  local start_y = cy + uy * staff_start
  local end_x = start_x + ux * staff_len
  local end_y = start_y + uy * staff_len

  set_rgb(cr, color)
  cairo_set_line_width(cr, line_width)
  cairo_move_to(cr, start_x, start_y)
  cairo_line_to(cr, end_x, end_y)
  cairo_stroke(cr)

  local rounded = math.floor((spd + 2.5) / 5) * 5
  local n50 = math.floor(rounded / 50)
  rounded = rounded % 50
  local n10 = math.floor(rounded / 10)
  rounded = rounded % 10
  local n5 = math.floor(rounded / 5)

  local function rot(x, y, ang)
    local ca, sa = math.cos(ang), math.sin(ang)
    return x * ca - y * sa, x * sa + y * ca
  end

  local bx, by = rot(ux, uy, barb_angle)
  local offset = 0

  for _ = 1, n50 do
    local base_x = end_x - ux * offset
    local base_y = end_y - uy * offset
    cairo_move_to(cr, base_x, base_y)
    cairo_line_to(cr, base_x + bx * pennant_len, base_y + by * pennant_len)
    cairo_line_to(cr, base_x - ux * pennant_width, base_y - uy * pennant_width)
    cairo_close_path(cr)
    cairo_fill(cr)
    offset = offset + barb_spacing
  end

  for _ = 1, n10 do
    local base_x = end_x - ux * offset
    local base_y = end_y - uy * offset
    cairo_move_to(cr, base_x, base_y)
    cairo_line_to(cr, base_x + bx * barb_len, base_y + by * barb_len)
    cairo_stroke(cr)
    offset = offset + barb_spacing
  end

  if n5 > 0 then
    local base_x = end_x - ux * offset
    local base_y = end_y - uy * offset
    cairo_move_to(cr, base_x, base_y)
    cairo_line_to(cr, base_x + bx * half_len, base_y + by * half_len)
    cairo_stroke(cr)
  end
end

local function draw_wxr_slp_meter(cr, theme, x, y, cfg, data)
  if cfg.slp_meter_enabled == false then return end

  local w = tonumber(cfg.slp_meter_w) or 128
  local header_h = tonumber(cfg.slp_meter_header_h) or 16
  local footer_h = tonumber(cfg.slp_meter_footer_h) or 16
  local body_h = tonumber(cfg.slp_meter_body_h) or 128
  local gap = tonumber(cfg.slp_meter_footer_gap) or 2
  local font_pt = tonumber(cfg.slp_meter_font_pt) or theme.text.body_sm_pt
  local value_font_pt = tonumber(cfg.slp_meter_value_font_pt) or 18
  local footer_font_pt = tonumber(cfg.slp_meter_footer_font_pt) or theme.text.micro_pt
  local body_top = y + header_h + 2
  local footer_y = body_top + body_h + 2
  local half_w = (w - gap) / 2
  local mid_x = x + math.floor(w / 2)
  local bar_w = tonumber(cfg.slp_meter_bar_w) or 8
  local min_hpa = tonumber(cfg.slp_meter_min_hpa) or 950
  local max_hpa = tonumber(cfg.slp_meter_max_hpa) or 1050
  local value_spread = tonumber(cfg.slp_meter_value_spread) or 0

  draw_table_header(cr, x, y, w, header_h, "SLP", font_pt, theme)
  fill_rect(cr, x, y + header_h + 1, w, 1, theme.colors.fg)
  fill_rect(cr, x, footer_y - 2, w, 1, theme.colors.fg)
  fill_rect(cr, mid_x, body_top, 1, math.max(0, footer_y - body_top - 2), theme.colors.fg)

  do
    local hpa = tonumber(data.slp_hpa_value or data.slp_hpa)
    if hpa and max_hpa > min_hpa then
      local pct = math.max(0, math.min(1, (hpa - min_hpa) / (max_hpa - min_hpa)))
      local fill_h = math.floor((body_h * pct) + 0.5)
      if fill_h > 0 then
        fill_rect(
          cr,
          mid_x - (bar_w / 2),
          body_top + body_h - fill_h,
          bar_w,
          fill_h,
          theme.colors.fg
        )
      end
    end
  end

  draw_text_center_mid(
    cr,
    x + (half_w / 2) - value_spread,
    body_top + (body_h / 2),
    data.slp_inhg or "/",
    theme.fonts.data,
    value_font_pt,
    theme.colors.fg,
    CAIRO_FONT_WEIGHT_NORMAL
  )
  draw_text_center_mid(
    cr,
    x + half_w + gap + (half_w / 2) + value_spread,
    body_top + (body_h / 2),
    data.slp_hpa or "/",
    theme.fonts.data,
    value_font_pt,
    theme.colors.fg,
    CAIRO_FONT_WEIGHT_NORMAL
  )

  draw_table_header(cr, x, footer_y, half_w, footer_h, "INHG", footer_font_pt, theme)
  draw_table_header(cr, x + half_w + gap, footer_y, half_w, footer_h, "HPA", footer_font_pt, theme)
end

local function draw_wxr_station_model(cr, theme, x, y, cfg, data)
  local center_x = x + (tonumber(cfg.center_x) or 228)
  local center_y = y + (tonumber(cfg.center_y) or 88)
  local circle_radius = tonumber(cfg.circle_radius) or 48
  local circle_stroke = tonumber(cfg.circle_stroke) or theme.strokes.line
  local outer_radius = tonumber(cfg.outer_radius) or (circle_radius + 10)
  local outer_stroke = tonumber(cfg.outer_stroke) or theme.strokes.line
  local compass_radius = tonumber(cfg.compass_radius) or (circle_radius + 8)
  local major_len = tonumber(cfg.compass_major_len) or 8
  local minor_len = tonumber(cfg.compass_minor_len) or 4
  local major_width = tonumber(cfg.compass_major_width) or 2
  local minor_width = tonumber(cfg.compass_minor_width) or 1
  local cloud_font_pt = tonumber(cfg.cloud_font_pt) or 38
  local wx_font_pt = tonumber(cfg.wx_font_pt) or 28
  local value_font_pt = tonumber(cfg.value_font_pt) or 18
  local tendency_font_pt = tonumber(cfg.tendency_font_pt) or value_font_pt
  local station_font_pt = tonumber(cfg.station_font_pt) or 14
  local n_label_pt = tonumber(cfg.n_label_pt) or 12
  local glyph_font = theme.fonts.wx_symbol or "WX Symbols"
  local value_font = theme.fonts.data

  set_rgb(cr, theme.colors.fg)
  cairo_set_line_width(cr, outer_stroke)
  cairo_new_sub_path(cr)
  cairo_arc(cr, center_x, center_y, outer_radius, 0, 2 * math.pi)
  cairo_stroke(cr)

  cairo_set_line_width(cr, circle_stroke)
  cairo_new_sub_path(cr)
  cairo_arc(cr, center_x, center_y, circle_radius, 0, 2 * math.pi)
  cairo_stroke(cr)

  for deg = 0, 350, 10 do
    local is_major = (deg % 90) == 0
    local len = is_major and major_len or minor_len
    local width = is_major and major_width or minor_width
    local ang = math.rad(deg - 90)
    local x0 = center_x + compass_radius * math.cos(ang)
    local y0 = center_y + compass_radius * math.sin(ang)
    local x1 = center_x + (compass_radius + len) * math.cos(ang)
    local y1 = center_y + (compass_radius + len) * math.sin(ang)
    cairo_set_line_width(cr, width)
    cairo_move_to(cr, x0, y0)
    cairo_line_to(cr, x1, y1)
    cairo_stroke(cr)
  end

  draw_text_center_mid(
    cr,
    center_x,
    center_y - compass_radius + 14,
    "N",
    value_font,
    n_label_pt,
    theme.colors.fg,
    CAIRO_FONT_WEIGHT_NORMAL
  )

  draw_text_center_mid(
    cr,
    center_x + (tonumber(cfg.cloud_glyph_x) or 0),
    center_y + (tonumber(cfg.cloud_glyph_y) or -3),
    data.cloud_glyph or "---",
    glyph_font,
    cloud_font_pt,
    theme.colors.fg,
    CAIRO_FONT_WEIGHT_NORMAL
  )

  draw_station_wind_barb(cr, center_x, center_y, data, cfg, theme.colors.fg)

  draw_text_right_mid(
    cr,
    center_x + (tonumber(cfg.vis_x) or -86),
    center_y + (tonumber(cfg.vis_y) or -4),
    data.visibility or "/",
    value_font,
    value_font_pt,
    theme.colors.fg,
    CAIRO_FONT_WEIGHT_NORMAL
  )

  draw_text_center_mid(
    cr,
    center_x + (tonumber(cfg.wx_x) or -62),
    center_y + (tonumber(cfg.wx_y) or 28),
    data.wx_glyph or "",
    glyph_font,
    wx_font_pt,
    theme.colors.fg,
    CAIRO_FONT_WEIGHT_NORMAL
  )

  draw_text_center_mid(
    cr,
    center_x + (tonumber(cfg.temp_x) or -50),
    center_y + (tonumber(cfg.temp_y) or -28),
    data.temp or "/",
    value_font,
    value_font_pt,
    theme.colors.fg,
    CAIRO_FONT_WEIGHT_NORMAL
  )

  draw_text_center_mid(
    cr,
    center_x + (tonumber(cfg.dew_x) or -50),
    center_y + (tonumber(cfg.dew_y) or 34),
    data.dew or "/",
    value_font,
    value_font_pt,
    theme.colors.fg,
    CAIRO_FONT_WEIGHT_NORMAL
  )

  draw_text_left_mid(
    cr,
    center_x + (tonumber(cfg.slp_x) or 36),
    center_y + (tonumber(cfg.slp_y) or -28),
    data.slp or "/",
    value_font,
    value_font_pt,
    theme.colors.fg,
    CAIRO_FONT_WEIGHT_NORMAL
  )

  if data.tendency_value and data.tendency_value ~= "" then
    draw_text_left_mid(
      cr,
      center_x + (tonumber(cfg.tendency_x) or 36),
      center_y + (tonumber(cfg.tendency_y) or 34),
      data.tendency_value,
      value_font,
      tendency_font_pt,
      theme.colors.fg,
      CAIRO_FONT_WEIGHT_NORMAL
    )
  end

  if data.tendency_glyph and data.tendency_glyph ~= "" then
    draw_text_left_mid(
      cr,
      center_x + (tonumber(cfg.tendency_x) or 36) + (tonumber(cfg.tendency_glyph_dx) or 22),
      center_y + (tonumber(cfg.tendency_y) or 34),
      data.tendency_glyph,
      glyph_font,
      tendency_font_pt,
      theme.colors.fg,
      CAIRO_FONT_WEIGHT_NORMAL
    )
  end

  if data.precip and data.precip ~= "" then
    draw_text_left_mid(
      cr,
      center_x + (tonumber(cfg.precip_x) or 36),
      center_y + (tonumber(cfg.precip_y) or 34),
      data.precip,
      value_font,
      value_font_pt,
      theme.colors.fg,
      CAIRO_FONT_WEIGHT_NORMAL
    )
  end

  draw_text_center_mid(
    cr,
    center_x,
    center_y + (tonumber(cfg.station_label_y) or 50),
    data.station or "",
    value_font,
    station_font_pt,
    theme.colors.fg,
    CAIRO_FONT_WEIGHT_NORMAL
  )

  draw_wxr_slp_meter(
    cr,
    theme,
    x + (tonumber(cfg.slp_meter_x) or 328),
    y + (tonumber(cfg.slp_meter_y) or 24),
    cfg,
    data
  )
end

local function orb_coast_rings()
  if ORB_COAST_RINGS ~= nil and #ORB_COAST_RINGS > 0 then
    return ORB_COAST_RINGS
  end

  local candidates = {
    SHARED_ASSETS_DIR .. "/data/geo/earth_coast_rings.lua",
    SHARED_ASSETS_DIR .. "/data/earth_coast_rings.lua",
  }

  for _, path in ipairs(candidates) do
    local ok, data = pcall(dofile, path)
    if ok and type(data) == "table" then
      ORB_COAST_RINGS = data
      return ORB_COAST_RINGS
    end
  end

  ORB_COAST_RINGS = {}
  return ORB_COAST_RINGS
end

local function project_lon_lat_flat(lon_deg, lat_deg, x, y, w, h)
  local lon = tonumber(lon_deg) or 0
  local lat = tonumber(lat_deg) or 0
  local px = x + (((lon + 180) / 360) * w)
  local py = y + (((90 - lat) / 180) * h)
  return px, py
end

local function draw_orb_night_box(cr, x, y, w, h, theme, cfg)
  local night_cfg = cfg.night_box or {}
  if night_cfg.enabled == false then
    return
  end

  local now = os.date("!*t")
  local utc_hour = (now.hour or 0) + ((now.min or 0) / 60) + ((now.sec or 0) / 3600)
  local box_w = w / 2

  -- Track the night half as one rectangle on the repeated map. Keep the left
  -- edge visible; the right edge may clip briefly until the map wrap catches up.
  local sunset_lon = 15 * (18 - utc_hour)
  while sunset_lon < -180 do
    sunset_lon = sunset_lon + 360
  end
  while sunset_lon >= 180 do
    sunset_lon = sunset_lon - 360
  end
  local sunset_x = x + (((sunset_lon + 180) / 360) * w)
  local raw_box_x = sunset_x

  local function stroke_box(rect_x, rect_w)
    if rect_w == nil then
      rect_w = box_w
    end
    if rect_w <= 0 then
      return
    end
    draw_rect(
      cr,
      rect_x,
      y,
      rect_w,
      h,
      tonumber(night_cfg.stroke_width) or theme.strokes.line,
      theme.colors.fg
    )
  end

  local box_x = raw_box_x
  if cfg.repeat_wrap == false then
    box_x = math.max(x, math.min(raw_box_x, x + w - box_w))
  else
    while box_x >= (x + w) do
      box_x = box_x - w
    end
    while box_x < x do
      box_x = box_x + w
    end
  end

  stroke_box(box_x, box_w)
end

local function draw_flat_coastlines(cr, x, y, w, h, theme, cfg)
  local rings = orb_coast_rings()
  if #rings == 0 then
    return
  end

  local outer_x, outer_y, outer_w, outer_h = x, y, w, h
  local edge_gap = tonumber(cfg.edge_gap) or 0
  local clip_x = outer_x + edge_gap
  local clip_y = outer_y
  local clip_w = math.max(0, outer_w - (edge_gap * 2))
  local clip_h = outer_h

  if cfg.preserve_aspect_2x1 ~= false then
    local target_w = math.min(w, h * 2)
    local target_h = target_w / 2
    x = x + ((w - target_w) / 2)
    y = y + ((h - target_h) / 2)
    w = target_w
    h = target_h
  end

  cairo_save(cr)
  cairo_rectangle(cr, clip_x, clip_y, clip_w, clip_h)
  cairo_clip(cr)
  cairo_set_line_width(cr, tonumber(cfg.stroke_width) or theme.strokes.line)
  set_rgb(cr, theme.colors.fg)

  draw_orb_night_box(cr, x, y, w, h, theme, cfg)

  if cfg.center_meridian ~= false then
    draw_rect(cr, x + (w / 2), y, 1, h, theme.strokes.line, theme.colors.fg)
  end

  if cfg.equator ~= false then
    draw_rect(cr, x, y + (h / 2), w, 1, theme.strokes.line, theme.colors.fg)
  end

  local offsets = { 0 }
  if cfg.repeat_wrap ~= false then
    offsets = { -w, 0, w }
  end

  for _, ring in ipairs(rings) do
    for _, offset_x in ipairs(offsets) do
      local started = false
      local prev_lon = nil

      for _, pt in ipairs(ring) do
        local lon = tonumber(pt[1]) or 0
        local lat = tonumber(pt[2]) or 0
        local px, py = project_lon_lat_flat(lon, lat, x + offset_x, y, w, h)

        if prev_lon ~= nil and math.abs(lon - prev_lon) > 180 then
          if started then
            cairo_stroke(cr)
            started = false
          end
        end

        if not started then
          cairo_new_path(cr)
          cairo_move_to(cr, px, py)
          started = true
        else
          cairo_line_to(cr, px, py)
        end

        prev_lon = lon
      end

      if started then
        cairo_stroke(cr)
      end
    end
  end

  cairo_restore(cr)
end

local function orb_slot_index(hour, slot_count)
  slot_count = math.max(1, tonumber(slot_count) or 16)
  local numeric = tonumber(hour)
  if numeric == nil then return nil end
  numeric = numeric % 24
  local slot_hours = 24 / slot_count
  local slot = math.floor(numeric / slot_hours) + 1
  return math.max(1, math.min(slot_count, slot))
end

local function orb_visible_slots(start_hour, end_hour, slot_count, current_slot, visible_now)
  slot_count = math.max(1, tonumber(slot_count) or 16)
  local slots = {}
  for i = 1, slot_count do
    slots[i] = " "
  end

  local start_slot = orb_slot_index(start_hour, slot_count)
  local end_slot = orb_slot_index(end_hour, slot_count)
  if start_slot == nil or end_slot == nil then
    return slots, nil, nil
  end

  local i = start_slot
  while true do
    slots[i] = "-"
    if i == end_slot then
      break
    end
    i = (i % slot_count) + 1
  end

  if start_slot == end_slot then
    slots[start_slot] = "[]"
  else
    slots[start_slot] = "["
    slots[end_slot] = "]"
  end

  if current_slot ~= nil and visible_now ~= nil then
    local slot_index = math.max(1, math.min(slot_count, tonumber(current_slot) or 1))
    if visible_now then
      if slots[slot_index] == " " then
        slots[slot_index] = "-"
      end
    elseif slots[slot_index] == "-" then
      slots[slot_index] = " "
    end
  end

  return slots, start_slot, end_slot
end

local function orb_current_slot(current_hour, slot_count)
  return orb_slot_index(current_hour, slot_count) or 1
end

local function draw_meter_cluster(cr, theme, panel, box, group_cfg, meters_cfg, meter_order, data_provider)
  local group_x = tonumber((group_cfg or {}).x) or 0
  local group_y = tonumber((group_cfg or {}).y) or 0

  for _, meter_key in ipairs(meter_order or {}) do
    local meter_cfg = meters_cfg and meters_cfg[meter_key]
    if meter_cfg then
      local meter_x = panel.x + box.x + group_x + (tonumber(meter_cfg.x) or 16)
      local meter_y = panel.y + box.y + group_y + (tonumber(meter_cfg.y) or 24)
      local meter_h = tonumber(meter_cfg.height) or 16
      local vertical_h = tonumber(meter_cfg.vertical_h) or 128
      local value = tonumber(meter_cfg.value) or 0
      local value_source = meter_cfg.value_source
      local value_provider = value_source and data_provider and data_provider[value_source]
      if type(value_provider) == "function" then
        value = tonumber(value_provider()) or value
      end

      draw_meter_header(
        cr,
        meter_x,
        meter_y,
        tonumber(meter_cfg.width) or 64,
        meter_h,
        meter_cfg.label or string.upper(meter_key),
        tonumber(meter_cfg.font_pt) or theme.text.body_sm_pt,
        vertical_h,
        meter_cfg.marks,
        theme
      )

      local bar_specs = meter_cfg.bar_specs
      if type(bar_specs) == "table" and #bar_specs > 0 then
        for _, bar_cfg in ipairs(bar_specs) do
          local bar_value = tonumber(bar_cfg.value) or value
          local bar_source = bar_cfg.value_source
          local bar_provider = bar_source and data_provider and data_provider[bar_source]
          if type(bar_provider) == "function" then
            bar_value = tonumber(bar_provider()) or bar_value
          end

          draw_meter_bar(
            cr,
            meter_x + (tonumber(bar_cfg.bar_x) or tonumber(meter_cfg.bar_x) or 0),
            meter_y + meter_h + 2,
            meter_y + meter_h + 2 + vertical_h,
            bar_value,
            tonumber(bar_cfg.bar_max) or tonumber(meter_cfg.bar_max) or 100,
            tonumber(bar_cfg.bar_width) or tonumber(meter_cfg.bar_width) or 8,
            theme.colors.fg
          )
        end
      else
        draw_meter_bar(
          cr,
          meter_x + (tonumber(meter_cfg.bar_x) or 0),
          meter_y + meter_h + 2,
          meter_y + meter_h + 2 + vertical_h,
          value,
          tonumber(meter_cfg.bar_max) or 100,
          tonumber(meter_cfg.bar_width) or 8,
          theme.colors.fg
        )
      end

      if meter_cfg.show_value ~= false then
        draw_meter_value(
          cr,
          meter_x + (tonumber(meter_cfg.value_x) or 0),
          meter_y + (tonumber(meter_cfg.value_y) or 82),
          value,
          tonumber(meter_cfg.value_font_pt) or 20,
          theme.colors.fg,
          theme
        )
      end
    end
  end
end

local function draw_two_header_table(cr, theme, base_x, base_y, left_label, right_label, left_w, gap_w, right_w, header_h, header_font_pt)
  draw_table_header(cr, base_x, base_y, left_w, header_h, left_label, header_font_pt, theme)
  draw_table_header(cr, base_x + left_w + gap_w, base_y, right_w, header_h, right_label, header_font_pt, theme)
  draw_rect(
    cr,
    base_x,
    base_y + header_h + 1,
    left_w + gap_w + right_w,
    1,
    theme.strokes.line,
    theme.colors.fg
  )
end

local function draw_grid_table(cr, theme, x, y, width, row_h, row_count, col_count)
  local col_w = width / col_count
  local total_h = row_h * row_count

  draw_rect(
    cr,
    x,
    y,
    width,
    total_h,
    theme.strokes.line,
    theme.colors.fg
  )

  for c = 1, col_count - 1 do
    local line_x = x + (col_w * c)
    draw_rect(
      cr,
      line_x,
      y,
      1,
      total_h,
      theme.strokes.line,
      theme.colors.fg
    )
  end

  for r = 1, row_count - 1 do
    local line_y = y + (row_h * r)
    draw_rect(
      cr,
      x,
      line_y,
      width,
      1,
      theme.strokes.line,
      theme.colors.fg
    )
  end

  return col_w
end

local function draw_grid(cr, theme, x, y, col_w, row_h, cols, rows)
  local width = col_w * cols
  local height = row_h * rows

  draw_rect(cr, x, y, width, height, theme.strokes.line, theme.colors.fg)

  for c = 1, cols - 1 do
    draw_rect(cr, x + (col_w * c), y, 1, height, theme.strokes.line, theme.colors.fg)
  end

  for r = 1, rows - 1 do
    draw_rect(cr, x, y + (row_h * r), width, 1, theme.strokes.line, theme.colors.fg)
  end
end

local function draw_sys_content(cr, theme, layout, panels, data)
  local sys_panel = panels.sys
  local sys_data = data and data.sys
  local boxes = sys_panel and sys_panel.boxes
  if not (sys_panel and boxes and sys_data) then return end

  if type(sys_data.status_lines) == "function" then
    local status_cfg = (((theme or {}).sys or {}).status or {})
    local x = layout.frame.x + sys_panel.x + (tonumber(status_cfg.x) or 16)
    local y = layout.frame.y + sys_panel.y + (tonumber(status_cfg.y) or 26)
    local line_step = tonumber(status_cfg.line_step) or 22
    for i, line in ipairs(sys_data.status_lines()) do
      draw_text_left(
        cr,
        x,
        y + ((i - 1) * line_step),
        line,
        theme.fonts.data,
        theme.text.body_pt,
        theme.colors.fg,
        CAIRO_FONT_WEIGHT_NORMAL
      )
    end
  end

  local cpu_box = boxes.cpu
  if cpu_box then
    local cpu_group_cfg = (((theme or {}).sys or {}).cpu_group or {})
    local meters_cfg = (((theme or {}).sys or {}).meters or {})
    draw_meter_cluster(
      cr,
      theme,
      { x = layout.frame.x + sys_panel.x, y = layout.frame.y + sys_panel.y },
      cpu_box,
      cpu_group_cfg,
      meters_cfg,
      { "cpu", "ram", "tmp" },
      sys_data
    )

    local table_cfg = (((theme or {}).sys or {}).process_table or {})
    local cpu_group_x = tonumber(cpu_group_cfg.x) or 0
    local cpu_group_y = tonumber(cpu_group_cfg.y) or 0
    local table_x = layout.frame.x + sys_panel.x + cpu_box.x + cpu_group_x + (tonumber(table_cfg.x) or 104)
    local table_y = layout.frame.y + sys_panel.y + cpu_box.y + cpu_group_y + (tonumber(table_cfg.y) or 24)
    local process_w = tonumber(table_cfg.process_w) or 176
    local percent_gap = tonumber(table_cfg.percent_gap) or 4
    local percent_w = tonumber(table_cfg.percent_w) or 52
    local header_h = tonumber(table_cfg.header_h) or 16
    local header_font_pt = tonumber(table_cfg.header_font_pt) or 18

    draw_two_header_table(
      cr,
      theme,
      table_x,
      table_y,
      "PROCESS",
      "%",
      process_w,
      percent_gap,
      percent_w,
      header_h,
      header_font_pt
    )

    if type(sys_data.process_rows) == "function" then
      local rows = sys_data.process_rows(
        tonumber(table_cfg.rows) or 6,
        tonumber(table_cfg.process_max_chars) or 18
      )
      local row_y = table_y + (tonumber(table_cfg.row_y) or 34)
      local row_step = tonumber(table_cfg.row_step) or 18
      local process_font_pt = tonumber(table_cfg.process_font_pt) or 14
      local percent_font_pt = tonumber(table_cfg.percent_font_pt) or 14

      for i, row in ipairs(rows) do
        local y = row_y + ((i - 1) * row_step)
        draw_text_left(
          cr,
          table_x,
          y,
          row.name,
          theme.fonts.data,
          process_font_pt,
          theme.colors.fg,
          CAIRO_FONT_WEIGHT_NORMAL
        )
        draw_text_right(
          cr,
          table_x + process_w + percent_gap + percent_w,
          y,
          row.pct,
          theme.fonts.data,
          percent_font_pt,
          theme.colors.fg,
          CAIRO_FONT_WEIGHT_NORMAL
        )
      end
    end
  end

  local gpu_box = boxes.gpu
  if gpu_box then
    local gpu_group_cfg = (((theme or {}).sys or {}).gpu_group or {})
    local gpu_meters_cfg = (((theme or {}).sys or {}).gpu_meters or {})
    draw_meter_cluster(
      cr,
      theme,
      { x = layout.frame.x + sys_panel.x, y = layout.frame.y + sys_panel.y },
      gpu_box,
      gpu_group_cfg,
      gpu_meters_cfg,
      { "gpu", "vrm", "gpu_tmp" },
      sys_data
    )

    local gpu_table_cfg = (((theme or {}).sys or {}).gpu_table or {})
    local gpu_group_x = tonumber(gpu_group_cfg.x) or 0
    local gpu_group_y = tonumber(gpu_group_cfg.y) or 0
    local table_x = layout.frame.x + sys_panel.x + gpu_box.x + gpu_group_x + (tonumber(gpu_table_cfg.x) or 104)
    local table_y = layout.frame.y + sys_panel.y + gpu_box.y + gpu_group_y + (tonumber(gpu_table_cfg.y) or 24)
    local component_w = tonumber(gpu_table_cfg.component_w) or 120
    local value_gap = tonumber(gpu_table_cfg.value_gap) or 2
    local value_w = tonumber(gpu_table_cfg.value_w) or 88
    local header_h = tonumber(gpu_table_cfg.header_h) or 16
    local header_font_pt = tonumber(gpu_table_cfg.header_font_pt) or 18

    draw_two_header_table(
      cr,
      theme,
      table_x,
      table_y,
      "COMPONENTS",
      "(V)",
      component_w,
      value_gap,
      value_w,
      header_h,
      header_font_pt
    )

    if type(sys_data.gpu_component_rows) == "function" then
      local rows = sys_data.gpu_component_rows()
      local row_y = table_y + (tonumber(gpu_table_cfg.row_y) or 34)
      local row_step = tonumber(gpu_table_cfg.row_step) or 18
      local component_font_pt = tonumber(gpu_table_cfg.component_font_pt) or 14
      local value_font_pt = tonumber(gpu_table_cfg.value_font_pt) or 14

      for i, row in ipairs(rows) do
        local y = row_y + ((i - 1) * row_step)
        draw_text_left(
          cr,
          table_x,
          y,
          row.name,
          theme.fonts.data,
          component_font_pt,
          theme.colors.fg,
          CAIRO_FONT_WEIGHT_NORMAL
        )
        draw_text_right(
          cr,
          table_x + component_w + value_gap + value_w,
          y,
          row.value,
          theme.fonts.data,
          value_font_pt,
          theme.colors.fg,
          CAIRO_FONT_WEIGHT_NORMAL
        )
      end
    end
  end

  local storage_box = boxes.storage
  if storage_box then
    local storage_cfg = (((theme or {}).sys or {}).storage_table or {})
    local table_x = layout.frame.x + sys_panel.x + storage_box.x + (tonumber(storage_cfg.x) or 16)
    local table_y = layout.frame.y + sys_panel.y + storage_box.y + (tonumber(storage_cfg.y) or 24)
    local table_w = tonumber(storage_cfg.width) or 456
    local header_gap = tonumber(storage_cfg.header_gap) or 2
    local header_h = tonumber(storage_cfg.header_h) or 16
    local header_font_pt = tonumber(storage_cfg.header_font_pt) or 18
    local row_h = tonumber(storage_cfg.row_h) or 21
    local row_count = tonumber(storage_cfg.rows) or 6
    local cell_font_pt = tonumber(storage_cfg.cell_font_pt) or 14
    local cell_pad_x = tonumber(storage_cfg.cell_pad_x) or 8
    local header_w = (table_w - (header_gap * 4)) / 5

    local headers = { "DISK", "SIZE", "USED", "AVAIL", "USE %" }
    for i, header in ipairs(headers) do
      local hx = table_x + ((i - 1) * (header_w + header_gap))
      draw_table_header(cr, hx, table_y, header_w, header_h, header, header_font_pt, theme)
    end

    draw_rect(
      cr,
      table_x,
      table_y + header_h + 1,
      table_w,
      1,
      theme.strokes.line,
      theme.colors.fg
    )

    local grid_y = table_y + header_h + 2
    local col_w = draw_grid_table(cr, theme, table_x, grid_y, table_w, row_h, row_count, 5)
    local rows = type(sys_data.storage_rows) == "function" and sys_data.storage_rows() or {}

    for i = 1, math.min(#rows, row_count) do
      local row = rows[i]
      local mid_y = grid_y + ((i - 1) * row_h) + (row_h / 2)

      draw_text_center_mid(
        cr,
        table_x + (col_w * 0.5),
        mid_y,
        row.disk or "",
        theme.fonts.data,
        cell_font_pt,
        theme.colors.fg,
        CAIRO_FONT_WEIGHT_NORMAL
      )

      for c, value in ipairs({ row.size or "", row.used or "", row.avail or "", row.use_pct or "" }) do
        draw_text_center_mid(
          cr,
          table_x + (col_w * (c + 0.5)),
          mid_y,
          value,
          theme.fonts.data,
          cell_font_pt,
          theme.colors.fg,
          CAIRO_FONT_WEIGHT_NORMAL
        )
      end
    end
  end

  if storage_box and type(sys_data.footer_lines) == "function" then
    local footer_cfg = (((theme or {}).sys or {}).footer or {})
    local x = layout.frame.x + sys_panel.x + (tonumber(footer_cfg.x) or 46)
    local line_step = tonumber(footer_cfg.line_step) or 22
    local gap_top = layout.frame.y + sys_panel.y + storage_box.y + storage_box.height
    local gap_bottom = layout.frame.y + sys_panel.y + sys_panel.height
    local gap_mid = gap_top + ((gap_bottom - gap_top) / 2)
    local first_y = gap_mid - (line_step / 2)
    local second_y = gap_mid + (line_step / 2)
    local lines = sys_data.footer_lines()

    draw_text_left_mid(
      cr,
      x,
      first_y,
      lines[1] or "",
      theme.fonts.data,
      theme.text.body_pt,
      theme.colors.fg,
      CAIRO_FONT_WEIGHT_NORMAL
    )

    draw_text_left_mid(
      cr,
      x,
      second_y,
      lines[2] or "",
      theme.fonts.data,
      theme.text.body_pt,
      theme.colors.fg,
      CAIRO_FONT_WEIGHT_NORMAL
    )
  end
end

local function draw_tme_content(cr, theme, layout, panels, data)
  local tme_panel = panels.tme
  local tme_data = data and data.tme
  if not (tme_panel and tme_data and type(tme_data.status_lines) == "function") then return end

  local status_cfg = (((theme or {}).tme or {}).status or {})
  local x = layout.frame.x + tme_panel.x + (tonumber(status_cfg.x) or 46)
  local y = layout.frame.y + tme_panel.y + (tonumber(status_cfg.y) or 36)
  local line_step = tonumber(status_cfg.line_step) or 22

  for i, line in ipairs(tme_data.status_lines()) do
    draw_text_left(
      cr,
      x,
      y + ((i - 1) * line_step),
      line,
      theme.fonts.data,
      theme.text.body_pt,
      theme.colors.fg,
      CAIRO_FONT_WEIGHT_NORMAL
    )
  end

  local clock_box = tme_panel.boxes and tme_panel.boxes.clock
  if not clock_box or type(tme_data.clock_rows) ~= "function" then return end

  local cfg = (((theme or {}).tme or {}).clock_table or {})
  local table_x = layout.frame.x + tme_panel.x + clock_box.x + (tonumber(cfg.x) or 16)
  local table_y = layout.frame.y + tme_panel.y + clock_box.y + (tonumber(cfg.y) or 24)
  local header_gap = tonumber(cfg.header_gap) or 2
  local header_h = tonumber(cfg.header_h) or 16
  local header_font_pt = tonumber(cfg.header_font_pt) or 18
  local row_y = table_y + (tonumber(cfg.row_y) or 34)
  local row_step = tonumber(cfg.row_step) or 18
  local row_font_pt = tonumber(cfg.row_font_pt) or 14
  local zone_w = tonumber(cfg.zone_w) or 56
  local off_w = tonumber(cfg.off_w) or 40
  local time_w = tonumber(cfg.time_w) or 56
  local date_w = tonumber(cfg.date_w) or 72
  local name_w = tonumber(cfg.name_w) or 224
  local name_pad_x = tonumber(cfg.name_pad_x) or 8

  local cols = {
    { label = "ZONE", width = zone_w },
    { label = "OFF", width = off_w },
    { label = "TIME", width = time_w },
    { label = "DATE", width = date_w },
    { label = "NAME", width = name_w },
  }

  local header_x = table_x
  for _, col in ipairs(cols) do
    draw_table_header(cr, header_x, table_y, col.width, header_h, col.label, header_font_pt, theme)
    header_x = header_x + col.width + header_gap
  end

  draw_rect(
    cr,
    table_x,
    table_y + header_h + 1,
    zone_w + off_w + time_w + date_w + name_w + (header_gap * 4),
    1,
    theme.strokes.line,
    theme.colors.fg
  )

  local rows = tme_data.clock_rows()
  for i, row in ipairs(rows) do
    local mid_y = row_y + ((i - 1) * row_step)
    local zone_x = table_x
    local off_x = zone_x + zone_w + header_gap
    local time_x = off_x + off_w + header_gap
    local date_x = time_x + time_w + header_gap
    local name_x = date_x + date_w + header_gap

    draw_text_center_mid(cr, zone_x + (zone_w * 0.5), mid_y, row.zone or "", theme.fonts.data, row_font_pt, theme.colors.fg, CAIRO_FONT_WEIGHT_NORMAL)
    draw_text_center_mid(cr, off_x + (off_w * 0.5), mid_y, row.off or "", theme.fonts.data, row_font_pt, theme.colors.fg, CAIRO_FONT_WEIGHT_NORMAL)
    draw_text_center_mid(cr, time_x + (time_w * 0.5), mid_y, row.time or "", theme.fonts.data, row_font_pt, theme.colors.fg, CAIRO_FONT_WEIGHT_NORMAL)
    draw_text_center_mid(cr, date_x + (date_w * 0.5), mid_y, row.date or "", theme.fonts.data, row_font_pt, theme.colors.fg, CAIRO_FONT_WEIGHT_NORMAL)
    draw_text_left_mid(cr, name_x + name_pad_x, mid_y, row.name or "", theme.fonts.data, row_font_pt, theme.colors.fg, CAIRO_FONT_WEIGHT_NORMAL)
  end

  local cal_box = tme_panel.boxes and tme_panel.boxes.calendar
  if not cal_box or type(tme_data.calendar_weeks) ~= "function" then
    return
  end

  local cal_cfg = (((theme or {}).tme or {}).calendar or {})
  local cal_x = layout.frame.x + tme_panel.x + cal_box.x + (tonumber(cal_cfg.x) or 16)
  local cal_y = layout.frame.y + tme_panel.y + cal_box.y + (tonumber(cal_cfg.y) or 24)
  local month_x = cal_x + (tonumber(cal_cfg.month_x) or 0)
  local header_y = cal_y + (tonumber(cal_cfg.header_y) or 8)
  local month_h = tonumber(cal_cfg.month_h) or 16
  local month_font_pt = tonumber(cal_cfg.month_font_pt) or theme.text.body_pt
  local events_x = cal_x + (tonumber(cal_cfg.events_x) or 280)
  local events_w = tonumber(cal_cfg.events_w) or 160
  local events_h = tonumber(cal_cfg.events_h) or 16
  local events_header_font_pt = tonumber(cal_cfg.events_header_font_pt) or theme.text.body_pt
  local grid_x = cal_x + (tonumber(cal_cfg.grid_x) or 0)
  local cell_w = tonumber(cal_cfg.cell_w) or 32
  local weekday_cell_h = tonumber(cal_cfg.weekday_cell_h) or 20
  local day_cell_h = tonumber(cal_cfg.day_cell_h) or 24
  local weekday_font_pt = tonumber(cal_cfg.weekday_font_pt) or theme.text.micro_pt
  local day_font_pt = tonumber(cal_cfg.day_font_pt) or theme.text.body_pt
  local today_inset = tonumber(cal_cfg.today_inset) or 2
  local overflow_alpha = tonumber(cal_cfg.overflow_alpha) or 0.5
  local overflow_color = cal_cfg.overflow_color or theme.colors.fg
  local events_body_y = tonumber(cal_cfg.events_body_y) or 32
  local events_row_step = tonumber(cal_cfg.events_row_step) or 18
  local events_font_pt = tonumber(cal_cfg.events_font_pt) or 14
  local events_max_rows = tonumber(cal_cfg.events_max_rows) or 12
  local event_marker_size = tonumber(cal_cfg.event_marker_size) or 4
  local event_marker_inset = tonumber(cal_cfg.event_marker_inset) or 4
  local month_y = header_y
  local events_y = header_y
  local month_w = cell_w * 7
  local grid_y = month_y + month_h + 1
  local event_dates = type(tme_data.calendar_event_dates) == "function" and tme_data.calendar_event_dates() or {}

  draw_table_header(
    cr,
    month_x,
    month_y,
    month_w,
    month_h,
    type(tme_data.calendar_title) == "function" and tme_data.calendar_title() or "",
    month_font_pt,
    theme
  )

  draw_table_header(cr, events_x, events_y, events_w, events_h, "EVENTS", events_header_font_pt, theme)

  draw_rect(
    cr,
    grid_x,
    grid_y,
    cell_w * 7,
    weekday_cell_h + (day_cell_h * 6),
    theme.strokes.line,
    theme.colors.fg
  )

  for c = 1, 6 do
    draw_rect(
      cr,
      grid_x + (cell_w * c),
      grid_y,
      1,
      weekday_cell_h + (day_cell_h * 6),
      theme.strokes.line,
      theme.colors.fg
    )
  end

  draw_rect(
    cr,
    grid_x,
    grid_y + weekday_cell_h,
    cell_w * 7,
    1,
    theme.strokes.line,
    theme.colors.fg
  )

  for r = 1, 5 do
    draw_rect(
      cr,
      grid_x,
      grid_y + weekday_cell_h + (day_cell_h * r),
      cell_w * 7,
      1,
      theme.strokes.line,
      theme.colors.fg
    )
  end

  local weekdays = { "S", "M", "T", "W", "T", "F", "S" }
  local weekday_today = os.date("*t").wday
  for c, label in ipairs(weekdays) do
    local weekday_x = grid_x + ((c - 1) * cell_w)
    local is_weekday_today = c == weekday_today
    if is_weekday_today then
      fill_rect(
        cr,
        weekday_x + today_inset,
        grid_y + today_inset,
        cell_w - (today_inset * 2),
        weekday_cell_h - (today_inset * 2),
        theme.colors.fg
      )
      draw_rect(
        cr,
        weekday_x + today_inset,
        grid_y + today_inset,
        cell_w - (today_inset * 2),
        weekday_cell_h - (today_inset * 2),
        theme.strokes.line,
        theme.colors.fg
      )
    end
    draw_text_center_mid(
      cr,
      weekday_x + (cell_w / 2),
      grid_y + (weekday_cell_h / 2),
      label,
      theme.fonts.data,
      weekday_font_pt,
      is_weekday_today and theme.colors.ink or theme.colors.fg,
      CAIRO_FONT_WEIGHT_NORMAL
    )
  end

  local today = type(tme_data.calendar_today) == "function" and tonumber(tme_data.calendar_today()) or -1
  local weeks = tme_data.calendar_weeks()
  for r = 1, math.min(#weeks, 6) do
    local row = weeks[r]
    for c = 1, 7 do
      local cell = row[c] or { day = 0, in_month = false }
      local day = type(cell) == "table" and (cell.day or 0) or cell
      local in_month = type(cell) == "table" and (cell.in_month ~= false) or false
      local cell_x = grid_x + ((c - 1) * cell_w)
      local cell_y = grid_y + weekday_cell_h + ((r - 1) * day_cell_h)
      if day ~= 0 then
        local cell_year = type(cell) == "table" and cell.year or nil
        local cell_month = type(cell) == "table" and cell.month or nil
        local date_key = (cell_year and cell_month) and string.format("%04d-%02d-%02d", cell_year, cell_month, day) or nil
        local has_event = date_key and event_dates[date_key] or false
        local is_today = in_month and day == today
        if is_today then
          fill_rect(
            cr,
            cell_x + today_inset,
            cell_y + today_inset,
            cell_w - (today_inset * 2),
            day_cell_h - (today_inset * 2),
            theme.colors.fg
          )
          draw_rect(
            cr,
            cell_x + today_inset,
            cell_y + today_inset,
            cell_w - (today_inset * 2),
            day_cell_h - (today_inset * 2),
            theme.strokes.line,
            theme.colors.fg
          )
        end

        if in_month or is_today then
          draw_text_center_mid(
            cr,
            cell_x + (cell_w / 2),
            cell_y + (day_cell_h / 2),
            tostring(day),
            theme.fonts.data,
            day_font_pt,
            is_today and theme.colors.ink or theme.colors.fg,
            CAIRO_FONT_WEIGHT_NORMAL
          )
        else
          draw_text_center_mid_alpha(
            cr,
            cell_x + (cell_w / 2),
            cell_y + (day_cell_h / 2),
            tostring(day),
            theme.fonts.data,
            day_font_pt,
            overflow_color,
            overflow_alpha,
            CAIRO_FONT_WEIGHT_NORMAL
          )
        end

        if has_event then
          fill_rect(
            cr,
            cell_x + cell_w - event_marker_inset - event_marker_size,
            cell_y + event_marker_inset,
            event_marker_size,
            event_marker_size,
            theme.colors.fg
          )
        end
      end
    end
  end

  if type(tme_data.calendar_events) == "function" then
    local events = tme_data.calendar_events()
    local events_start_y = cal_y + events_body_y
    local events_limit_y = cal_y + cal_box.height - 8
    local capacity = math.floor((events_limit_y - events_start_y) / events_row_step) + 1
    local max_rows = math.max(0, math.min(events_max_rows, capacity))

    for i = 1, math.min(#events, max_rows) do
      draw_text_left(
        cr,
        events_x,
        events_start_y + ((i - 1) * events_row_step),
        events[i].text,
        theme.fonts.data,
        events_font_pt,
        theme.colors.fg,
        CAIRO_FONT_WEIGHT_NORMAL
      )
    end
  end
end

local function draw_net_content(cr, theme, layout, panels, data)
  local net_panel = panels.net
  local net_data = data and data.net
  if not (net_panel and net_data and type(net_data.net_status_lines) == "function") then return end

  local box = net_panel.boxes and net_panel.boxes.primary
  if not box then return end

  local cfg = (((theme or {}).net or {}).status or {})
  local x = layout.frame.x + net_panel.x + (tonumber(cfg.x) or 46)
  local y = layout.frame.y + net_panel.y + (tonumber(cfg.y) or 36)
  local line_step = tonumber(cfg.line_step) or 22

  for i, line in ipairs(net_data.net_status_lines()) do
    draw_text_left(
      cr,
      x,
      y + ((i - 1) * line_step),
      line,
      theme.fonts.data,
      theme.text.body_pt,
      theme.colors.fg,
      CAIRO_FONT_WEIGHT_NORMAL
    )
  end

  local primary_group_cfg = (((theme or {}).net or {}).primary_group or {})
  local meters_cfg = (((theme or {}).net or {}).meters or {})
  draw_meter_cluster(
    cr,
    theme,
    { x = layout.frame.x + net_panel.x, y = layout.frame.y + net_panel.y },
    box,
    primary_group_cfg,
    meters_cfg,
    { "live", "cf_1111", "google_8888" },
    net_data
  )

  local table_cfg = (((theme or {}).net or {}).primary_table or {})
  local group_x = tonumber(primary_group_cfg.x) or 0
  local group_y = tonumber(primary_group_cfg.y) or 0
  local table_x = layout.frame.x + net_panel.x + box.x + group_x + (tonumber(table_cfg.x) or 104)
  local table_y = layout.frame.y + net_panel.y + box.y + group_y + (tonumber(table_cfg.y) or 24)
  local node_w = tonumber(table_cfg.node_w) or 96
  local value_gap = tonumber(table_cfg.value_gap) or 2
  local value_w = tonumber(table_cfg.value_w) or 108
  local header_h = tonumber(table_cfg.header_h) or 16
  local header_font_pt = tonumber(table_cfg.header_font_pt) or 18

  draw_two_header_table(
    cr,
    theme,
    table_x,
    table_y,
    "NODE",
    "(V)",
    node_w,
    value_gap,
    value_w,
    header_h,
    header_font_pt
  )

  if type(net_data.net_node_rows) == "function" then
    local rows = net_data.net_node_rows()
    local row_y = table_y + (tonumber(table_cfg.row_y) or 34)
    local row_step = tonumber(table_cfg.row_step) or 18
    local node_font_pt = tonumber(table_cfg.node_font_pt) or 14
    local value_font_pt = tonumber(table_cfg.value_font_pt) or 12

    for i, row in ipairs(rows) do
      local y = row_y + ((i - 1) * row_step)
      draw_text_left(
        cr,
        table_x,
        y,
        row.name,
        theme.fonts.data,
        node_font_pt,
        theme.colors.fg,
        CAIRO_FONT_WEIGHT_NORMAL
      )
      draw_text_right(
        cr,
        table_x + node_w + value_gap + value_w,
        y,
        row.value,
        theme.fonts.data,
        value_font_pt,
        theme.colors.fg,
        CAIRO_FONT_WEIGHT_NORMAL
      )
    end
  end

  local vlan_box = net_panel.boxes and net_panel.boxes.vlan
  if vlan_box then
    local vlan_cfg = (((theme or {}).net or {}).vlan_table or {})
    local table_x = layout.frame.x + net_panel.x + vlan_box.x + (tonumber(vlan_cfg.x) or 16)
    local table_y = layout.frame.y + net_panel.y + vlan_box.y + (tonumber(vlan_cfg.y) or 24)
    local table_w = tonumber(vlan_cfg.width) or 456
    local header_gap = tonumber(vlan_cfg.header_gap) or 2
    local gateway_w = tonumber(vlan_cfg.gateway_w) or 148
    local ms_w = tonumber(vlan_cfg.ms_w) or 56
    local speed_w = table_w - gateway_w - ms_w - (header_gap * 2)
    local header_h = tonumber(vlan_cfg.header_h) or 16
    local header_font_pt = tonumber(vlan_cfg.header_font_pt) or 18
    local row_h = tonumber(vlan_cfg.row_h) or 21
    local row_count = tonumber(vlan_cfg.rows) or 5
    local cell_font_pt = tonumber(vlan_cfg.cell_font_pt) or 14
    local speed_bar_h = tonumber(vlan_cfg.speed_bar_h) or 8
    local speed_bar_inset_x = tonumber(vlan_cfg.speed_bar_inset_x) or 8

    draw_table_header(cr, table_x, table_y, gateway_w, header_h, "GATEWAY", header_font_pt, theme)
    draw_table_header(cr, table_x + gateway_w + header_gap, table_y, speed_w, header_h, "SPEED", header_font_pt, theme)
    draw_table_header(cr, table_x + gateway_w + header_gap + speed_w + header_gap, table_y, ms_w, header_h, "MS", header_font_pt, theme)

    draw_rect(cr, table_x, table_y + header_h + 1, table_w, 1, theme.strokes.line, theme.colors.fg)

    local grid_y = table_y + header_h + 2
    local rows = type(net_data.vlan_rows) == "function" and net_data.vlan_rows() or {}
    local body_h = row_h * math.min(#rows, row_count)
    local separator_1_x = table_x + gateway_w + (header_gap * 0.5)
    local separator_2_x = table_x + gateway_w + header_gap + speed_w + (header_gap * 0.5)

    if body_h > 0 then
      draw_rect(cr, separator_1_x, grid_y, 1, body_h, theme.strokes.line, theme.colors.fg)
      draw_rect(cr, separator_2_x, grid_y, 1, body_h, theme.strokes.line, theme.colors.fg)
    end

    for i = 1, math.min(#rows, row_count) do
      local row = rows[i]
      local mid_y = grid_y + ((i - 1) * row_h) + (row_h / 2)

      draw_text_center_mid(
        cr,
        table_x + (gateway_w * 0.5),
        mid_y,
        row.gateway or "",
        theme.fonts.data,
        cell_font_pt,
        theme.colors.fg,
        CAIRO_FONT_WEIGHT_NORMAL
      )

      local speed_x = table_x + gateway_w + header_gap + speed_bar_inset_x
      local speed_bar_w = speed_w - (speed_bar_inset_x * 2)
      local speed_y = mid_y - (speed_bar_h / 2)
      draw_hbar(cr, speed_x, speed_y, speed_bar_w, speed_bar_h, row.speed_ratio, theme.colors.fg)

      draw_text_center_mid(
        cr,
        table_x + gateway_w + header_gap + speed_w + header_gap + (ms_w * 0.5),
        mid_y,
        row.ms or "",
        theme.fonts.data,
        cell_font_pt,
        theme.colors.fg,
        CAIRO_FONT_WEIGHT_NORMAL
      )
    end
  end
end

local function draw_wxr_content(cr, theme, layout, panels, data)
  local wxr_panel = panels.wxr
  local wxr_data = data and data.wxr
  if not (wxr_panel and wxr_data and type(wxr_data.status_lines) == "function") then return end

  local status_cfg = (((theme or {}).wxr or {}).status or {})
  local x = layout.frame.x + wxr_panel.x + (tonumber(status_cfg.x) or 46)
  local y = layout.frame.y + wxr_panel.y + (tonumber(status_cfg.y) or 36)
  local line_step = tonumber(status_cfg.line_step) or 22

  for i, line in ipairs(wxr_data.status_lines()) do
    draw_text_left(
      cr,
      x,
      y + ((i - 1) * line_step),
      line,
      theme.fonts.data,
      theme.text.body_pt,
      theme.colors.fg,
      CAIRO_FONT_WEIGHT_NORMAL
    )
  end

  local box = wxr_panel.boxes and wxr_panel.boxes.current
  if not box then return end

  local cfg = (((theme or {}).wxr or {}).current or {})
  local table_x = layout.frame.x + wxr_panel.x + box.x + (tonumber(cfg.x) or 16)
  local table_y = layout.frame.y + wxr_panel.y + box.y + (tonumber(cfg.y) or 24)
  local table_w = tonumber(cfg.width) or 456
  local header_gap = tonumber(cfg.header_gap) or 2
  local header_h = tonumber(cfg.header_h) or 16
  local header_font_pt = tonumber(cfg.header_font_pt) or 18
  local value_font_pt = tonumber(cfg.value_font_pt) or 18
  local symbol_font_pt = tonumber(cfg.symbol_font_pt) or 24
  local sky_symbol_y_offset = tonumber(cfg.sky_symbol_y_offset) or 0
  local rule_gap = tonumber(cfg.rule_gap) or 1
  local metar_rule_y = table_y + (tonumber(cfg.metar_rule_y) or 76)
  local metar_x = table_x + (tonumber(cfg.metar_x) or 0)
  local metar_y = table_y + (tonumber(cfg.metar_y) or 92)
  local metar_font_pt = tonumber(cfg.metar_font_pt) or 12
  local metar_line_step = tonumber(cfg.metar_line_step) or 14
  local header_w = (table_w - (header_gap * 4)) / 5
  local values_top_y = table_y + header_h + rule_gap + 1
  local value_y = values_top_y + ((metar_rule_y - values_top_y) / 2)

  local headers = type(wxr_data.current_headers) == "function" and wxr_data.current_headers() or { "SKY", "WX", "TEMP", "HUM", "WIND" }
  for i, header in ipairs(headers) do
    local hx = table_x + ((i - 1) * (header_w + header_gap))
    draw_table_header(cr, hx, table_y, header_w, header_h, header, header_font_pt, theme)
  end

  draw_rect(
    cr,
    table_x,
    table_y + header_h + rule_gap,
    table_w,
    1,
    theme.strokes.line,
    theme.colors.fg
  )

  local row = type(wxr_data.current_row) == "function" and wxr_data.current_row() or {}
  local values = {
    row.sky or "---",
    row.wx or "",
    row.temp or "---",
    row.humidity or "---",
    row.wind or "---/--",
  }

  for i, value in ipairs(values) do
    local center_x = table_x + ((i - 1) * (header_w + header_gap)) + (header_w / 2)
    local font_face = theme.fonts.data
    local font_size = value_font_pt
    local center_y = value_y
    if i <= 2 then
      font_face = theme.fonts.wx_symbol or "WX Symbols"
      font_size = symbol_font_pt
    end
    if i == 1 then
      center_y = center_y + sky_symbol_y_offset
    end
    draw_text_center_mid(
      cr,
      center_x,
      center_y,
      value,
      font_face,
      font_size,
      theme.colors.fg,
      CAIRO_FONT_WEIGHT_NORMAL
    )
  end

  draw_rect(
    cr,
    table_x,
    metar_rule_y,
    table_w,
    1,
    theme.strokes.line,
    theme.colors.fg
  )

  local metar_lines = type(wxr_data.current_metar_lines) == "function" and wxr_data.current_metar_lines() or {}
  draw_text_block_left(
    cr,
    metar_x,
    metar_y,
    metar_lines,
    theme.fonts.data,
    metar_font_pt,
    theme.colors.fg,
    metar_line_step,
      CAIRO_FONT_WEIGHT_NORMAL
  )

  local forecast_box = wxr_panel.boxes and wxr_panel.boxes.forecast
  if not forecast_box then return end

  local forecast_cfg = (((theme or {}).wxr or {}).forecast or {})
  local forecast_x = layout.frame.x + wxr_panel.x + forecast_box.x + (tonumber(forecast_cfg.x) or 16)
  local forecast_y = layout.frame.y + wxr_panel.y + forecast_box.y + (tonumber(forecast_cfg.y) or 24)
  local forecast_w = tonumber(forecast_cfg.width) or 456
  local header_gap_2 = tonumber(forecast_cfg.header_gap) or 2
  local header_h_2 = tonumber(forecast_cfg.header_h) or 16
  local header_font_pt_2 = tonumber(forecast_cfg.header_font_pt) or 18
  local row_h = tonumber(forecast_cfg.row_h) or 24
  local row_count = tonumber(forecast_cfg.rows) or 5
  local cell_font_pt = tonumber(forecast_cfg.cell_font_pt) or 14
  local symbol_font_pt_2 = tonumber(forecast_cfg.symbol_font_pt) or 24
  local sky_symbol_y_offset_2 = tonumber(forecast_cfg.sky_symbol_y_offset) or 0
  local taf_x = forecast_x + (tonumber(forecast_cfg.taf_x) or 0)
  local taf_y = forecast_y + (tonumber(forecast_cfg.taf_y) or 182)
  local taf_font_pt = tonumber(forecast_cfg.taf_font_pt) or 12
  local taf_line_step = tonumber(forecast_cfg.taf_line_step) or 14
  local header_w_2 = (forecast_w - (header_gap_2 * 5)) / 6

  local forecast_headers = type(wxr_data.forecast_headers) == "function" and wxr_data.forecast_headers() or { "DAY", "DATE", "SKY", "WX", "HIGH", "LOW" }
  for i, header in ipairs(forecast_headers) do
    local hx = forecast_x + ((i - 1) * (header_w_2 + header_gap_2))
    draw_table_header(cr, hx, forecast_y, header_w_2, header_h_2, header, header_font_pt_2, theme)
  end

  local grid_y = forecast_y + header_h_2 + 2
  local col_w = draw_grid_table(cr, theme, forecast_x, grid_y, forecast_w, row_h, row_count, 6)
  local forecast_rows = type(wxr_data.forecast_rows) == "function" and wxr_data.forecast_rows() or {}

  for r = 1, math.min(#forecast_rows, row_count) do
    local row = forecast_rows[r]
    local center_y = grid_y + ((r - 1) * row_h) + (row_h / 2)
    local values_2 = {
      row.day or "",
      row.date or "",
      row.sky or "---",
      row.wx or "",
      row.high or "---",
      row.low or "---",
    }

    for c, value in ipairs(values_2) do
      local center_x = forecast_x + ((c - 1) * col_w) + (col_w / 2)
      local font_face = theme.fonts.data
      local font_size = cell_font_pt
      local y_offset = 0
      local use_symbol_font = (c == 3 or c == 4) and value ~= "---"

      if use_symbol_font then
        font_face = theme.fonts.wx_symbol or "WX Symbols"
        font_size = symbol_font_pt_2
      end
      if c == 3 then
        y_offset = sky_symbol_y_offset_2
      end

      draw_text_center_mid(
        cr,
        center_x,
        center_y + y_offset,
        value,
        font_face,
        font_size,
        theme.colors.fg,
        CAIRO_FONT_WEIGHT_NORMAL
      )
    end
  end

  local taf_lines = type(wxr_data.forecast_taf_lines) == "function" and wxr_data.forecast_taf_lines() or {}
  draw_text_block_left(
    cr,
    taf_x,
    taf_y,
    taf_lines,
    theme.fonts.data,
    taf_font_pt,
    theme.colors.fg,
    taf_line_step,
    CAIRO_FONT_WEIGHT_NORMAL
  )

  local station_box = wxr_panel.boxes and wxr_panel.boxes.station_model
  if not station_box then return end

  local station_cfg = (((theme or {}).wxr or {}).station_model or {})
  local station_x = layout.frame.x + wxr_panel.x + station_box.x + (tonumber(station_cfg.x) or 16)
  local station_y = layout.frame.y + wxr_panel.y + station_box.y + (tonumber(station_cfg.y) or 20)
  local station_data = type(wxr_data.station_model) == "function" and wxr_data.station_model() or {}
  draw_wxr_station_model(cr, theme, station_x, station_y, station_cfg, station_data)
end

local function draw_orb_content(cr, theme, layout, panels, data)
  local orb_panel = panels.orb
  local orb_data = data and data.orb
  if not (orb_panel and orb_data and type(orb_data.status_lines) == "function") then return end

  local status_cfg = (((theme or {}).orb or {}).status or {})
  local x = layout.frame.x + orb_panel.x + (tonumber(status_cfg.x) or 46)
  local y = layout.frame.y + orb_panel.y + (tonumber(status_cfg.y) or 36)
  local line_step = tonumber(status_cfg.line_step) or 22

  for i, line in ipairs(orb_data.status_lines()) do
    draw_text_left(
      cr,
      x,
      y + ((i - 1) * line_step),
      line,
      theme.fonts.data,
      theme.text.body_pt,
      theme.colors.fg,
      CAIRO_FONT_WEIGHT_NORMAL
    )
  end

  local celestial_box = orb_panel.boxes and orb_panel.boxes.celestial
  if celestial_box and type(orb_data.celestial_rows) == "function" then
    local cfg = (((theme or {}).orb or {}).celestial or {})
    local table_x = layout.frame.x + orb_panel.x + celestial_box.x + (tonumber(cfg.x) or 8)
    local table_y = layout.frame.y + orb_panel.y + celestial_box.y + (tonumber(cfg.y) or 20)
    local table_w = tonumber(cfg.width) or (celestial_box.width - 16)
    local body_w = tonumber(cfg.body_w) or 48
    local data_w = tonumber(cfg.data_w) or 82
    local header_gap = tonumber(cfg.header_gap) or 2
    local time_w = table_w - body_w - data_w - (header_gap * 2)
    local header_h = tonumber(cfg.header_h) or 16
    local row_y = table_y + (tonumber(cfg.row_y) or 26)
    local row_h = tonumber(cfg.row_h) or 16
    local row_count = tonumber(cfg.rows) or 7
    local footer_y = table_y + (tonumber(cfg.footer_y) or 138)
    local footer_h = tonumber(cfg.footer_h) or 16
    local header_font_pt = tonumber(cfg.header_font_pt) or theme.text.body_xs_pt
    local row_font_pt = tonumber(cfg.row_font_pt) or theme.text.body_xs_pt
    local footer_font_pt = tonumber(cfg.footer_font_pt) or theme.text.micro_pt
    local footer_label_inset = tonumber(cfg.footer_label_inset) or 10
    local marker_size = tonumber(cfg.marker_size) or 8
    local slot_count = tonumber(cfg.slot_count) or 16
    local band_y_nudge = tonumber(cfg.band_y_nudge) or 0
    local time_x = table_x + body_w + header_gap
    local data_x = time_x + time_w + header_gap
    local slot_w = time_w / slot_count

    draw_table_header(cr, table_x, table_y, body_w, header_h, "BODY", header_font_pt, theme)
    draw_table_header(cr, time_x, table_y, time_w, header_h, "TIME", header_font_pt, theme)
    draw_table_header(cr, data_x, table_y, data_w, header_h, "DATA", header_font_pt, theme)
    draw_rect(cr, table_x, table_y + header_h + 1, table_w, 1, theme.strokes.line, theme.colors.fg)
    draw_rect(
      cr,
      time_x - (header_gap * 0.5),
      table_y + header_h + 2,
      1,
      footer_y - (table_y + header_h + 2),
      theme.strokes.line,
      theme.colors.fg
    )
    draw_rect(
      cr,
      data_x - (header_gap * 0.5),
      table_y + header_h + 2,
      1,
      footer_y - (table_y + header_h + 2),
      theme.strokes.line,
      theme.colors.fg
    )

    draw_table_header(cr, table_x, footer_y, body_w, footer_h, "", footer_font_pt, theme)
    draw_table_header(cr, data_x, footer_y, data_w, footer_h, "HDG / ALT", footer_font_pt, theme)

    local rows = orb_data.celestial_rows()
    local current_hour = type(orb_data.current_hour) == "function" and orb_data.current_hour() or 0
    local current_slot = orb_current_slot(current_hour, slot_count)

    for i = 1, math.min(#rows, row_count) do
      local row = rows[i]
      local mid_y = row_y + ((i - 1) * row_h)
      local band_slots = orb_visible_slots(row.start_hour, row.end_hour, slot_count, current_slot, row.visible_now)

      draw_text_left_mid(
        cr,
        table_x + 8,
        mid_y,
        row.body or "",
        theme.fonts.data,
        row_font_pt,
        theme.colors.fg,
        CAIRO_FONT_WEIGHT_NORMAL
      )

      for slot_index, glyph in ipairs(band_slots) do
        if glyph ~= " " then
          local glyph_y = mid_y
          if glyph == "-" then
            glyph_y = mid_y + band_y_nudge
          end
          draw_text_center_mid(
            cr,
            time_x + ((slot_index - 0.5) * slot_w),
            glyph_y,
            glyph,
            theme.fonts.data,
            row_font_pt,
            theme.colors.fg,
            CAIRO_FONT_WEIGHT_NORMAL
          )
        end
      end

      draw_text_left_mid(
        cr,
        data_x + 8,
        mid_y,
        row.data or "",
        theme.fonts.data,
        row_font_pt,
        theme.colors.fg,
        CAIRO_FONT_WEIGHT_NORMAL
      )

      local marker_x = time_x + ((current_slot - 0.5) * slot_w)

      fill_rect(
        cr,
        marker_x - (marker_size / 2),
        mid_y - math.floor(marker_size / 2),
        marker_size,
        marker_size,
        theme.colors.fg
      )
    end

    local markers = type(orb_data.time_markers) == "function" and orb_data.time_markers() or {}
    if #markers > 0 then
      local cell_count = math.max(1, #markers - 1)
      local marker_w = time_w / cell_count
      for i, marker in ipairs(markers) do
        local cell_x = time_x + (math.min(i - 1, cell_count - 1) * marker_w)
        if i <= cell_count then
          fill_rect(cr, cell_x, footer_y, marker_w, footer_h, theme.colors.fg)
        end

        local marker_hour = (i - 1) * 3
        local label_x = time_x + ((marker_hour / 24) * time_w)
        if i == 1 then
          label_x = label_x + footer_label_inset
        elseif i == #markers then
          label_x = label_x - footer_label_inset
        end

        draw_text_center_mid(
          cr,
          label_x,
          footer_y + (footer_h / 2),
          marker,
          theme.fonts.data,
          footer_font_pt,
          theme.colors.ink,
          CAIRO_FONT_WEIGHT_NORMAL
        )
      end
    end
  end

  local terminator_box = orb_panel.boxes and orb_panel.boxes.terminator
  if terminator_box then
    local term_cfg = (((theme or {}).orb or {}).terminator or {})
    local map_x = layout.frame.x + orb_panel.x + terminator_box.x + (tonumber(term_cfg.x) or 16)
    local map_y = layout.frame.y + orb_panel.y + terminator_box.y + (tonumber(term_cfg.y) or 16)
    local map_w = tonumber(term_cfg.width) or (terminator_box.width - 32)
    local map_h = tonumber(term_cfg.height) or (terminator_box.height - 32)
    draw_flat_coastlines(cr, map_x, map_y, map_w, map_h, theme, term_cfg)
  end

  if type(orb_data.legend_rows) ~= "function" then
    return
  end

  local legend_cfg = (((theme or {}).orb or {}).legend or {})
  local legend_x = layout.frame.x + orb_panel.x + (tonumber(legend_cfg.x) or 46)
  local legend_y = layout.frame.y + orb_panel.y + (tonumber(legend_cfg.y) or 310)
  local legend_step = tonumber(legend_cfg.line_step) or 24
  local symbol_w = tonumber(legend_cfg.symbol_w) or 44
  local square_size = tonumber(legend_cfg.square_size) or 10
  local legend_font_pt = tonumber(legend_cfg.font_pt) or theme.text.body_xs_pt
  local legend_center_x = layout.frame.x + orb_panel.x + (orb_panel.width / 2)

  for i, row in ipairs(orb_data.legend_rows()) do
    local row_y = legend_y + ((i - 1) * legend_step)
    local symbol = row.symbol or ""
    local label = row.label or ""

    if symbol == "square" then
      local legend_text = "= " .. label
      cairo_select_font_face(
        cr,
        theme.fonts.data,
        CAIRO_FONT_SLANT_NORMAL,
        CAIRO_FONT_WEIGHT_NORMAL
      )
      cairo_set_font_size(cr, legend_font_pt)
      local ext = cairo_text_extents_t:create()
      cairo_text_extents(cr, legend_text, ext)
      local total_w = square_size + math.max(symbol_w - square_size, 0) + ext.width
      local row_x = legend_center_x - (total_w / 2)

      fill_rect(
        cr,
        row_x,
        row_y - math.floor(square_size / 2),
        square_size,
        square_size,
        theme.colors.fg
      )
      draw_text_left_mid(
        cr,
        row_x + symbol_w,
        row_y,
        legend_text,
        theme.fonts.data,
        legend_font_pt,
        theme.colors.fg,
        CAIRO_FONT_WEIGHT_NORMAL
      )
    elseif symbol:match("^%d%d%d%s+[+%-]%d%d$") then
      draw_text_center_mid(
        cr,
        legend_center_x,
        row_y,
        string.format("%s = %s", symbol, label),
        theme.fonts.data,
        legend_font_pt,
        theme.colors.fg,
        CAIRO_FONT_WEIGHT_NORMAL
      )
    else
      draw_text_center_mid(
        cr,
        legend_center_x,
        row_y,
        string.format("%s = %s", symbol, label),
        theme.fonts.data,
        legend_font_pt,
        theme.colors.fg,
        CAIRO_FONT_WEIGHT_NORMAL
      )
    end
  end
end

local function draw_env_content(cr, theme, layout, panels, data)
  local env_panel = panels.env
  local env_data = data and data.env
  if not (env_panel and env_data and type(env_data.status_lines) == "function") then return end

  local status_cfg = (((theme or {}).env or {}).status or {})
  local x = layout.frame.x + env_panel.x + (tonumber(status_cfg.x) or 46)
  local y = layout.frame.y + env_panel.y + (tonumber(status_cfg.y) or 36)
  local line_step = tonumber(status_cfg.line_step) or 22

  for i, line in ipairs(env_data.status_lines()) do
    draw_text_left(
      cr,
      x,
      y + ((i - 1) * line_step),
      line,
      theme.fonts.data,
      theme.text.body_pt,
      theme.colors.fg,
      CAIRO_FONT_WEIGHT_NORMAL
    )
  end

  local atmos_box = env_panel.boxes and env_panel.boxes.atmos
  if not atmos_box then return end

  local cfg = (((theme or {}).env or {}).atmos or {})
  local table_cfg = {}
  for k, v in pairs(cfg) do
    table_cfg[k] = v
  end
  table_cfg.height = atmos_box.height - (2 * (tonumber(cfg.y) or 20))

  local inner_x = layout.frame.x + env_panel.x + atmos_box.x + (tonumber(cfg.x) or 16)
  local inner_y = layout.frame.y + env_panel.y + atmos_box.y + (tonumber(cfg.y) or 20)
  local inner_w = tonumber(cfg.width) or (atmos_box.width - 32)
  local meter_w = tonumber(cfg.meter_w) or 64
  local solar_w = tonumber(cfg.solar_meter_w) or 136
  local meter_gap = tonumber(cfg.meter_gap) or 16
  local center_w = inner_w - meter_w - solar_w - (meter_gap * 2)
  local center_x = inner_x + meter_w + meter_gap
  local solar_x = center_x + center_w + meter_gap
  local table_gap = tonumber(cfg.table_gap) or 16
  local header_h = tonumber(cfg.header_h) or 16
  local row_h = tonumber(cfg.row_h) or 16
  local pollution_rows = tonumber(cfg.pollution_rows) or 7
  local pollen_rows = tonumber(cfg.pollen_rows) or 4
  local pollen_y = inner_y + header_h + 12 + (pollution_rows * row_h) + table_gap

  local aqi_airnow_value = type(env_data.aqi_airnow_value) == "function" and env_data.aqi_airnow_value() or 0
  local aqi_owm_value = type(env_data.aqi_owm_value) == "function" and env_data.aqi_owm_value() or 0
  local uv_value = type(env_data.solar_uv_value) == "function" and env_data.solar_uv_value() or 0
  local rad_value = type(env_data.solar_rad_value) == "function" and env_data.solar_rad_value() or 0
  local uv_text = type(env_data.solar_uv_text) == "function" and env_data.solar_uv_text() or tostring(uv_value)
  local rad_text = type(env_data.solar_rad_text) == "function" and env_data.solar_rad_text() or tostring(rad_value)
  local aqi_value_spread = tonumber(cfg.aqi_value_spread) or 22
  local aqi_value_y = tonumber(cfg.aqi_value_y) or 34
  local aqi_value_font_pt = tonumber(cfg.aqi_value_font_pt) or 12
  local aqi_value_center_x = inner_x + (meter_w / 2)
  local solar_value_spread = tonumber(cfg.solar_value_spread) or 22
  local solar_value_center_x = solar_x + (solar_w / 2)
  local solar_value_y = (table_cfg.height / 2)

  draw_env_meter(
    cr,
    theme,
    inner_x,
    inner_y,
    meter_w,
    table_cfg,
    "AQI",
    nil,
    {
      {
        value = aqi_airnow_value,
        max_value = 300,
        value_center_x = aqi_value_center_x - aqi_value_spread,
        value_y = aqi_value_y,
        value_font_pt = aqi_value_font_pt,
      },
      {
        value = aqi_owm_value,
        max_value = tonumber(cfg.owm_aqi_bar_max) or 5,
        value_center_x = aqi_value_center_x + aqi_value_spread,
        value_y = aqi_value_y,
        value_font_pt = aqi_value_font_pt,
      },
    },
    "ANW",
    "OWM"
  )

  draw_env_atmos_table(
    cr,
    theme,
    center_x,
    inner_y,
    center_w,
    table_cfg,
    "POLLUTION",
    type(env_data.pollution_rows) == "function" and env_data.pollution_rows() or {},
    pollution_rows
  )

  draw_env_atmos_table(
    cr,
    theme,
    center_x,
    pollen_y,
    center_w,
    table_cfg,
    "POLLEN",
    type(env_data.pollen_rows) == "function" and env_data.pollen_rows() or {},
    pollen_rows
  )

  draw_env_meter(
    cr,
    theme,
    solar_x,
    inner_y,
    solar_w,
    table_cfg,
    "SOLAR",
    nil,
    {
      {
        value = uv_value,
        value_text = uv_text,
        max_value = 100,
        value_center_x = solar_value_center_x - solar_value_spread,
        value_y = solar_value_y,
      },
      {
        value = rad_value,
        value_text = rad_text,
        max_value = 100,
        value_center_x = solar_value_center_x + solar_value_spread,
        value_y = solar_value_y,
      },
    },
    "UV",
    "RAD"
  )
end

function M.draw(cr, theme, layout, panels, data)
  fill_rect(
    cr,
    layout.frame.x,
    layout.frame.y,
    layout.frame.width,
    layout.frame.height,
    theme.colors.bg
  )

  draw_rect(
    cr,
    layout.frame.x,
    layout.frame.y,
    layout.frame.width,
    layout.frame.height,
    theme.strokes.line,
    theme.colors.fg
  )

  for _, panel in ipairs({
    panels.sys,
    panels.tme,
    panels.wxr,
    panels.net,
    panels.orb,
    panels.env,
  }) do
    draw_rect(
      cr,
      layout.frame.x + panel.x,
      layout.frame.y + panel.y,
      panel.width,
      panel.height,
      theme.strokes.line,
      theme.colors.fg
    )
    draw_panel_boxes(cr, panel, theme, layout.frame)
    draw_title(cr, panel, theme, layout.frame)
    draw_panel_footer_label(cr, panel, theme, layout.frame)
    draw_panel_box_titles(cr, panel, theme, layout.frame, data and data[string.lower(panel.title or "")])
  end

  draw_sys_content(cr, theme, layout, panels, data)
  draw_tme_content(cr, theme, layout, panels, data)
  draw_wxr_content(cr, theme, layout, panels, data)
  draw_net_content(cr, theme, layout, panels, data)
  draw_orb_content(cr, theme, layout, panels, data)
  draw_env_content(cr, theme, layout, panels, data)
end

return M
