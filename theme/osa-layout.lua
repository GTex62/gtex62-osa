local layout = {}

-- The OSA chassis is authored in one live coordinate space.
-- Conky window dimensions are derived at runtime from this frame.
layout.frame = {
  x = 0,
  y = 0,
  width = 1736,
  height = 1368,
}

layout.columns = {
  left = { x = 28, width = 520 },
  mid = { x = 604, width = 520 },
  right = { x = 1188, width = 520 },
}

layout.rows = {
  top = 40,
  gap = 56,
}

return layout
