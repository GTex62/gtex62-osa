local theme = {}
local HOME = os.getenv("HOME") or ""
local ENGINE_DIR = os.getenv("GTEX62_CONKY_ENGINE_DIR") or (HOME .. "/.config/conky/gtex62-conky-engine")

local function load_engine_runtime()
  local ok, runtime = pcall(dofile, ENGINE_DIR .. "/lua/runtime/window.lua")
  if ok and type(runtime) == "table" then
    return runtime
  end
  return nil
end

local engine_runtime = load_engine_runtime()

-- Monitor selection (0 = primary, 1 = secondary)
theme.monitor_head = 1

theme.colors = {
  bg = { 0.0, 0.0, 0.0 },
  fg = { 1.0, 1.0, 0.0 },
  ink = { 0.0, 0.0, 0.0 },
}

theme.strokes = {
  line = 1,
}

theme.fonts = {
  title = "Eurostile LT Std",
  data = "GTex62 OSA",
  wx_symbol = "WX Symbols",
}

theme.text = {
  panel_title_pt = 21,
  body_pt = 18,
  body_sm_pt = 16,
  body_xs_pt = 14,
  micro_pt = 12,
}

theme.spacing = {
  grid = 8,
  title_pad_x = 32,
  title_clearance = 8,
  box_title_x = 20,
}

theme.sys = {
  status = {
    x = 46,
    y = 36,
    line_step = 22,
  },
  footer = {
    x = 46,
    line_step = 22,
  },
  cpu_group = {
    x = 0,
    y = -2,
  },
  gpu_group = {
    x = 0,
    y = -2,
  },
  meters = {
    cpu = {
      x = 16,
      y = 24,
      width = 64,
      height = 16,
      font_pt = 18,
      label = "CPU",
      vertical_h = 128,
      value_source = "cpu_usage_percent",
      value = 58,
      value_font_pt = 20,
      value_x = 0,
      value_y = 82,
      bar_x = 44,
      bar_width = 8,
      marks = {
        short = 4,
        medium = 6,
        long = 8,
      },
    },
    ram = {
      x = 336,
      y = 24,
      width = 64,
      height = 16,
      font_pt = 18,
      label = "RAM",
      vertical_h = 128,
      value_source = "ram_usage_percent",
      value = 43,
      value_font_pt = 20,
      value_x = 0,
      value_y = 82,
      bar_x = 44,
      bar_width = 8,
      marks = {
        short = 4,
        medium = 6,
        long = 8,
      },
    },
    tmp = {
      x = 408,
      y = 24,
      width = 64,
      height = 16,
      font_pt = 18,
      label = "TMP",
      vertical_h = 128,
      value_source = "cpu_temp_celsius",
      temp_policy = "avg_core",
      value = 76,
      value_font_pt = 20,
      value_x = 0,
      value_y = 82,
      bar_x = 44,
      bar_width = 8,
      marks = {
        short = 4,
        medium = 6,
        long = 8,
      },
    },
  },
  process_table = {
    x = 104,
    y = 24,
    process_w = 160,
    percent_gap = 2,
    percent_w = 48,
    header_h = 16,
    header_font_pt = 18,
    row_y = 34,
    rows = 6,
    row_step = 18,
    process_font_pt = 14,
    percent_font_pt = 14,
    process_max_chars = 18,
  },
  gpu_meters = {
    gpu = {
      x = 16,
      y = 24,
      width = 64,
      height = 16,
      font_pt = 18,
      label = "GPU",
      vertical_h = 128,
      value_source = "gpu_usage_percent",
      value = 19,
      value_font_pt = 20,
      value_x = 0,
      value_y = 82,
      bar_x = 44,
      bar_width = 8,
      marks = {
        short = 4,
        medium = 6,
        long = 8,
      },
    },
    vrm = {
      x = 336,
      y = 24,
      width = 64,
      height = 16,
      font_pt = 18,
      label = "VRM",
      vertical_h = 128,
      value_source = "gpu_vram_percent",
      value = 8,
      value_font_pt = 20,
      value_x = 0,
      value_y = 82,
      bar_x = 44,
      bar_width = 8,
      marks = {
        short = 4,
        medium = 6,
        long = 8,
      },
    },
    gpu_tmp = {
      x = 408,
      y = 24,
      width = 64,
      height = 16,
      font_pt = 18,
      label = "TMP",
      vertical_h = 128,
      value_source = "gpu_temp_celsius",
      value = 34,
      value_font_pt = 20,
      value_x = 0,
      value_y = 82,
      bar_x = 44,
      bar_width = 8,
      marks = {
        short = 4,
        medium = 6,
        long = 8,
      },
    },
  },
  gpu_table = {
    x = 104,
    y = 24,
    component_w = 120,
    value_gap = 2,
    value_w = 88,
    header_h = 16,
    header_font_pt = 18,
    row_y = 34,
    rows = 2,
    row_step = 18,
    component_font_pt = 14,
    value_font_pt = 14,
  },
  storage_table = {
    x = 16,
    y = 24,
    width = 456,
    header_gap = 2,
    header_h = 16,
    header_font_pt = 18,
    row_h = 21,
    rows = 6,
    cell_font_pt = 14,
    cell_pad_x = 8,
  },
}

theme.tme = {
  status = {
    x = 46,
    y = 36,
    line_step = 22,
  },
  clock_table = {
    x = 16,
    y = 24,
    header_gap = 2,
    header_h = 16,
    header_font_pt = 18,
    row_y = 34,
    row_step = 24,
    rows = 5,
    row_font_pt = 14,
    zone_w = 56,
    off_w = 40,
    time_w = 56,
    date_w = 72,
    name_w = 224,
    name_pad_x = 8,
  },
  calendar = {
    x = 16,
    y = 24,
    month_x = 0,
    header_y = 8,
    month_h = 16,
    month_font_pt = 18,
    events_x = 264,
    events_w = 192,
    events_h = 16,
    events_gap = 16,
    events_header_font_pt = 18,
    grid_x = 0,
    cell_w = 36,
    weekday_cell_h = 16,
    day_cell_h = 28,
    weekday_font_pt = 12,
    day_font_pt = 14,
    today_inset = 2,
    overflow_alpha = 0.5,
    overflow_color = { 1.0, 1.0, 0.0 },
    events_body_y = 40,
    events_row_step = 18,
    events_font_pt = 14,
    events_max_rows = 12,
    event_marker_size = 4,
    event_marker_inset = 2,
  },
}

theme.wxr = {
  status = {
    x = 46,
    y = 36,
    line_step = 22,
  },
  current = {
    x = 16,
    y = 24,
    width = 456,
    header_gap = 2,
    header_h = 16,
    header_font_pt = 18,
    rule_gap = 1,
    value_font_pt = 18,
    symbol_font_pt = 32,
    sky_symbol_y_offset = -6,
    metar_rule_y = 60,
    metar_x = 0,
    metar_y = 76,
    metar_font_pt = 14,
    metar_line_step = 14,
    metar_max_lines = 7,
    metar_wrap_col = 58,
  },
  forecast = {
    x = 16,
    y = 24,
    width = 456,
    header_gap = 2,
    header_h = 16,
    header_font_pt = 18,
    row_h = 24,
    rows = 5,
    cell_font_pt = 14,
    symbol_font_pt = 20,
    sky_symbol_y_offset = -4,
    taf_x = 0,
    taf_y = 158,
    taf_font_pt = 14,
    taf_line_step = 14,
    taf_max_lines = 8,
    taf_wrap_col = 58,
    taf_indent_cols = 2,
  },
  station_model = {
    x = -80,
    y = 24,
    width = 456,
    height = 184,
    center_x = 228,
    center_y = 88,
    circle_radius = 80,
    circle_stroke = 0,
    outer_radius = 80,
    outer_stroke = 0,
    compass_radius = 88,
    compass_major_len = 8,
    compass_minor_len = 4,
    compass_major_width = 2,
    compass_minor_width = 1,
    n_label_pt = 16,
    cloud_font_pt = 30,
    cloud_glyph_x = 0,
    cloud_glyph_y = -6,
    wx_font_pt = 28,
    value_font_pt = 18,
    tendency_font_pt = 18,
    station_font_pt = 14,
    vis_x = -56,
    vis_y = 0,
    wx_x = -36,
    wx_y = 0,
    temp_x = -44,
    temp_y = -34,
    dew_x = -44,
    dew_y = 34,
    slp_x = 30,
    slp_y = -34,
    tendency_x = 34,
    tendency_y = 0,
    tendency_glyph_dx = 30,
    precip_x = 30,
    precip_y = 34,
    wind_staff_len = 30,
    wind_staff_start = 18,
    wind_line_width = 2,
    wind_barb_len = 18,
    wind_half_len = 12,
    wind_spacing = 7,
    wind_angle_deg = 60,
    wind_pennant_len = 15,
    wind_pennant_width = 8,
    station_label_y = 70,
    slp_meter_x = 378,
    slp_meter_y = 8,
    slp_meter_w = 128,
    slp_meter_header_h = 16,
    slp_meter_body_h = 128,
    slp_meter_footer_h = 16,
    slp_meter_footer_gap = 2,
    slp_meter_font_pt = 18,
    slp_meter_value_font_pt = 16,
    slp_meter_footer_font_pt = 16,
    slp_meter_bar_w = 8,
    slp_meter_min_hpa = 950,
    slp_meter_max_hpa = 1050,
    slp_meter_value_spread = 6,
  },
}

theme.net = {
  status = {
    x = 46,
    y = 36,
    line_step = 22,
  },
  primary_group = {
    x = 0,
    y = -2,
  },
  meters = {
    live = {
      x = 16,
      y = 24,
      width = 64,
      height = 16,
      font_pt = 18,
      label = "LIVE",
      vertical_h = 128,
      show_value = false,
      bar_specs = {
        {
          value_source = "live_upload_kib",
          bar_x = 14,
          bar_width = 8,
          bar_max = 128,
        },
        {
          value_source = "live_download_kib",
          bar_x = 44,
          bar_width = 8,
          bar_max = 256,
        },
      },
      marks = {
        short = 4,
        medium = 6,
        long = 8,
      },
    },
    cf_1111 = {
      x = 336,
      y = 24,
      width = 64,
      height = 16,
      font_pt = 18,
      label = "1.1.1",
      vertical_h = 128,
      value_source = "ping_1111_ms",
      bar_max = 250,
      value_font_pt = 20,
      value_x = 0,
      value_y = 82,
      bar_x = 44,
      bar_width = 8,
      marks = {
        short = 4,
        medium = 6,
        long = 8,
      },
    },
    google_8888 = {
      x = 408,
      y = 24,
      width = 64,
      height = 16,
      font_pt = 18,
      label = "8.8.8",
      vertical_h = 128,
      value_source = "ping_8888_ms",
      bar_max = 250,
      value_font_pt = 20,
      value_x = 0,
      value_y = 82,
      bar_x = 44,
      bar_width = 8,
      marks = {
        short = 4,
        medium = 6,
        long = 8,
      },
    },
  },
  primary_table = {
    x = 104,
    y = 24,
    node_w = 96,
    value_gap = 2,
    value_w = 108,
    header_h = 16,
    header_font_pt = 18,
    row_y = 34,
    rows = 5,
    row_step = 18,
    node_font_pt = 14,
    value_font_pt = 12,
  },
  vlan_table = {
    x = 16,
    y = 16,
    width = 456,
    header_gap = 2,
    gateway_w = 116,
    ms_w = 56,
    header_h = 16,
    header_font_pt = 18,
    row_h = 18,
    rows = 5,
    cell_font_pt = 14,
    speed_bar_h = 8,
    speed_bar_inset_x = 16,
  },
}

theme.orb = {
  status = {
    x = 46,
    y = 36,
    line_step = 22,
  },
  celestial = {
    x = 8,
    y = 20,
    width = 456,
    body_w = 48,
    data_w = 82,
    header_gap = 2,
    header_h = 16,
    row_y = 34,
    row_h = 16,
    rows = 7,
    footer_y = 146,
    footer_h = 16,
    header_font_pt = 14,
    row_font_pt = 14,
    footer_font_pt = 12,
    footer_label_inset = 10,
    marker_size = 8,
    slot_count = 48,
    band_y_nudge = 2,
  },
  legend = {
    x = 46,
    y = 302,
    line_step = 20,
    symbol_w = 18,
    square_size = 10,
    font_pt = 14,
  },
  terminator = {
    x = 16,
    y = 16,
    width = 456,
    height = 152,
    stroke_width = 1,
    edge_gap = 16,
    preserve_aspect_2x1 = true,
    repeat_wrap = true,
    center_meridian = false,
    equator = false,
    night_box = {
      enabled = true,
      stroke_width = 1,
    },
  },
}

function theme.session_text_scale()
  if engine_runtime and engine_runtime.session_text_scale then
    return engine_runtime.session_text_scale()
  end
  return 1.0
end

function theme.window_size(frame)
  if engine_runtime and engine_runtime.window_size then
    return engine_runtime.window_size(frame)
  end
  frame = frame or {}
  local scale = theme.session_text_scale()
  return {
    width = math.floor(((frame.width or 1760) / scale) + 0.5),
    height = math.floor(((frame.height or 1400) / scale) + 0.5),
  }
end

function theme.engine_dir()
  return ENGINE_DIR
end

function theme.using_engine_runtime()
  return engine_runtime ~= nil
end

return theme
