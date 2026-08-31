-- 星空闪烁 + 偶发流星（Lua UI 特效）
-- 节奏：能量高时闪得更亮、流星更密。

local STAR_COUNT = 110
local stars = {}
local meteors = {}
local timeSec = 0
local meteorCooldown = 0.8

local energySmooth = 0
local energyAvg = 0.02
local pulseEnv = 0

local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

local function lerp(a, b, t)
  return a + (b - a) * t
end

local function spawn_star(w, h)
  return {
    x = math.random() * w,
    y = math.random() * h,
    size = 0.7 + math.random() * 1.6,
    base = 0.15 + math.random() * 0.55,
    phase = math.random() * math.pi * 2,
    freq = 0.4 + math.random() * 2.2,
    warm = math.random() < 0.18, -- 少量偏暖星
  }
end

local function spawn_meteor(w, h)
  -- 从左上/右上一带切入，斜向下快划
  local fromLeft = math.random() < 0.55
  local x = fromLeft and (-20 + math.random() * w * 0.4) or (w * 0.55 + math.random() * w * 0.5)
  local y = -12 - math.random() * 50
  local vx = (fromLeft and 1 or -1) * (300 + math.random() * 260)
  local vy = 220 + math.random() * 300
  return {
    x = x,
    y = y,
    vx = vx,
    vy = vy,
    life = 0.4 + math.random() * 0.55,
    age = 0,
    len = 20 + math.random() * 30,
    thick = 1.0 + math.random() * 0.8,
  }
end

local function update_rhythm(dt)
  if not engine.is_playing() then
    energySmooth = energySmooth * (1 - math.min(1, dt * 2.5))
    pulseEnv = pulseEnv * (1 - math.min(1, dt * 5))
    return
  end

  local e = engine.vis_energy() or 0
  local levels = engine.vis_levels(8)
  local high = (levels and levels[6] or 0) * 0.4
      + (levels and levels[7] or 0) * 0.35
      + (levels and levels[8] or 0) * 0.25

  local atk = math.min(1, dt * 12)
  local rel = math.min(1, dt * 3.5)
  if e > energySmooth then
    energySmooth = lerp(energySmooth, e, atk)
  else
    energySmooth = lerp(energySmooth, e, rel)
  end

  energyAvg = lerp(energyAvg, energySmooth, math.min(1, dt * 1.1))
  local onset = clamp(energySmooth - energyAvg * 1.15, 0, 1)
  onset = onset + clamp(high - energyAvg * 0.8, 0, 1) * 0.8
  if onset > pulseEnv then
    pulseEnv = lerp(pulseEnv, onset, math.min(1, dt * 18))
  else
    pulseEnv = pulseEnv * (1 - math.min(1, dt * 4.5))
  end
end

local function draw_meteor(m)
  local speed = math.sqrt(m.vx * m.vx + m.vy * m.vy)
  if speed < 1 then
    speed = 1
  end
  local dx = m.vx / speed
  local dy = m.vy / speed
  local fade = clamp(1 - m.age / m.life, 0, 1)
  local steps = clamp(math.floor(m.len / 2.4), 3, 12)
  for s = 0, steps do
    local t = s / steps
    local px = m.x - dx * m.len * t
    local py = m.y - dy * m.len * t
    local a = fade * (1 - t * 0.85) * (0.55 + pulseEnv * 0.35)
    local r = 220 + math.floor((1 - t) * 35)
    local g = 230 + math.floor((1 - t) * 20)
    local b = 255
    engine.draw_circle(px, py, m.thick * (1 - t * 0.5), r, g, b, a)
  end
  -- 头部稍亮
  engine.draw_circle(m.x, m.y, m.thick * 1.35, 255, 255, 255, fade * 0.9)
end

function on_init(w, h)
  stars = {}
  meteors = {}
  timeSec = 0
  meteorCooldown = 0.6 + math.random() * 0.8
  energySmooth, energyAvg, pulseEnv = 0, 0.02, 0
  for i = 1, STAR_COUNT do
    stars[i] = spawn_star(w, h)
  end
end

function on_resize(w, h)
  for i = 1, #stars do
    local s = stars[i]
    if s.x > w then
      s.x = math.random() * w
    end
    if s.y > h then
      s.y = math.random() * h
    end
  end
end

function on_frame(dt, w, h)
  if w < 8 or h < 8 then
    return
  end
  if #stars == 0 then
    on_init(w, h)
  end

  timeSec = timeSec + dt
  update_rhythm(dt)

  -- 背景星：慢闪 + 节拍提亮
  local twinkleBoost = 1 + energySmooth * 0.8 + pulseEnv * 1.2
  for i = 1, #stars do
    local s = stars[i]
    s.phase = s.phase + s.freq * dt * twinkleBoost
    local tw = 0.55 + 0.45 * math.sin(s.phase)
    -- 偶发「眨眼」尖峰
    local blink = 0
    if math.sin(s.phase * 0.37 + i) > 0.97 then
      blink = 0.35 + pulseEnv * 0.4
    end
    local a = clamp(s.base * tw * (0.75 + energySmooth * 0.5) + blink, 0.05, 1)
    local sz = s.size * (1 + blink * 0.5 + pulseEnv * 0.15)
    if s.warm then
      engine.draw_circle(s.x, s.y, sz, 255, 230, 190, a)
    else
      engine.draw_dot(s.x, s.y, sz, a)
    end
  end

  -- 生成流星
  meteorCooldown = meteorCooldown - dt
  local spawnChance = 0.12 + energySmooth * 0.35 + pulseEnv * 0.8
  if meteorCooldown <= 0 and #meteors < 4 then
    if (not engine.is_playing()) or math.random() < spawnChance then
      meteors[#meteors + 1] = spawn_meteor(w, h)
    end
    -- 安静稀、热闹密
    meteorCooldown = (0.9 + math.random() * 2.2) / (0.55 + energySmooth * 1.4 + pulseEnv * 1.6)
    if not engine.is_playing() then
      meteorCooldown = meteorCooldown * 1.6
    end
  end

  -- 更新流星
  local alive = {}
  for i = 1, #meteors do
    local m = meteors[i]
    m.age = m.age + dt
    m.x = m.x + m.vx * dt
    m.y = m.y + m.vy * dt
    if m.age < m.life and m.x > -80 and m.x < w + 80 and m.y < h + 80 then
      draw_meteor(m)
      alive[#alive + 1] = m
    end
  end
  meteors = alive
end
