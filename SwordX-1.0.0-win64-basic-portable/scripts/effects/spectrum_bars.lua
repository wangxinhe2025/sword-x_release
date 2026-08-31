-- 频谱柱：接管 main.vis（engine.vis_rect），宿主不再画原生频谱

local BANDS = 24
local PARTICLES_PER_BAND = 4
local levelsSmooth = {}
local particles = {}
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

local function band_color(i, n, pulse)
  local t = (i - 1) / math.max(1, n - 1)
  local r = math.floor(lerp(255, 80, t))
  local g = math.floor(lerp(140, 220, t))
  local b = math.floor(lerp(70, 255, t))
  if pulse > 0.3 then
    r = math.min(255, r + math.floor(pulse * 40))
    g = math.min(255, g + math.floor(pulse * 20))
  end
  return r, g, b
end

local function rebuild()
  levelsSmooth = {}
  particles = {}
  for i = 1, BANDS do
    levelsSmooth[i] = 0
    particles[i] = {}
    for p = 1, PARTICLES_PER_BAND do
      particles[i][p] = {
        jitter = (math.random() - 0.5) * 0.35,
        phase = math.random() * math.pi * 2,
        size = 1.0 + math.random() * 1.2,
      }
    end
  end
end

local function update_levels(dt)
  local levels = engine.vis_levels(BANDS)
  local playing = engine.is_playing()
  local sum = 0

  for i = 1, BANDS do
    local target = playing and (levels and levels[i] or 0) or 0
    local cur = levelsSmooth[i] or 0
    if target > cur then
      cur = lerp(cur, target, math.min(1, dt * 22))
    else
      cur = lerp(cur, target, math.min(1, dt * 7))
    end
    levelsSmooth[i] = cur
    sum = sum + cur
  end

  local e = playing and (engine.vis_energy() or 0) or 0
  energySmooth = lerp(energySmooth, e, math.min(1, dt * 12))
  energyAvg = lerp(energyAvg, energySmooth, math.min(1, dt * 1.2))
  local onset = clamp(energySmooth - energyAvg * 1.12, 0, 1)
  if onset > pulseEnv then
    pulseEnv = lerp(pulseEnv, onset, math.min(1, dt * 20))
  else
    pulseEnv = pulseEnv * (1 - math.min(1, dt * 5))
  end

  return sum / BANDS
end

function on_init(w, h)
  timeSec = 0
  energySmooth, energyAvg, pulseEnv = 0, 0.02, 0
  rebuild()
  engine.set_paint_while_drag(true)
end

function on_resize(w, h)
end

function on_frame(dt, w, h)
  if w < 8 or h < 8 then
    return
  end
  if #particles == 0 then
    on_init(w, h)
  end

  -- 访问频谱区域 = 本帧接管；无 main.vis 时退回不画
  local vx, vy, vw, vh = engine.vis_rect()
  if not vx or vw < 8 or vh < 8 then
    return
  end

  timeSec = timeSec + dt
  local avgLevel = update_levels(dt)

  local margin = math.max(2, vw * 0.04)
  local usable = vw - margin * 2
  local gap = usable / BANDS
  local baseY = vy + vh - 2
  local maxH = vh * (0.88 + pulseEnv * 0.08)

  for i = 1, BANDS do
    local lv = levelsSmooth[i] or 0
    local bounce = math.sin(timeSec * 14 + i * 0.7) * lv * pulseEnv * 0.06
    local barH = maxH * clamp(lv + bounce, 0, 1.15)
    local cx = vx + margin + (i - 0.5) * gap
    local r, g, b = band_color(i, BANDS, pulseEnv)

    local plist = particles[i]
    for p = 1, #plist do
      local part = plist[p]
      part.phase = part.phase + dt * (6 + lv * 10)

      local t = (p - 0.5) / #plist
      local y = baseY - barH * t
      local x = cx + part.jitter * gap * 0.45
          + math.sin(part.phase) * (1.0 + lv * 2.0)

      local a = clamp(0.2 + lv * 0.75 + (1 - t) * 0.1, 0.05, 0.95)
      if barH < 4 then
        a = a * (barH / 4)
      end
      local size = part.size * (0.85 + lv * 0.7 + (1 - t) * 0.25)

      engine.draw_circle(x, y, size, r, g, b, a)

      if p == #plist and lv > 0.08 then
        engine.draw_circle(x, y - 1.5, size * 1.2, 255, 255, 255, a * 0.5)
      end
    end

    local baseA = 0.12 + avgLevel * 0.15 + lv * 0.25
    engine.draw_circle(cx, baseY, 1.0, r, g, b, baseA)
  end
end
