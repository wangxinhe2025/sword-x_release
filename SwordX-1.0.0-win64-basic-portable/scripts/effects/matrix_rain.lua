-- 矩阵雨：竖列下落的短点串（赛博感）
-- 列数/长度控制较紧，避免 UI 脚本超时被自动关闭。

local COLS = 16
local MAX_LEN = 8
local columns = {}
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

local function spawn_col(w, h, fromTop)
  local len = 4 + math.floor(math.random() * (MAX_LEN - 3))
  return {
    x = math.random() * w,
    y = fromTop and (-len * 8 - math.random() * h * 0.25) or (math.random() * h),
    vy = 80 + math.random() * 130,
    len = len,
    step = 6 + math.random() * 4,
    phase = math.random() * math.pi * 2,
    bright = 0.55 + math.random() * 0.4,
  }
end

local function rebuild(w, h)
  columns = {}
  for i = 1, COLS do
    local c = spawn_col(w, h, false)
    c.x = (i - 0.5) / COLS * w + (math.random() - 0.5) * (w / COLS) * 0.3
    columns[i] = c
  end
end

local function update_rhythm(dt)
  if not engine.is_playing() then
    energySmooth = energySmooth * (1 - math.min(1, dt * 2.5))
    pulseEnv = pulseEnv * (1 - math.min(1, dt * 4))
    return 0.75
  end
  local e = engine.vis_energy() or 0
  local levels = engine.vis_levels(8)
  local high = (levels and levels[7] or 0) * 0.5 + (levels and levels[8] or 0) * 0.5

  energySmooth = lerp(energySmooth, e, math.min(1, dt * 10))
  energyAvg = lerp(energyAvg, energySmooth, math.min(1, dt * 1.2))
  local onset = clamp(energySmooth - energyAvg * 1.12, 0, 1) + high * 0.3
  if onset > pulseEnv then
    pulseEnv = lerp(pulseEnv, clamp(onset, 0, 1), math.min(1, dt * 18))
  else
    pulseEnv = pulseEnv * (1 - math.min(1, dt * 5))
  end
  return 0.75 + energySmooth * 0.9 + pulseEnv * 1.1
end

function on_init(w, h)
  timeSec = 0
  energySmooth, energyAvg, pulseEnv = 0, 0.02, 0
  rebuild(w, h)
end

function on_resize(w, h)
  for i = 1, #columns do
    columns[i].x = clamp(columns[i].x, 0, w)
  end
end

function on_frame(dt, w, h)
  if w < 8 or h < 8 then
    return
  end
  if #columns == 0 then
    on_init(w, h)
  end

  timeSec = timeSec + dt
  local speedMul = update_rhythm(dt)

  for i = 1, #columns do
    local c = columns[i]
    c.phase = c.phase + dt * (2 + pulseEnv * 3)
    c.y = c.y + c.vy * speedMul * dt

    local trailH = c.len * c.step
    if c.y - trailH > h + 20 then
      columns[i] = spawn_col(w, h, true)
      c = columns[i]
      c.x = (i - 0.5) / COLS * w + (math.random() - 0.5) * (w / COLS) * 0.35
      if pulseEnv > 0.35 then
        c.vy = c.vy * (1 + pulseEnv * 0.35)
      end
    end

    for s = 0, c.len - 1 do
      local py = c.y - s * c.step
      if py >= -4 and py <= h + 4 then
        local t = s / math.max(1, c.len - 1)
        local a = c.bright * (1 - t * 0.9)
        a = clamp(a * (0.8 + energySmooth * 0.3), 0.05, 0.9)
        local size = (s == 0) and 2.0 or (1.15 + (1 - t) * 0.5)
        if s == 0 then
          engine.draw_circle(c.x, py, size, 210, 255, 230, a)
        else
          -- 青绿尾迹
          engine.draw_circle(
            c.x, py, size,
            math.floor(40 + (1 - t) * 80),
            math.floor(160 + (1 - t) * 80),
            math.floor(90 + (1 - t) * 60),
            a)
        end
      end
    end
  end
end
