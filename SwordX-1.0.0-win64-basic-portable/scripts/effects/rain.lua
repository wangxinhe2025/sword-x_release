-- 主窗口下雨（Lua UI 特效）
-- 节奏：用 engine.vis_energy / engine.vis_levels 跟随当前播放。

local COUNT = 120
local drops = {}
local timeSec = 0

local energySmooth = 0
local energyAvg = 0.02
local midSmooth = 0
local pulseEnv = 0

local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

local function lerp(a, b, t)
  return a + (b - a) * t
end

local function spawn(w, h, fromTop)
  local len = 6 + math.random() * 12
  local speed = 220 + math.random() * 280
  return {
    x = math.random() * (w + 40) - 20,
    y = fromTop and (-len - math.random() * 60) or (math.random() * h),
    vy = speed,
    vx = -40 - math.random() * 50, -- 斜雨
    len = len,
    thick = 0.7 + math.random() * 0.9,
    alpha = 0.25 + math.random() * 0.45,
  }
end

local function update_rhythm(dt)
  if not engine.is_playing() then
    energySmooth = energySmooth * (1 - math.min(1, dt * 3))
    midSmooth = midSmooth * (1 - math.min(1, dt * 3))
    pulseEnv = pulseEnv * (1 - math.min(1, dt * 6))
    return 0.65, -35, 0
  end

  local e = engine.vis_energy() or 0
  local levels = engine.vis_levels(8)
  -- 雨更跟中高频（镲/人声）一点，低频只做偶发倾盆
  local mid = (levels and levels[3] or 0) * 0.4
      + (levels and levels[4] or 0) * 0.35
      + (levels and levels[5] or 0) * 0.25
  local bass = (levels and levels[1] or 0) * 0.6 + (levels and levels[2] or 0) * 0.4

  local atk = math.min(1, dt * 16)
  local rel = math.min(1, dt * 5)
  if e > energySmooth then
    energySmooth = lerp(energySmooth, e, atk)
  else
    energySmooth = lerp(energySmooth, e, rel)
  end
  midSmooth = lerp(midSmooth, mid, math.min(1, dt * 12))

  energyAvg = lerp(energyAvg, energySmooth, math.min(1, dt * 1.4))
  local onset = clamp(energySmooth - energyAvg * 1.1, 0, 1)
  onset = onset + clamp(midSmooth - energyAvg * 0.85, 0, 1) * 0.7
  onset = onset + clamp(bass - energyAvg, 0, 1) * 0.35
  if onset > pulseEnv then
    pulseEnv = lerp(pulseEnv, onset, math.min(1, dt * 22))
  else
    pulseEnv = pulseEnv * (1 - math.min(1, dt * 6))
  end

  -- 安静细雨，响时倾盆；节拍瞬间加速
  local fallMul = 0.7 + energySmooth * 1.4 + pulseEnv * 1.8
  local wind = -45 - midSmooth * 55 - pulseEnv * 40
      + math.sin(timeSec * 0.55) * (6 + energySmooth * 8)
  return fallMul, wind, pulseEnv
end

-- 用短链圆点画雨丝（宿主暂无线段 API）
local function draw_streak(x, y, vx, vy, len, thick, alpha)
  local speed = math.sqrt(vx * vx + vy * vy)
  if speed < 1 then
    speed = 1
  end
  local dx = vx / speed
  local dy = vy / speed
  local steps = clamp(math.floor(len / 2.2), 2, 8)
  for s = 0, steps do
    local t = s / steps
    local px = x - dx * len * t
    local py = y - dy * len * t
    local a = alpha * (1 - t * 0.75)
    -- 偏冷蓝灰
    engine.draw_circle(px, py, thick * (1 - t * 0.35), 170, 195, 230, a)
  end
end

function on_init(w, h)
  drops = {}
  timeSec = 0
  energySmooth, energyAvg, midSmooth, pulseEnv = 0, 0.02, 0, 0
  for i = 1, COUNT do
    drops[i] = spawn(w, h, false)
  end
end

function on_resize(w, h)
  for i = 1, #drops do
    local d = drops[i]
    if d.x > w + 30 then
      d.x = math.random() * w
    end
    if d.y > h + 20 then
      d.y = math.random() * h
    end
  end
end

function on_frame(dt, w, h)
  if w < 8 or h < 8 then
    return
  end
  if #drops == 0 then
    on_init(w, h)
  end

  timeSec = timeSec + dt
  local fallMul, wind, pulse = update_rhythm(dt)

  for i = 1, #drops do
    local d = drops[i]
    local vx = d.vx + wind * 0.35
    local vy = d.vy * fallMul
    d.x = d.x + vx * dt
    d.y = d.y + vy * dt

    if d.y > h + 16 or d.x < -40 or d.x > w + 40 then
      drops[i] = spawn(w, h, true)
      d = drops[i]
      if pulse > 0.28 then
        d.len = d.len * (1 + pulse * 0.5)
        d.vy = d.vy * (1 + pulse * 0.4)
        d.alpha = clamp(d.alpha + pulse * 0.2, 0.2, 0.85)
      end
    end

    local a = clamp(d.alpha * (0.8 + energySmooth * 0.4 + pulse * 0.3), 0.12, 0.9)
    local len = d.len * (1 + pulse * 0.35)
    draw_streak(d.x, d.y, vx, vy, len, d.thick, a)
  end
end
