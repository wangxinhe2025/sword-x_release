-- 雾气 / 尘埃：慢、淡、大软点（Lua UI 特效）

local COUNT = 48
local motes = {}
local timeSec = 0
local energySmooth = 0

local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

local function lerp(a, b, t)
  return a + (b - a) * t
end

local function spawn(w, h)
  return {
    x = math.random() * w,
    y = math.random() * h,
    vx = (math.random() - 0.5) * 12,
    vy = (math.random() - 0.5) * 8 - 2,
    size = 8 + math.random() * 22,
    alpha = 0.04 + math.random() * 0.08,
    phase = math.random() * math.pi * 2,
    cool = math.random() < 0.55,
  }
end

function on_init(w, h)
  motes = {}
  timeSec = 0
  energySmooth = 0
  for i = 1, COUNT do
    motes[i] = spawn(w, h)
  end
end

function on_resize(w, h)
  for i = 1, #motes do
    local m = motes[i]
    m.x = clamp(m.x, 0, w)
    m.y = clamp(m.y, 0, h)
  end
end

function on_frame(dt, w, h)
  if w < 8 or h < 8 then
    return
  end
  if #motes == 0 then
    on_init(w, h)
  end

  timeSec = timeSec + dt
  local e = engine.is_playing() and (engine.vis_energy() or 0) or 0
  energySmooth = lerp(energySmooth, e, math.min(1, dt * 4))

  local drift = 1 + energySmooth * 0.6
  local aBoost = 1 + energySmooth * 0.5

  for i = 1, #motes do
    local m = motes[i]
    m.phase = m.phase + dt * 0.35
    m.x = m.x + (m.vx + math.sin(m.phase) * 6) * dt * drift
    m.y = m.y + (m.vy + math.cos(m.phase * 0.7) * 4) * dt * drift

    -- 环绕出界
    if m.x < -m.size then m.x = w + m.size end
    if m.x > w + m.size then m.x = -m.size end
    if m.y < -m.size then m.y = h + m.size end
    if m.y > h + m.size then m.y = -m.size end

    local pulse = 0.85 + 0.15 * math.sin(m.phase * 1.3)
    local a = clamp(m.alpha * pulse * aBoost, 0.02, 0.18)
    local sz = m.size * (0.9 + energySmooth * 0.25)
    if m.cool then
      engine.draw_circle(m.x, m.y, sz, 190, 205, 220, a)
    else
      engine.draw_circle(m.x, m.y, sz, 210, 200, 185, a)
    end
  end
end
