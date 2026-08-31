-- Winter 飘雪：下落偏慢；无风；轻微随机横飘。数量仍随音乐响度变化。
-- 绑定：main.window { --lua-ui-script: lua/snow.lua; }

local MIN_COUNT = 36
local MAX_COUNT = 160
local IDLE_COUNT = 52

local flakes = {}
local timeSec = 0
local spawnAcc = 0

local energySmooth = 0
local energyAvg = 0.02
local bassSmooth = 0
local pulseEnv = 0

-- 整体落速（略慢于最初版，快于上一版）
local FALL_MUL = 0.72

local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

local function lerp(a, b, t)
  return a + (b - a) * t
end

local function spawn(w, h, fromTop)
  local near = math.random()
  return {
    x = math.random() * w,
    y = fromTop and (-10 - math.random() * 50) or (math.random() * h),
    vy = 16 + near * 28,                 -- 基础下落
    vx = (math.random() - 0.5) * 6,      -- 每片固有微偏
    size = 1.0 + near * 2.6,
    phase = math.random() * math.pi * 2,
    spin = 0.45 + math.random() * 1.1,
    sway = 4 + math.random() * 7,        -- 左右飘幅（像素/秒量级）
    alpha = 0.28 + near * 0.50,
    ice = math.random() < 0.35,
  }
end

local function update_rhythm(dt)
  if not engine.is_playing() then
    energySmooth = energySmooth * (1 - math.min(1, dt * 2.4))
    bassSmooth = bassSmooth * (1 - math.min(1, dt * 2.4))
    pulseEnv = pulseEnv * (1 - math.min(1, dt * 5))
    return
  end

  local e = engine.vis_energy() or 0
  local levels = engine.vis_levels(8)
  local bass = (levels and levels[1] or 0) * 0.65 + (levels and levels[2] or 0) * 0.35

  local atk = math.min(1, dt * 12)
  local rel = math.min(1, dt * 3.2)
  if e > energySmooth then
    energySmooth = lerp(energySmooth, e, atk)
  else
    energySmooth = lerp(energySmooth, e, rel)
  end
  bassSmooth = lerp(bassSmooth, bass, math.min(1, dt * 8))

  energyAvg = lerp(energyAvg, energySmooth, math.min(1, dt * 1.0))
  local onset = clamp(energySmooth - energyAvg * 1.12, 0, 1)
  onset = onset + clamp(bassSmooth - energyAvg * 0.9, 0, 1) * 0.4
  if onset > pulseEnv then
    pulseEnv = lerp(pulseEnv, onset, math.min(1, dt * 16))
  else
    pulseEnv = pulseEnv * (1 - math.min(1, dt * 4.5))
  end
end

local function target_count()
  if not engine.is_playing() then
    return IDLE_COUNT
  end
  local t = clamp(energySmooth * 0.75 + pulseEnv * 0.55 + bassSmooth * 0.2, 0, 1)
  return math.floor(lerp(MIN_COUNT, MAX_COUNT, t) + 0.5)
end

local function sync_count(w, h, dt, target)
  local n = #flakes
  if n < target then
    local rate = 18 + (target - n) * 2.5 + pulseEnv * 40
    spawnAcc = spawnAcc + rate * dt
    while spawnAcc >= 1 and #flakes < target do
      spawnAcc = spawnAcc - 1
      flakes[#flakes + 1] = spawn(w, h, true)
    end
  else
    spawnAcc = 0
    if n > target then
      local drop = math.min(n - target, 1 + math.floor((n - target) * dt * 8))
      for _ = 1, drop do
        if #flakes > target then
          flakes[#flakes] = nil
        end
      end
    end
  end
end

function on_init(w, h)
  flakes = {}
  timeSec = 0
  spawnAcc = 0
  energySmooth, energyAvg, bassSmooth, pulseEnv = 0, 0.02, 0, 0
  for i = 1, IDLE_COUNT do
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
  update_rhythm(dt)

  local target = target_count()
  sync_count(w, h, dt, target)

  local wantRespawn = #flakes <= target
  local alive = {}
  for i = 1, #flakes do
    local f = flakes[i]
    f.phase = f.phase + f.spin * dt
    -- 无风：固有微偏 + 正弦摆动，形成自然乱飘
    local drift = f.vx + math.sin(f.phase) * f.sway
    f.x = f.x + drift * dt
    f.y = f.y + f.vy * FALL_MUL * dt

    local out = f.y > h + 12 or f.x < -24 or f.x > w + 24
    if out then
      if wantRespawn then
        alive[#alive + 1] = spawn(w, h, true)
      end
    else
      alive[#alive + 1] = f
    end
  end
  flakes = alive

  for i = 1, #flakes do
    local f = flakes[i]
    local a = clamp(f.alpha, 0.12, 1)
    local sz = f.size
    if f.ice then
      engine.draw_circle(f.x, f.y, sz * 1.15, 210, 226, 242, a * 0.55)
      engine.draw_circle(f.x, f.y, sz * 0.55, 245, 250, 255, a)
    else
      engine.draw_dot(f.x, f.y, sz, a)
    end
  end
end
