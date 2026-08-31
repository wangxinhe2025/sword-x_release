-- 柱状频谱：engine.vis_rect 接管 + engine.fill_rect 实心柱

local BANDS = 18
local SEGS = 10
local levels = {}
local peaks = {}

local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

local function lerp(a, b, t)
  return a + (b - a) * t
end

local function bar_color(t)
  if t < 0.55 then
    local u = t / 0.55
    return math.floor(lerp(50, 240, u)),
           math.floor(lerp(200, 220, u)),
           math.floor(lerp(100, 50, u))
  end
  local u = (t - 0.55) / 0.45
  return math.floor(lerp(240, 255, u)),
         math.floor(lerp(220, 60, u)),
         math.floor(lerp(50, 40, u))
end

local function rebuild()
  levels, peaks = {}, {}
  for i = 1, BANDS do
    levels[i] = 0
    peaks[i] = 0
  end
end

function on_init(w, h)
  rebuild()
  engine.set_paint_while_drag(true)
end

function on_resize(w, h)
end

function on_frame(dt, w, h)
  if w < 8 or h < 8 then
    return
  end
  if #levels == 0 then
    rebuild()
  end

  local vx, vy, vw, vh = engine.vis_rect()
  if not vx or vw < 12 or vh < 8 then
    return
  end

  local playing = engine.is_playing()
  local raw = playing and engine.vis_levels(BANDS) or nil

  local gap = math.max(1.5, vw * 0.012)
  local slot = vw / BANDS
  local barW = math.max(3, slot - gap)

  for i = 1, BANDS do
    local target = (raw and raw[i]) or 0
    local cur = levels[i] or 0
    if target > cur then
      cur = lerp(cur, target, math.min(1, dt * 22))
    else
      cur = lerp(cur, target, math.min(1, dt * 7))
    end
    levels[i] = cur

    local pk = peaks[i] or 0
    if cur > pk then
      pk = cur
    else
      pk = pk - dt * 0.45
      if pk < cur then pk = cur end
    end
    peaks[i] = clamp(pk, 0, 1)

    local x = vx + (i - 0.5) * slot - barW * 0.5
    local baseY = vy + vh
    local segH = vh / SEGS
    local lit = math.floor(cur * SEGS + 0.5)

    -- 分段填色柱（面）
    for s = 0, lit - 1 do
      local t = (s + 0.5) / SEGS
      local y0 = baseY - (s + 1) * segH
      local r, g, b = bar_color(t)
      engine.fill_rect(x, y0 + 0.35, barW, math.max(0.8, segH - 0.7), r, g, b, 0.55 + t * 0.4)
    end

    -- 峰值帽（线）
    if peaks[i] > 0.04 and playing then
      local peakY = baseY - vh * peaks[i]
      local r, g, b = bar_color(clamp(peaks[i], 0.6, 1))
      engine.draw_line(x, peakY, x + barW, peakY, 2, 255, 255, 255, 0.75)
      engine.draw_line(x, peakY, x + barW, peakY, 1.2, r, g, b, 0.95)
    end
  end
end
