require "cairo"

local HOME = os.getenv("HOME") or ""
local SUITE_DIR = os.getenv("CONKY_SUITE_DIR") or (HOME .. "/.config/conky/gtex62-osa")

local runtime = nil
local frame = nil
local sys = nil
local tme = nil
local wxr = nil
local net = nil
local orb = nil

local function ensure_loaded()
  if runtime ~= nil then
    return
  end

  runtime = dofile(SUITE_DIR .. "/lua/suite/runtime.lua")
  frame = dofile(SUITE_DIR .. "/lua/ui/frame.lua")
  sys = dofile(SUITE_DIR .. "/lua/suite/sys.lua")
  tme = dofile(SUITE_DIR .. "/lua/suite/tme.lua")
  wxr = dofile(SUITE_DIR .. "/lua/suite/wxr.lua")
  net = dofile(SUITE_DIR .. "/lua/suite/net.lua")
  orb = dofile(SUITE_DIR .. "/lua/suite/orb.lua")
end

function conky_draw_osa()
  if conky_window == nil then return end
  ensure_loaded()

  local w = conky_window.width
  local h = conky_window.height
  local surface = cairo_xlib_surface_create(
    conky_window.display,
    conky_window.drawable,
    conky_window.visual,
    w,
    h
  )
  local cr = cairo_create(surface)
  local state = runtime.get_state()

  if type(frame.draw) == "function" then
    frame.draw(cr, state.theme, state.layout, state.panels, {
      sys = sys,
      tme = tme,
      wxr = wxr,
      net = net,
      orb = orb,
    })
  end

  cairo_destroy(cr)
  cairo_surface_destroy(surface)
end
