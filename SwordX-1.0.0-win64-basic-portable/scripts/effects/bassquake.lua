-- 低音节拍：仅 prev/play/pause/stop/next 轻微不规律抖动

local timeSec = 0
local bassSmooth = 0
local bassAvg = 0.03
local quakeEnv = 0

local TARGETS = {
  "main.prev",
  "main.play",
  "main.pause",
  "main.stop",
  "main.next",
}

local motion = {}

local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

local function lerp(a, b, t)
  return a + (b - a) * t
end

local function rebuild_motion()
  motion = {}
  for i = 1, #TARGETS do
    local id = TARGETS[i]
    motion[id] = {
      phase = math.random() * math.pi * 2,
      freq = 11 + math.random() * 14,
      ax = 0.6 + math.random() * 0.5,
      ay = 0.6 + math.random() * 0.5,
      spin = (math.random() - 0.5) * 2.5,
    }
  end
end

local function update_quake(dt)
  if not engine.is_playing() then
    bassSmooth = bassSmooth * (1 - math.min(1, dt * 3))
    quakeEnv = quakeEnv * (1 - math.min(1, dt * 5))
    return
  end

  local levels = engine.vis_levels(8)
  local bass = (levels and levels[1] or 0) * 0.75 + (levels and levels[2] or 0) * 0.25
  local e = engine.vis_energy() or 0
  bass = math.max(bass, e * 0.55)

  local atk = math.min(1, dt * 18)
  local rel = math.min(1, dt * 6)
  if bass > bassSmooth then
    bassSmooth = lerp(bassSmooth, bass, atk)
  else
    bassSmooth = lerp(bassSmooth, bass, rel)
  end

  bassAvg = lerp(bassAvg, bassSmooth, math.min(1, dt * 1.0))
  local onset = clamp(bassSmooth - bassAvg * 1.08, 0, 1)
  local absKick = clamp((bassSmooth - 0.25) * 1.3, 0, 1)
  local kick = clamp(onset * 1.1 + absKick * 0.8, 0, 1)

  if kick > quakeEnv then
    quakeEnv = lerp(quakeEnv, kick, math.min(1, dt * 22))
  else
    quakeEnv = quakeEnv * (1 - math.min(1, dt * 4.5))
  end
end

function on_init(w, h)
  timeSec = 0
  bassSmooth, bassAvg, quakeEnv = 0, 0.03, 0
  rebuild_motion()
end

function on_resize(w, h)
  rebuild_motion()
end

function on_frame(dt, w, h)
  if w < 8 or h < 8 then
    return
  end
  if next(motion) == nil then
    rebuild_motion()
  end

  timeSec = timeSec + dt
  update_quake(dt)

  -- 约 ±2px；节拍时轻微放大（约 1.0..1.12）
  local amp = quakeEnv * 2.0 + bassSmooth * 0.6
  local beatScale = 1.0 + quakeEnv * 0.12 + bassSmooth * 0.03

  -- 只对这些 id 设 shake/scale；其它 role 保持默认（宿主每帧会清空）
  for i = 1, #TARGETS do
    local id = TARGETS[i]
    local m = motion[id]
    if m then
      m.phase = m.phase + (m.freq + quakeEnv * 8) * dt
      local dx = math.sin(m.phase) * amp * m.ax
          + math.sin(m.phase * 1.7 + m.spin) * amp * 0.25
      local dy = math.cos(m.phase * 1.25) * amp * m.ay
          + math.sin(m.phase * 2.1) * amp * 0.2
      engine.set_role_shake(id, dx, dy)
      local pulse = 1.0 + math.sin(m.phase * 0.85) * 0.02 * quakeEnv
      engine.set_role_scale(id, beatScale * pulse)
    end
  end
end
