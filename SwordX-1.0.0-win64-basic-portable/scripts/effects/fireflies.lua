-- 萤火虫：随机游走 + 亮度正弦闪（Lua UI 特效）

local COUNT = 36
local bugs = {}
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

local function spawn(w, h)
  local ang = math.random() * math.pi * 2
  local spd = 18 + math.random() * 28
  return {
    x = math.random() * w,
    y = math.random() * h,
    vx = math.cos(ang) * spd,
    vy = math.sin(ang) * spd,
    size = 1.4 + math.random() * 1.8,
    phase = math.random() * math.pi * 2,
    freq = 1.2 + math.random() * 2.4,
    turn = (math.random() - 0.5) * 2.5,
    warm = math.random() < 0.7,
  }
end

local function update_rhythm(dt)
  if not engine.is_playing() then
    energySmooth = energySmooth * (1 - math.min(1, dt * 2))
    pulseEnv = pulseEnv * (1 - math.min(1, dt * 4))
    return
  end
  local e = engine.vis_energy() or 0
  energySmooth = lerp(energySmooth, e, math.min(1, dt * 8))
  energyAvg = lerp(energyAvg, energySmooth, math.min(1, dt * 1.1))
  local onset = clamp(energySmooth - energyAvg * 1.1, 0, 1)
  if onset > pulseEnv then
    pulseEnv = lerp(pulseEnv, onset, math.min(1, dt * 16))
  else
    pulseEnv = pulseEnv * (1 - math.min(1, dt * 4))
  end
end

function on_init(w, h)
  bugs = {}
  timeSec = 0
  energySmooth, energyAvg, pulseEnv = 0, 0.02, 0
  for i = 1, COUNT do
    bugs[i] = spawn(w, h)
  end
end

function on_resize(w, h)
  for i = 1, #bugs do
    local b = bugs[i]
    b.x = clamp(b.x, 0, w)
    b.y = clamp(b.y, 0, h)
  end
end

function on_frame(dt, w, h)
  if w < 8 or h < 8 then
    return
  end
  if #bugs == 0 then
    on_init(w, h)
  end

  timeSec = timeSec + dt
  update_rhythm(dt)

  local speedMul = 0.75 + energySmooth * 0.9 + pulseEnv * 0.6

  for i = 1, #bugs do
    local b = bugs[i]
    -- 缓慢转向（随机游走）
    b.turn = b.turn + (math.random() - 0.5) * dt * 4
    b.turn = clamp(b.turn, -3.2, 3.2)
    local ang = math.atan(b.vy, b.vx) + b.turn * dt
    local spd = math.sqrt(b.vx * b.vx + b.vy * b.vy)
    if spd < 8 then
      spd = 12 + math.random() * 10
    end
    spd = clamp(spd + (math.random() - 0.5) * 20 * dt, 10, 55)
    b.vx = math.cos(ang) * spd
    b.vy = math.sin(ang) * spd

    b.x = b.x + b.vx * dt * speedMul
    b.y = b.y + b.vy * dt * speedMul

    -- 软边界反弹
    if b.x < 4 then b.x, b.vx = 4, math.abs(b.vx) end
    if b.x > w - 4 then b.x, b.vx = w - 4, -math.abs(b.vx) end
    if b.y < 4 then b.y, b.vy = 4, math.abs(b.vy) end
    if b.y > h - 4 then b.y, b.vy = h - 4, -math.abs(b.vy) end

    b.phase = b.phase + b.freq * dt * (1 + pulseEnv * 0.8)
    -- 亮度正弦 + 偶发更亮
    local tw = 0.15 + 0.85 * (0.5 + 0.5 * math.sin(b.phase))
    tw = tw ^ 1.6
    if math.sin(b.phase * 0.31 + i) > 0.96 then
      tw = clamp(tw + 0.45, 0, 1)
    end
    local a = clamp(tw * (0.35 + energySmooth * 0.35 + pulseEnv * 0.25), 0.02, 0.95)
    local sz = b.size * (0.7 + tw * 0.8 + pulseEnv * 0.3)

    if b.warm then
      engine.draw_circle(b.x, b.y, sz * 2.2, 255, 220, 80, a * 0.18) -- 光晕
      engine.draw_circle(b.x, b.y, sz, 255, 240, 120, a)
    else
      engine.draw_circle(b.x, b.y, sz * 2.0, 180, 255, 160, a * 0.15)
      engine.draw_circle(b.x, b.y, sz, 200, 255, 170, a)
    end
  end
end
