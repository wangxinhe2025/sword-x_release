-- 樱花飘落：粉白花瓣慢飘摆动（纯樱花，不含秋叶）
-- 轻量：批量软点；拖窗/缩放时跳过绘制

local COUNT = 42
local petals = {}
local timeSec = 0
local energySmooth = 0
local energyAvg = 0.02
local pulseEnv = 0
local gust = 0
local themeR, themeG, themeB = 255, 170, 200
local hasTheme = false
local themeTick = -1

-- 樱花粉色板（未设主题色时）
local PALETTE = {
  { 255, 182, 210 },
  { 255, 160, 198 },
  { 248, 200, 220 },
  { 255, 210, 228 },
  { 240, 150, 190 },
  { 255, 230, 240 },
  { 235, 140, 180 },
  { 250, 175, 205 },
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
    -- 主题色向樱花粉靠拢，避免偏绿/偏蓝时不像樱花
    local pr, pg, pb = 255, 175, 205
    local mix = 0.55
    local j = 18
    return clamp(lerp(themeR, pr, mix) + math.random(-j, j), 160, 255),
      clamp(lerp(themeG, pg, mix) + math.random(-j, j), 100, 240),
      clamp(lerp(themeB, pb, mix) + math.random(-j, j), 140, 255)
  end
  local c = PALETTE[1 + math.floor(math.random() * #PALETTE)]
  local j = 10
  return clamp(c[1] + math.random(-j, j), 180, 255),
    clamp(c[2] + math.random(-j, j), 110, 240),
    clamp(c[3] + math.random(-j, j), 150, 255)
end

local function spawn(w, h, fromTop)
  local r, g, b = pick_color()
  return {
    x = math.random() * w,
    y = fromTop and (-14 - math.random() * 48) or (math.random() * h),
    vx = (math.random() - 0.5) * 14,
    vy = 12 + math.random() * 26,
    size = 2.4 + math.random() * 3.6,
    phase = math.random() * math.pi * 2,
    spin = 0.7 + math.random() * 1.8,
    sway = 20 + math.random() * 34,
    alpha = 0.4 + math.random() * 0.42,
    tip = 0.35 + math.random() * 0.25, -- 花瓣细长比
    r = r,
    g = g,
    b = b,
  }
end

local function update_wind(dt)
  if not engine.is_playing() then
    energySmooth = energySmooth * (1 - math.min(1, dt * 2.2))
    pulseEnv = pulseEnv * (1 - math.min(1, dt * 3.5))
    gust = lerp(gust, math.sin(timeSec * 0.32) * 7, math.min(1, dt * 2))
    return 0.5, gust
  end

  local e = engine.vis_energy() or 0
  local levels = engine.vis_levels(6) or {}
  local mid = (levels[3] or 0) * 0.55 + (levels[4] or 0) * 0.45

  energySmooth = lerp(energySmooth, math.max(e, mid * 0.8), math.min(1, dt * 8))
  energyAvg = lerp(energyAvg, energySmooth, math.min(1, dt * 1.1))
  local onset = clamp(energySmooth - energyAvg * 1.14, 0, 1) + mid * 0.18
  if onset > pulseEnv then
    pulseEnv = lerp(pulseEnv, clamp(onset, 0, 1), math.min(1, dt * 14))
  else
    pulseEnv = pulseEnv * (1 - math.min(1, dt * 4))
  end

  local base = math.sin(timeSec * 0.38) * (10 + energySmooth * 16)
  local want = base + pulseEnv * 18 * (math.sin(timeSec * 2.8) > 0 and 1 or -0.4)
  gust = lerp(gust, want, math.min(1, dt * 3.2))
  return 0.55 + energySmooth * 0.85 + pulseEnv * 0.7, gust
end

function on_init(w, h)
  petals = {}
  timeSec = 0
  energySmooth, energyAvg, pulseEnv, gust = 0, 0.02, 0, 0
  themeTick = -1
  engine.set_paint_while_drag(false)
  refresh_theme()
  for i = 1, COUNT do
    petals[i] = spawn(w, h, false)
  end
end

function on_resize(w, h)
  for i = 1, #petals do
    local p = petals[i]
    if p.x > w + 40 then p.x = math.random() * w end
    if p.y > h + 40 then p.y = math.random() * h end
  end
end

function on_frame(dt, w, h)
  if w < 8 or h < 8 then
    return
  end
  if engine.is_dragging() or engine.is_resizing() then
    return
  end
  if #petals == 0 then
    on_init(w, h)
  end

  timeSec = timeSec + dt
  local tick = math.floor(timeSec)
  if tick ~= themeTick then
    themeTick = tick
    refresh_theme()
  end

  local fallMul, wind = update_wind(dt)

  -- 每瓣 3 点：瓣心 + 两侧弧，近似樱花花瓣
  local pts = {}
  local n = 0
  for i = 1, #petals do
    local p = petals[i]
    p.phase = p.phase + p.spin * dt * (1 + pulseEnv * 0.55)
    local swayX = math.sin(p.phase * 0.95) * p.sway
    local lift = math.sin(p.phase * 1.55) * (4 + pulseEnv * 7)

    p.x = p.x + (p.vx + swayX * 0.16 + wind) * dt
    p.y = p.y + (p.vy * fallMul + lift * 0.1) * dt

    if p.y > h + 18 or p.x < -40 or p.x > w + 40 then
      petals[i] = spawn(w, h, true)
      p = petals[i]
      if pulseEnv > 0.28 then
        p.size = p.size * (1 + pulseEnv * 0.2)
        p.vy = p.vy * (1 + pulseEnv * 0.18)
      end
    end

    local a = clamp(p.alpha * (0.84 + energySmooth * 0.22), 0.22, 0.94)
    local ang = p.phase
    local sx = p.size * (0.92 + 0.1 * math.sin(p.phase * 1.4))
    local cosA, sinA = math.cos(ang), math.sin(ang)
    -- 花瓣长轴与两侧
    local tipX = p.x + cosA * sx * p.tip * 1.15
    local tipY = p.y + sinA * sx * p.tip * 1.15
    local side = sx * 0.42
    local ox, oy = -sinA * side, cosA * side

    n = n + 1
    pts[n] = { x = p.x, y = p.y, size = sx * 0.72, alpha = a, r = p.r, g = p.g, b = p.b }
    n = n + 1
    pts[n] = {
      x = tipX, y = tipY, size = sx * 0.48, alpha = a * 0.78,
      r = p.r, g = p.g, b = p.b,
    }
    n = n + 1
    pts[n] = {
      x = p.x + ox * 0.55, y = p.y + oy * 0.55, size = sx * 0.4, alpha = a * 0.65,
      r = clamp(p.r + 8, 0, 255), g = clamp(p.g + 10, 0, 255), b = clamp(p.b + 8, 0, 255),
    }
  end
  engine.draw_points(pts)
end
