-- 全屏颜色叠加：按频谱频带推色温（低频暖 → 高频冷）

local bassS, midS, highS = 0, 0, 0
local energyS = 0
local pulseEnv = 0
local energyAvg = 0.03
local hueShift = 0 -- 缓动色相偏移，避免跳变

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

-- 色温近似：kelvin 粗映射到 RGB（暖黄→冷蓝）
local function kelvin_rgb(k)
  k = clamp(k, 1000, 12000) / 100
  local r, g, b
  if k <= 66 then
    r = 255
    g = clamp(99.4708025861 * math.log(k) - 161.1195681661, 0, 255)
  else
    r = clamp(329.698727446 * ((k - 60) ^ -0.1332047592), 0, 255)
    g = clamp(288.1221695283 * ((k - 60) ^ -0.0755148492), 0, 255)
  end
  if k >= 66 then
    b = 255
  elseif k <= 19 then
    b = 0
  else
    b = clamp(138.5177312231 * math.log(k - 10) - 305.0447927307, 0, 255)
  end
  return math.floor(r + 0.5), math.floor(g + 0.5), math.floor(b + 0.5)
end

local function update_bands(dt)
  local playing = engine.is_playing()
  if not playing then
    local rel = math.min(1, dt * 2.5)
    bassS = lerp(bassS, 0, rel)
    midS = lerp(midS, 0, rel)
    highS = lerp(highS, 0, rel)
    energyS = lerp(energyS, 0, rel)
    pulseEnv = pulseEnv * (1 - math.min(1, dt * 4))
    return
  end

  local n = 16
  local levels = engine.vis_levels(n) or {}
  local bass, mid, high = 0, 0, 0
  -- 低 / 中 / 高 段平均
  local nb, nm, nh = 0, 0, 0
  for i = 1, n do
    local v = levels[i] or 0
    local t = (i - 1) / (n - 1)
    if t < 0.28 then
      bass = bass + v; nb = nb + 1
    elseif t < 0.65 then
      mid = mid + v; nm = nm + 1
    else
      high = high + v; nh = nh + 1
    end
  end
  bass = nb > 0 and (bass / nb) or 0
  mid = nm > 0 and (mid / nm) or 0
  high = nh > 0 and (high / nh) or 0

  local atk = math.min(1, dt * 12)
  local rel = math.min(1, dt * 5)
  local function smooth(cur, target)
    if target > cur then return lerp(cur, target, atk) end
    return lerp(cur, target, rel)
  end
  bassS = smooth(bassS, bass)
  midS = smooth(midS, mid)
  highS = smooth(highS, high)

  local e = engine.vis_energy() or 0
  energyS = smooth(energyS, e)
  energyAvg = lerp(energyAvg, energyS, math.min(1, dt * 1.1))
  local onset = clamp(energyS - energyAvg * 1.1, 0, 1)
  if onset > pulseEnv then
    pulseEnv = lerp(pulseEnv, onset, math.min(1, dt * 18))
  else
    pulseEnv = pulseEnv * (1 - math.min(1, dt * 4.5))
  end
end

function on_init(w, h)
  bassS, midS, highS, energyS = 0, 0, 0, 0
  pulseEnv, energyAvg, hueShift = 0, 0.03, 0
end

function on_resize(w, h)
end

function on_frame(dt, w, h)
  if w < 4 or h < 4 then
    return
  end

  update_bands(dt)

  local sum = bassS + midS + highS + 1e-5
  local wb, wm, wh = bassS / sum, midS / sum, highS / sum

  -- 色温：低频暖(~2200K) → 中性(~4500K) → 高频冷(~9000K)
  local kelvin = 2200 * wb + 4500 * wm + 9000 * wh
  -- 能量抬一点对比；安静时偏中性
  local quiet = 1.0 - clamp(energyS * 1.4, 0, 0.75)
  kelvin = lerp(kelvin, 5200, quiet * 0.55)

  local kr, kg, kb = kelvin_rgb(kelvin)

  -- 额外：高频略推青紫色相，低频略推品红暖边（很淡）
  local targetHue = lerp(0.05, 0.62, wh) -- 暖红橙 → 冷蓝
  targetHue = lerp(targetHue, 0.08, wb * 0.5)
  hueShift = lerp(hueShift, targetHue, math.min(1, dt * 3.5))
  local hr, hg, hb = hsv_to_rgb(hueShift, 0.55 + midS * 0.25, 1.0)

  local r = math.floor(lerp(kr, hr, 0.28))
  local g = math.floor(lerp(kg, hg, 0.28))
  local b = math.floor(lerp(kb, hb, 0.28))

  -- 叠加透明度：有音乐时更明显，节拍瞬间略闪
  local alpha = 0.06 + energyS * 0.16 + pulseEnv * 0.08
  alpha = clamp(alpha, 0.04, 0.32)

  -- 全屏一层
  engine.fill_rect(0, 0, w, h, r, g, b, alpha)

  -- 顶部/底部极淡渐变带（两层矮矩形），增强“氛围光”而不是纯色块
  local bandH = math.max(8, h * 0.12)
  local aEdge = alpha * 0.55
  engine.fill_rect(0, 0, w, bandH, r, g, b, aEdge)
  engine.fill_rect(0, h - bandH, w, bandH, r, g, b, aEdge * 0.85)

  -- 低频时底部再叠一点暖光
  if bassS > 0.08 then
    local warmA = bassS * 0.10 + pulseEnv * 0.05
    engine.fill_rect(0, h * 0.55, w, h * 0.45, 255, 140, 60, warmA)
  end
  -- 高频时顶部叠一点冷光
  if highS > 0.08 then
    local coolA = highS * 0.09
    engine.fill_rect(0, 0, w, h * 0.4, 80, 140, 255, coolA)
  end
end
