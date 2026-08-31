-- 示例：按节奏改组件/窗体颜色与透明度（engine.set_role_color / opacity 等）

local timeSec = 0
local energyS = 0
local bassS = 0
local hue = 0.55

local TITLE_ROLES = {
  "main.title",
  "main.time",
  "main.duration",
}

local FADE_ROLES = {
  "main.prev",
  "main.play",
  "main.pause",
  "main.stop",
  "main.next",
}

local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

local function lerp(a, b, t)
  return a + (b - a) * t
end

local function hsv_to_rgb(h, s, v)
  h = (h % 1.0 + 1.0) % 1.0
  s = clamp(s, 0, 1)
  v = clamp(v, 0, 1)
  local i = math.floor(h * 6)
  local f = h * 6 - i
  local p = v * (1 - s)
  local q = v * (1 - f * s)
  local t = v * (1 - (1 - f) * s)
  local r, g, b
  local m = i % 6
  if m == 0 then r, g, b = v, t, p
  elseif m == 1 then r, g, b = q, v, p
  elseif m == 2 then r, g, b = p, v, t
  elseif m == 3 then r, g, b = p, q, v
  elseif m == 4 then r, g, b = t, p, v
  else r, g, b = v, p, q
  end
  return math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5)
end

local function update_audio(dt)
  if not engine.is_playing() then
    energyS = lerp(energyS, 0, math.min(1, dt * 3))
    bassS = lerp(bassS, 0, math.min(1, dt * 3))
    return
  end
  local e = engine.vis_energy() or 0
  local levels = engine.vis_levels(8) or {}
  local bass = (levels[1] or 0) * 0.7 + (levels[2] or 0) * 0.3
  energyS = lerp(energyS, e, math.min(1, dt * 10))
  bassS = lerp(bassS, bass, math.min(1, dt * 12))
end

function on_frame(dt, w, h)
  timeSec = timeSec + dt
  update_audio(dt)

  -- 色相随时间与能量缓慢漂移
  hue = (hue + dt * (0.04 + energyS * 0.12)) % 1.0
  local pulse = 0.55 + 0.45 * math.sin(timeSec * (2.2 + bassS * 4.0))
  local sat = clamp(0.45 + energyS * 0.45, 0, 1)
  local val = clamp(0.55 + bassS * 0.4, 0, 1)
  local r, g, b = hsv_to_rgb(hue, sat, val)
  local r2, g2, b2 = hsv_to_rgb(hue + 0.12, sat * 0.85, val)

  -- 窗体衬底：随低音微微“呼吸”透明度（0..1）
  local winOp = clamp(0.78 + bassS * 0.18 + pulse * 0.04, 0.55, 1.0)
  engine.set_window_opacity(winOp)
  engine.set_control_opacity(clamp(0.88 + energyS * 0.12, 0.6, 1.0))

  -- 主窗背景色（main.window / 装饰会同步 listBg）
  engine.set_role_color("main.window", r, g, b, 0.55 + energyS * 0.35)

  -- 标题/时间文字跟色
  for i = 1, #TITLE_ROLES do
    engine.set_role_color(TITLE_ROLES[i], r2, g2, b2, 1.0)
  end

  -- transport 按钮随节拍闪透明度
  local btnOp = clamp(0.45 + pulse * 0.55, 0.25, 1.0)
  for i = 1, #FADE_ROLES do
    engine.set_role_opacity(FADE_ROLES[i], btnOp)
    engine.set_role_color(FADE_ROLES[i], 255, 255, 255, 0.75 + energyS * 0.25)
  end

  -- 封面区域略淡，突出氛围
  engine.set_role_opacity("main.cover", clamp(0.7 + energyS * 0.3, 0.4, 1.0))
end
