-- 樱花 / 落叶：慢飘 + 左右摆（Lua UI 特效）

local COUNT = 56
local petals = {}
local timeSec = 0
local energySmooth = 0
local pulseEnv = 0
local energyAvg = 0.02

local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

local function lerp(a, b, t)
  return a + (b - a) * t
end

local function spawn(w, h, fromTop)
  local leaf = math.random() < 0.28 -- 少量偏秋叶色
  return {
    x = math.random() * w,
    y = fromTop and (-10 - math.random() * 40) or (math.random() * h),
    vy = 14 + math.random() * 28,
    vx = (math.random() - 0.5) * 16,
    size = 2.2 + math.random() * 3.5,
    phase = math.random() * math.pi * 2,
    spin = 0.8 + math.random() * 2.0,
    sway = 22 + math.random() * 30,
    alpha = 0.35 + math.random() * 0.45,
    leaf = leaf,
    -- 樱粉 / 秋叶
    r = leaf and (200 + math.random(40)) or (240 + math.random(15)),
    g = leaf and (90 + math.random(60)) or (140 + math.random(50)),
    b = leaf and (40 + math.random(40)) or (170 + math.random(40)),
  }
end

local function update_rhythm(dt)
  if not engine.is_playing() then
    energySmooth = energySmooth * (1 - math.min(1, dt * 2.5))
    pulseEnv = pulseEnv * (1 - math.min(1, dt * 4))
    return 0.7, 0
  end
  local e = engine.vis_energy() or 0
  local levels = engine.vis_levels(8)
  local mid = (levels and levels[3] or 0) * 0.5 + (levels and levels[4] or 0) * 0.5
  energySmooth = lerp(energySmooth, e, math.min(1, dt * 8))
  energyAvg = lerp(energyAvg, energySmooth, math.min(1, dt * 1.15))
  local onset = clamp(energySmooth - energyAvg * 1.12, 0, 1) + mid * 0.2
  if onset > pulseEnv then
    pulseEnv = lerp(pulseEnv, clamp(onset, 0, 1), math.min(1, dt * 16))
  else
    pulseEnv = pulseEnv * (1 - math.min(1, dt * 4.5))
  end
  local fallMul = 0.65 + energySmooth * 0.9 + pulseEnv * 0.8
  local wind = math.sin(timeSec * 0.45) * (10 + energySmooth * 18) + pulseEnv * 12
  return fallMul, wind
end

function on_init(w, h)
  petals = {}
  timeSec = 0
  energySmooth, energyAvg, pulseEnv = 0, 0.02, 0
  for i = 1, COUNT do
    petals[i] = spawn(w, h, false)
  end
end

function on_resize(w, h)
  for i = 1, #petals do
    local p = petals[i]
    if p.x > w then p.x = math.random() * w end
    if p.y > h then p.y = math.random() * h end
  end
end

function on_frame(dt, w, h)
  if w < 8 or h < 8 then
    return
  end
  if #petals == 0 then
    on_init(w, h)
  end

  timeSec = timeSec + dt
  local fallMul, wind = update_rhythm(dt)

  for i = 1, #petals do
    local p = petals[i]
    p.phase = p.phase + p.spin * dt
    local swayX = math.sin(p.phase) * p.sway
    p.x = p.x + (p.vx + swayX * 0.15 + wind) * dt
    p.y = p.y + p.vy * fallMul * dt

    if p.y > h + 12 or p.x < -30 or p.x > w + 30 then
      petals[i] = spawn(w, h, true)
      p = petals[i]
      if pulseEnv > 0.3 then
        p.size = p.size * (1 + pulseEnv * 0.25)
        p.vy = p.vy * (1 + pulseEnv * 0.2)
      end
    end

    local a = clamp(p.alpha * (0.85 + energySmooth * 0.25), 0.12, 0.9)
    local sz = p.size * (0.9 + 0.15 * math.sin(p.phase * 2))
    -- 花瓣：主点 + 略偏一点的副点，近似花瓣形
    engine.draw_circle(p.x, p.y, sz, p.r, p.g, p.b, a)
    engine.draw_circle(
      p.x + math.cos(p.phase) * sz * 0.45,
      p.y + math.sin(p.phase) * sz * 0.25,
      sz * 0.65, p.r, p.g, p.b, a * 0.7)
  end
end
