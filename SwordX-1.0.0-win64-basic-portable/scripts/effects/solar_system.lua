-- 太阳系：中央太阳，行星沿轨道公转（Lua UI 特效）
-- 比例为示意，非真实天文尺度。

local timeSec = 0
local energySmooth = 0
local stars = {}

-- 轨道半径为相对单位；speed 为角速度（rad/s）；倾角略作椭圆感
local PLANETS = {
  { name = "mercury", orbit = 0.14, size = 1.4, speed = 1.60, r = 180, g = 170, b = 150, phase = 0.2 },
  { name = "venus",   orbit = 0.22, size = 2.2, speed = 1.18, r = 230, g = 190, b = 110, phase = 1.1 },
  { name = "earth",   orbit = 0.30, size = 2.4, speed = 1.00, r = 90,  g = 150, b = 230, phase = 2.4 },
  { name = "mars",    orbit = 0.38, size = 1.8, speed = 0.80, r = 220, g = 110, b = 70,  phase = 3.6 },
  { name = "jupiter", orbit = 0.52, size = 4.6, speed = 0.42, r = 220, g = 180, b = 130, phase = 0.8 },
  { name = "saturn",  orbit = 0.66, size = 3.8, speed = 0.30, r = 230, g = 205, b = 140, phase = 4.2, ring = true },
  { name = "uranus",  orbit = 0.78, size = 2.8, speed = 0.22, r = 140, g = 210, b = 220, phase = 5.1 },
  { name = "neptune", orbit = 0.90, size = 2.7, speed = 0.16, r = 80,  g = 120, b = 230, phase = 1.7 },
}

local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

local function lerp(a, b, t)
  return a + (b - a) * t
end

local function rebuild_stars(w, h)
  stars = {}
  local n = 55
  for i = 1, n do
    stars[i] = {
      x = math.random() * w,
      y = math.random() * h,
      size = 0.5 + math.random() * 1.1,
      a = 0.08 + math.random() * 0.22,
      phase = math.random() * math.pi * 2,
      freq = 0.3 + math.random() * 1.5,
    }
  end
end

local function draw_orbit(cx, cy, rx, ry, a)
  local steps = clamp(math.floor((rx + ry) * 0.22), 20, 40)
  local prevX, prevY
  for i = 0, steps do
    local t = (i / steps) * math.pi * 2
    local x = cx + math.cos(t) * rx
    local y = cy + math.sin(t) * ry
    if prevX then
      engine.draw_line(prevX, prevY, x, y, 1.0, 140, 160, 200, a)
    end
    prevX, prevY = x, y
  end
end

function on_init(w, h)
  timeSec = 0
  energySmooth = 0
  -- 打散初始相位，避免全挤在一起
  for i = 1, #PLANETS do
    PLANETS[i].phase = math.random() * math.pi * 2
  end
  rebuild_stars(w, h)
end

function on_resize(w, h)
  rebuild_stars(w, h)
end

function on_frame(dt, w, h)
  if w < 16 or h < 16 then
    return
  end
  if #stars == 0 then
    on_init(w, h)
  end

  timeSec = timeSec + dt
  local playing = engine.is_playing()
  local e = playing and (engine.vis_energy() or 0) or 0
  energySmooth = lerp(energySmooth, e, math.min(1, dt * 8))

  local cx = w * 0.5
  local cy = h * 0.48
  local scale = math.min(w, h) * 0.46
  local beat = 1.0 + energySmooth * 0.12
  local orbitSpeed = 1.0 + energySmooth * 0.55

  -- 背景星点
  for i = 1, #stars do
    local s = stars[i]
    local tw = 0.65 + 0.35 * math.sin(timeSec * s.freq + s.phase)
    engine.draw_dot(s.x, s.y, s.size, s.a * tw)
  end

  -- 轨道
  for i = 1, #PLANETS do
    local p = PLANETS[i]
    local rx = scale * p.orbit
    local ry = scale * p.orbit * 0.72 -- 略扁，更有透视感
    draw_orbit(cx, cy, rx, ry, 0.07 + (i % 2) * 0.015)
  end

  -- 太阳（多层光晕）
  local sunR = scale * 0.075 * beat
  engine.draw_circle(cx, cy, sunR * 2.8, 255, 160, 40, 0.08 + energySmooth * 0.06)
  engine.draw_circle(cx, cy, sunR * 1.9, 255, 180, 60, 0.16 + energySmooth * 0.08)
  engine.draw_circle(cx, cy, sunR * 1.25, 255, 210, 80, 0.45)
  engine.draw_circle(cx, cy, sunR, 255, 240, 160, 0.9)
  engine.draw_circle(cx, cy, sunR * 0.45, 255, 255, 230, 0.95)

  -- 行星
  for i = 1, #PLANETS do
    local p = PLANETS[i]
    p.phase = p.phase + p.speed * orbitSpeed * dt
    local rx = scale * p.orbit
    local ry = scale * p.orbit * 0.72
    local x = cx + math.cos(p.phase) * rx
    local y = cy + math.sin(p.phase) * ry
    -- 远侧略暗（椭圆下半偏远）
    local depth = 0.55 + 0.45 * (0.5 + 0.5 * math.sin(p.phase))
    local a = 0.55 + 0.4 * depth
    local sz = p.size * (0.85 + 0.2 * depth) * (0.95 + energySmooth * 0.08)

    if p.ring then
      engine.draw_circle(x - sz * 1.1, y, sz * 0.45, p.r, p.g, p.b, a * 0.45)
      engine.draw_circle(x + sz * 1.1, y, sz * 0.45, p.r, p.g, p.b, a * 0.45)
      engine.draw_circle(x, y, sz * 0.35, 240, 220, 180, a * 0.35)
    end

    engine.draw_circle(x, y, sz * 1.35, p.r, p.g, p.b, a * 0.25) -- 微光晕
    engine.draw_circle(x, y, sz, p.r, p.g, p.b, a)

    -- 地球小月亮
    if p.name == "earth" then
      local mx = x + math.cos(p.phase * 3.2) * (sz * 2.2)
      local my = y + math.sin(p.phase * 3.2) * (sz * 1.6)
      engine.draw_circle(mx, my, 0.9, 210, 210, 220, a * 0.85)
    end
  end
end
