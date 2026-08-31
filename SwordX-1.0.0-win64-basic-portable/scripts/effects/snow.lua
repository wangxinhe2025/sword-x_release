-- 主窗口飘雪（Lua UI 特效）
-- 节奏：用 engine.vis_energy / engine.vis_levels 跟随当前播放，逻辑全在本脚本。

local COUNT = 96
local flakes = {}
local timeSec = 0

-- 包络 / 节拍状态（仅 Lua）
local energySmooth = 0
local energyAvg = 0.02
local bassSmooth = 0
local pulseEnv = 0

local function spawn(w, h, fromTop)
  return {
    x = math.random() * w,
    y = fromTop and (-8 - math.random() * 40) or (math.random() * h),
    vy = 28 + math.random() * 55,
    vx = (math.random() - 0.5) * 24,
    size = 1.2 + math.random() * 2.8,
    phase = math.random() * math.pi * 2,
    spin = 1.2 + math.random() * 2.5,
    alpha = 0.35 + math.random() * 0.55,
  }
end

local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

local function lerp(a, b, t)
  return a + (b - a) * t
end

-- 从可视化更新节奏量：落速倍率、风力、脉冲
local function update_rhythm(dt)
  if not engine.is_playing() then
    energySmooth = energySmooth * (1 - math.min(1, dt * 3))
    bassSmooth = bassSmooth * (1 - math.min(1, dt * 3))
    pulseEnv = pulseEnv * (1 - math.min(1, dt * 6))
    return 0.55, 0, 0
  end

  local e = engine.vis_energy() or 0
  local levels = engine.vis_levels(8)
  local bass = (levels and levels[1] or 0) * 0.65 + (levels and levels[2] or 0) * 0.35

  local atk = math.min(1, dt * 14)
  local rel = math.min(1, dt * 4)
  if e > energySmooth then
    energySmooth = lerp(energySmooth, e, atk)
  else
    energySmooth = lerp(energySmooth, e, rel)
  end
  bassSmooth = lerp(bassSmooth, bass, math.min(1, dt * 10))

  -- 相对均值的抬升 ≈ 节拍 onset
  energyAvg = lerp(energyAvg, energySmooth, math.min(1, dt * 1.2))
  local onset = clamp(energySmooth - energyAvg * 1.12, 0, 1)
  onset = onset + clamp(bassSmooth - energyAvg * 0.9, 0, 1) * 0.55
  if onset > pulseEnv then
    pulseEnv = lerp(pulseEnv, onset, math.min(1, dt * 20))
  else
    pulseEnv = pulseEnv * (1 - math.min(1, dt * 5))
  end

  -- 安静≈0.5x，响亮≈2.2x，节拍瞬间再冲一下
  local fallMul = 0.5 + energySmooth * 1.5 + pulseEnv * 2.2
  local wind = (bassSmooth - 0.2) * 36 + math.sin(timeSec * 0.7) * (8 + energySmooth * 10)
  return fallMul, wind, pulseEnv
end

function on_init(w, h)
  flakes = {}
  timeSec = 0
  energySmooth, energyAvg, bassSmooth, pulseEnv = 0, 0.02, 0, 0
  for i = 1, COUNT do
    flakes[i] = spawn(w, h, false)
  end
end

function on_resize(w, h)
  for i = 1, #flakes do
    local f = flakes[i]
    if f.x > w then
      f.x = math.random() * w
    end
    if f.y > h then
      f.y = math.random() * h
    end
  end
end

function on_frame(dt, w, h)
  if w < 8 or h < 8 then
    return
  end
  if #flakes == 0 then
    on_init(w, h)
  end

  timeSec = timeSec + dt
  local fallMul, wind, pulse = update_rhythm(dt)

  for i = 1, #flakes do
    local f = flakes[i]
    f.phase = f.phase + f.spin * dt * (1 + pulse * 0.8)
    f.x = f.x + (f.vx + math.sin(f.phase) * 18 + wind) * dt
    f.y = f.y + f.vy * fallMul * dt

    if f.y > h + 10 or f.x < -20 or f.x > w + 20 then
      flakes[i] = spawn(w, h, true)
      f = flakes[i]
      -- 强拍时新生雪花略大、略亮
      if pulse > 0.25 then
        f.size = f.size * (1 + pulse * 0.45)
        f.alpha = clamp(f.alpha + pulse * 0.25, 0.2, 0.95)
        f.vy = f.vy * (1 + pulse * 0.35)
      end
    end

    local a = clamp(f.alpha * (0.85 + energySmooth * 0.35 + pulse * 0.25), 0.1, 1)
    engine.draw_dot(f.x, f.y, f.size * (1 + pulse * 0.15), a)
  end
end
