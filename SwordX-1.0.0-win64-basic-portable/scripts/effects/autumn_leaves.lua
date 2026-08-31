-- 秋天落叶：轻量绘制（2 软圆/叶），优先皮肤 --theme-color
-- 注意：软圆混合较贵，数量/复杂度需压住，否则拖窗易卡

local COUNT = 28
local leaves = {}
local timeSec = 0
local energySmooth = 0
local energyAvg = 0.02
local pulseEnv = 0
local gust = 0
local themeR, themeG, themeB = 220, 140, 50
local hasTheme = false
local themeTick = -1

local PALETTE = {
  { 210, 70, 40 },
  { 230, 120, 45 },
  { 240, 170, 55 },
  { 200, 140, 40 },
  { 160, 90, 45 },
  { 180, 55, 35 },
  { 220, 100, 30 },
  { 140, 80, 40 },
}

local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

local function lerp(a, b, t)
  return a + (b - a) * t
end

local function refresh_theme()
  local r, g, b, a, from = engine.theme_color()
  if r and g and b then
    themeR, themeG, themeB = r, g, b
    hasTheme = from and true or false
  end
end

local function pick_color()
  if hasTheme then
    local j = 24
    local shade = (math.random() - 0.35) * 40
    return clamp(themeR + math.random(-j, j) + shade, 40, 255),
      clamp(themeG + math.random(-j, j) + shade * 0.7, 20, 255),
      clamp(themeB + math.random(-j, j) + shade * 0.4, 10, 220)
  end
  local c = PALETTE[1 + math.floor(math.random() * #PALETTE)]
  local j = 12
  return clamp(c[1] + math.random(-j, j), 40, 255),
    clamp(c[2] + math.random(-j, j), 20, 255),
    clamp(c[3] + math.random(-j, j), 10, 200)
end

local function spawn(w, h, fromTop)
  local r, g, b = pick_color()
  return {
    x = math.random() * w,
    y = fromTop and (-12 - math.random() * 40) or (math.random() * h),
    vx = (math.random() - 0.5) * 20,
    vy = 16 + math.random() * 32,
    size = 2.6 + math.random() * 3.2,
    phase = math.random() * math.pi * 2,
    tumble = 1.0 + math.random() * 2.2,
    sway = 16 + math.random() * 28,
    alpha = 0.42 + math.random() * 0.4,
    r = r,
    g = g,
    b = b,
  }
end

local function update_wind(dt)
  if not engine.is_playing() then
    energySmooth = energySmooth * (1 - math.min(1, dt * 2.2))
    pulseEnv = pulseEnv * (1 - math.min(1, dt * 3.5))
    gust = lerp(gust, math.sin(timeSec * 0.35) * 8, math.min(1, dt * 2))
    return 0.55, gust
  end

  local e = engine.vis_energy() or 0
  local levels = engine.vis_levels(6) or {}
  local bass = (levels[1] or 0) * 0.65 + (levels[2] or 0) * 0.35

  energySmooth = lerp(energySmooth, math.max(e, bass * 0.85), math.min(1, dt * 9))
  energyAvg = lerp(energyAvg, energySmooth, math.min(1, dt * 1.1))
  local onset = clamp(energySmooth - energyAvg * 1.15, 0, 1)
  if onset > pulseEnv then
    pulseEnv = lerp(pulseEnv, onset, math.min(1, dt * 14))
  else
    pulseEnv = pulseEnv * (1 - math.min(1, dt * 3.8))
  end

  local base = math.sin(timeSec * 0.4) * (12 + energySmooth * 20)
  local want = base + pulseEnv * 24 * (math.sin(timeSec * 3.1) > 0 and 1 or -0.35)
  gust = lerp(gust, want, math.min(1, dt * 3.5))
  return 0.55 + energySmooth * 0.9 + pulseEnv * 0.65, gust
end

function on_init(w, h)
  leaves = {}
  timeSec = 0
  energySmooth, energyAvg, pulseEnv, gust = 0, 0.02, 0, 0
  themeTick = -1
  -- 拖窗时不强制重绘（默认）；on_frame 里若遇到拖动则跳过绘制
  engine.set_paint_while_drag(false)
  refresh_theme()
  for i = 1, COUNT do
    leaves[i] = spawn(w, h, false)
  end
end

function on_resize(w, h)
  for i = 1, #leaves do
    local p = leaves[i]
    if p.x > w + 40 then p.x = math.random() * w end
    if p.y > h + 40 then p.y = math.random() * h end
  end
end

function on_frame(dt, w, h)
  if w < 8 or h < 8 then
    return
  end
  -- 拖动/缩放时跳过重绘，避免软圆批绘拖慢窗体
  if engine.is_dragging() or engine.is_resizing() then
    return
  end
  if #leaves == 0 then
    on_init(w, h)
  end

  timeSec = timeSec + dt
  local tick = math.floor(timeSec)
  if tick ~= themeTick then
    themeTick = tick
    refresh_theme()
  end

  local fallMul, wind = update_wind(dt)

  -- 批量点：叶身 + 叶尖（2 点/叶），比多次 draw_circle 调用开销更小
  local pts = {}
  local n = 0
  for i = 1, #leaves do
    local p = leaves[i]
    p.phase = p.phase + p.tumble * dt * (1 + pulseEnv * 0.7)
    local swayX = math.sin(p.phase * 0.9) * p.sway
    local lift = math.sin(p.phase * 1.6) * (5 + pulseEnv * 8)

    p.x = p.x + (p.vx + swayX * 0.18 + wind) * dt
    p.y = p.y + (p.vy * fallMul + lift * 0.12) * dt

    if p.y > h + 16 or p.x < -36 or p.x > w + 36 then
      leaves[i] = spawn(w, h, true)
      p = leaves[i]
      if pulseEnv > 0.28 then
        p.size = p.size * (1 + pulseEnv * 0.22)
        p.vy = p.vy * (1 + pulseEnv * 0.2)
      end
    end

    local a = clamp(p.alpha * (0.82 + energySmooth * 0.25), 0.2, 0.92)
    local ang = p.phase
    local sx = p.size * (0.9 + 0.12 * math.sin(p.phase * 1.3))
    local cosA, sinA = math.cos(ang), math.sin(ang)
    local tipX = p.x + cosA * sx * 0.7
    local tipY = p.y + sinA * sx * 0.7

    n = n + 1
    pts[n] = { x = p.x, y = p.y, size = sx * 0.85, alpha = a, r = p.r, g = p.g, b = p.b }
    n = n + 1
    pts[n] = {
      x = tipX, y = tipY, size = sx * 0.5, alpha = a * 0.75,
      r = p.r, g = p.g, b = p.b,
    }
  end
  engine.draw_points(pts)
end
