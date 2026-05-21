local layout = {}

-- The OSA chassis is authored in one live coordinate space.
-- Conky window dimensions are derived at runtime from this frame.
layout.frame = {
  x = 0,
  y = 0,
  width = 1736,
  height = 1368,
}

-- scale_mode: "manual" uses layout.scale directly.
-- scale_mode: "auto" computes scale from CONKY_SCREEN_W/H vs frame dimensions.
-- Frame dimensions are the base (scale=1.0) coordinate space.
layout.scale_mode = "manual"
layout.scale = 1.00

layout.columns = {
  left  = { x = 28, width = 520 },
  mid   = { x = 608, width = 520 },
  right = { x = 1188, width = 520 },
}

layout.rows = {
  top = 40,
  gap = 56,
}

-- scaled_frame: pre-computed for Conky window sizing at conf load time.
-- In auto mode this reads CONKY_SCREEN_W/H; export them before launching Conky.
local function _compute_scale()
  if layout.scale_mode == "auto" then
    local w = tonumber(os.getenv("CONKY_SCREEN_W"))
    local h = tonumber(os.getenv("CONKY_SCREEN_H"))
    local bw = layout.frame.width
    local bh = layout.frame.height
    if w and h and bw > 0 and bh > 0 then
      return math.min(w / bw, h / bh)
    end
  end
  return tonumber(layout.scale) or 1.0
end

local _s = _compute_scale()
layout.scaled_frame = {
  x      = math.floor(layout.frame.x * _s + 0.5),
  y      = math.floor(layout.frame.y * _s + 0.5),
  width  = math.floor(layout.frame.width * _s + 0.5),
  height = math.floor(layout.frame.height * _s + 0.5),
}

return layout
