-- 多边形频谱：仿 C++ PaintVis（LED 分段柱 + 峰值帽）
-- 使用 engine.fill_quad / fill_triangle；engine.vis_rect 接管原生频谱

local SLOT = 14
local GAP = 2
local BAR_W = SLOT - GAP
local SEG_H = 4
local SEG_GAP = 1
local SEG_STEP = SEG_H + SEG_GAP
local MAX_BANDS = 32

local levels = {}
local peaks = {}
local midDomSmooth = 0

local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

local function lerp(a, b, t)
  return a + (b - a) * t
end

local function mix(a, b, t)
  return math.floor(lerp(a, b, t) + 0.5)
end

local function rebuild(n)
  levels, peaks = {}, {}
  for i = 1, n do
    levels[i] = 0
    peaks[i] = 0
  end
  midDomSmooth = 0
end

-- 中频 / 高低频色（主题色作中频，边缘略偏冷）
local function palette()
  local r, g, b = engine.theme_color()
  r = r or 78
  g = g or 240
  b = b or 168
  local mid = { r, g, b }
  local edge = {
    clamp(mix(r, 255, 0.35), 0, 255),
    clamp(mix(g, 64, 0.45), 0, 255),
    clamp(mix(b, 96, 0.25), 0, 255),
  }
  return mid, edge
end

local function bar_color(i, bars, mid, edge, midHalf)
  if bars <= 1 then
    return mid[1], mid[2], mid[3]
  end
  local x = (i - 1) / (bars - 1)
  local dist = math.abs(2 * x - 1)
  local core = midHalf * 0.55
  local edgeAmt = 0
  if dist > core then
    local span = math.max(0.10, 1.0 - core)
    edgeAmt = clamp((dist - core) / span, 0, 1)
    edgeAmt = edgeAmt * edgeAmt * (3 - 2 * edgeAmt)
  end
  return mix(mid[1], edge[1], edgeAmt),
    mix(mid[2], edge[2], edgeAmt),
    mix(mid[3], edge[3], edgeAmt)
end

-- 轻微 3D：顶边略收窄的四边形 LED 块
local function draw_seg_quad(x0, y0, x1, y1, r, g, b, a)
  local inset = 0.6
  engine.fill_quad(
    x0 + inset, y0,
    x1 - inset, y0,
    x1, y1,
    x0, y1,
    r, g, b, a)
end

function on_init(w, h)
  rebuild(16)
  -- 拖窗时仍刷新频谱，避免视觉区空白
  engine.set_paint_while_drag(true)
end

function on_frame(dt, w, h)
  if w < 8 or h < 8 then
    return
  end

  local vx, vy, vw, vh = engine.vis_rect()
  if not vx or vw < 32 or vh < 8 then
    return
  end

  local bars = clamp(math.floor(vw / SLOT), 12, MAX_BANDS)
  if #levels ~= bars then
    rebuild(bars)
  end

  local playing = engine.is_playing()
  local raw = playing and engine.vis_levels(bars) or nil
  local mid, edge = palette()

  -- 平滑：升快降慢（接近 C++ visBars_ * 0.78）
  local midSum, edgeSum, midN, edgeN = 0, 0, 0, 0
  local midLo = math.floor(bars / 3)
  local midHi = math.floor((2 * bars) / 3)

  for i = 1, bars do
    local target = (raw and raw[i]) or 0
    local cur = levels[i] or 0
    if target > cur then
      cur = target
    else
      cur = math.max(target, cur * 0.78)
    end
    levels[i] = cur

    local pk = peaks[i] or 0
    if cur > pk then
      pk = cur
    else
      pk = pk - 0.025
      if pk < cur then pk = cur end
    end
    peaks[i] = clamp(pk, 0, 1)

    if i > midLo and i <= midHi then
      midSum = midSum + cur
      midN = midN + 1
    else
      edgeSum = edgeSum + cur
      edgeN = edgeN + 1
    end
  end

  local midAvg = midN > 0 and (midSum / midN) or 0
  local edgeAvg = edgeN > 0 and (edgeSum / edgeN) or 0
  local rel = midAvg / (midAvg + edgeAvg + 0.04)
  local gate = clamp((midAvg - 0.12) * 9.0, 0, 1)
  gate = gate * clamp((rel - 0.28) * 5.5, 0, 1)
  local midDominance = gate * gate * gate
  if midDominance > midDomSmooth then
    midDomSmooth = midDomSmooth * 0.28 + midDominance * 0.72
  else
    midDomSmooth = midDomSmooth * 0.38 + midDominance * 0.62
  end
  local midHalf = 0.02 + midDomSmooth * 0.96

  local usableH = math.max(SEG_STEP, vh - SEG_GAP)
  local maxSegs = math.max(1, math.floor((usableH + SEG_GAP) / SEG_STEP))
  local baseY = vy + vh

  for i = 1, bars do
    local x0 = vx + (i - 1) * SLOT
    if x0 + BAR_W > vx + vw then
      break
    end
    local x1 = x0 + BAR_W
    local r, g, b = bar_color(i, bars, mid, edge, midHalf)
    local lit = clamp(math.floor(levels[i] * maxSegs + 0.5), 0, maxSegs)

    for s = 0, lit - 1 do
      local y1 = baseY - s * SEG_STEP - SEG_GAP
      local y0 = y1 - SEG_H
      local t = (s + 0.5) / maxSegs
      local a = 0.72 + t * 0.22
      draw_seg_quad(x0, y0, x1, y1, r, g, b, a)
    end

    -- 峰值帽：提亮小四边形 + 顶上三角
    local peakSeg = clamp(math.floor(peaks[i] * maxSegs + 0.5), 0, maxSegs)
    if peakSeg > 0 and playing then
      local ps = peakSeg - 1
      local y1 = baseY - ps * SEG_STEP - SEG_GAP
      local y0 = y1 - SEG_H
      local pr = mix(r, 255, 0.22)
      local pg = mix(g, 255, 0.22)
      local pb = mix(b, 255, 0.22)
      draw_seg_quad(x0, y0, x1, y1, pr, pg, pb, 0.95)
      local cx = (x0 + x1) * 0.5
      local tip = y0 - 2.2
      engine.fill_triangle(
        x0 + 1.5, y0,
        x1 - 1.5, y0,
        cx, tip,
        pr, pg, pb, 0.85)
    end
  end
end
