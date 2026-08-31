-- 火焰（粒子）：多发射点 + 湍流上升 + 色温随寿命衰减
-- 原理：每帧从底部喷粒子，受力(升力/阻力/横向噪声)，按寿命上色淡出。

local MAX = 220
local particles = {}
local free = {} -- 空闲索引栈
local timeSec = 0
local energySmooth = 0
local pulseEnv = 0
local energyAvg = 0.025
local spawnAcc = 0

-- 发射器相对底部中心的偏移（构造火苗轮廓）
local emitters = {
  { x = 0.00,  w = 0.045, power = 1.00 },
  { x = -0.04, w = 0.030, power = 0.75 },
  { x =  0.04, w = 0.030, power = 0.75 },
  { x = -0.075,w = 0.022, power = 0.45 },
  { x =  0.075,w = 0.022, power = 0.45 },
}

local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

local function lerp(a, b, t)
  return a + (b - a) * t
end

-- 廉价伪噪声（够用做湍流）
local function noise1(x)
  local s = math.sin(x * 12.9898) * 43758.5453
  return s - math.floor(s)
end

local function noise2(x, y)
  return noise1(x * 1.31 + y * 7.17 + 19.19)
end

local function heat_color(lifeT, heat)
  -- lifeT 0=新生 1=熄灭；heat 越高越偏白芯
  local t = clamp(lifeT, 0, 1)
  local r, g, b
  if t < 0.15 then
    local u = t / 0.15
    r = 255
    g = math.floor(lerp(245, 210, u))
    b = math.floor(lerp(220, 80, u))
  elseif t < 0.45 then
    local u = (t - 0.15) / 0.30
    r = 255
    g = math.floor(lerp(210, 140, u))
    b = math.floor(lerp(80, 30, u))
  elseif t < 0.75 then
    local u = (t - 0.45) / 0.30
    r = math.floor(lerp(255, 200, u))
    g = math.floor(lerp(140, 50, u))
    b = math.floor(lerp(30, 10, u))
  else
    local u = (t - 0.75) / 0.25
    r = math.floor(lerp(200, 40, u))
    g = math.floor(lerp(50, 20, u))
    b = math.floor(lerp(10, 15, u))
  end
  -- 高热粒子更亮
  local boost = 1.0 + heat * 0.25
  r = math.min(255, math.floor(r * boost))
  g = math.min(255, math.floor(g * boost))
  b = math.min(255, math.floor(b * (0.85 + heat * 0.2)))
  return r, g, b
end

local function alloc()
  if #free > 0 then
    return table.remove(free)
  end
  if #particles >= MAX then
    return nil
  end
  local i = #particles + 1
  particles[i] = {}
  return i
end

local function release(i)
  free[#free + 1] = i
  particles[i].alive = false
end

local function spawn_one(w, h, baseY, intensity)
  local i = alloc()
  if not i then
    return
  end
  local em = emitters[1 + math.floor(math.random() * #emitters)]
  local spread = em.w * w * (0.55 + math.random() * 0.9)
  local x = w * 0.5 + em.x * w + (math.random() - 0.5) * spread
  local heat = clamp(em.power * (0.55 + math.random() * 0.55) * (0.7 + intensity * 0.6), 0, 1)
  local life = lerp(0.55, 1.35, heat) * (0.85 + math.random() * 0.35)
  local up = -(55 + heat * 95 + intensity * 70 + math.random() * 40)

  local p = particles[i]
  p.alive = true
  p.x = x
  p.y = baseY + (math.random() - 0.3) * 6
  p.vx = (math.random() - 0.5) * (18 + intensity * 25)
  p.vy = up
  p.life = life
  p.age = 0
  p.size0 = lerp(2.2, 5.5, heat) * (0.75 + math.random() * 0.5)
  p.heat = heat
  p.seed = math.random() * 1000
  p.spin = (math.random() - 0.5) * 10
end

local function update_rhythm(dt)
  if not engine.is_playing() then
    energySmooth = energySmooth * (1 - math.min(1, dt * 2.2))
    pulseEnv = pulseEnv * (1 - math.min(1, dt * 3.5))
    return
  end
  local levels = engine.vis_levels(8)
  local bass = (levels and levels[1] or 0) * 0.65
      + (levels and levels[2] or 0) * 0.25
      + (levels and levels[3] or 0) * 0.10
  local e = math.max(bass, (engine.vis_energy() or 0) * 0.85)
  local atk = math.min(1, dt * 14)
  local rel = math.min(1, dt * 6)
  if e > energySmooth then
    energySmooth = lerp(energySmooth, e, atk)
  else
    energySmooth = lerp(energySmooth, e, rel)
  end
  energyAvg = lerp(energyAvg, energySmooth, math.min(1, dt * 1.0))
  local onset = clamp(energySmooth - energyAvg * 1.1, 0, 1)
  if onset > pulseEnv then
    pulseEnv = lerp(pulseEnv, onset, math.min(1, dt * 20))
  else
    pulseEnv = pulseEnv * (1 - math.min(1, dt * 4.2))
  end
end

function on_init(w, h)
  particles, free = {}, {}
  timeSec = 0
  energySmooth, energyAvg, pulseEnv, spawnAcc = 0, 0.025, 0, 0
  engine.set_paint_while_drag(false)
  -- 预热一点粒子，避免首帧空
  local baseY = h * 0.86
  for _ = 1, 40 do
    spawn_one(w, h, baseY, 0.3)
  end
end

function on_resize(w, h)
end

function on_frame(dt, w, h)
  if w < 16 or h < 16 then
    return
  end
  if engine.is_dragging() or engine.is_resizing() then
    return
  end
  if #particles == 0 and #free == 0 then
    on_init(w, h)
  end

  timeSec = timeSec + dt
  update_rhythm(dt)

  local cx = w * 0.5
  local baseY = h * 0.86
  local intensity = clamp(0.25 + energySmooth * 0.9 + pulseEnv * 0.7, 0, 1.6)

  -- 发射率：安静时也有火，节拍时猛喷
  local rate = 70 + intensity * 160 + pulseEnv * 120
  spawnAcc = spawnAcc + rate * dt
  while spawnAcc >= 1 do
    spawnAcc = spawnAcc - 1
    spawn_one(w, h, baseY, intensity)
  end

  -- 底部余烬（少而软，衬托粒子）
  engine.draw_circle(cx, baseY + 6, w * 0.10, 255, 40, 8, 0.10 + intensity * 0.06)
  engine.draw_circle(cx, baseY + 3, w * 0.055, 255, 90, 20, 0.14 + pulseEnv * 0.08)

  local batch = {}
  local nDraw = 0

  for i = 1, #particles do
    local p = particles[i]
    if p.alive then
      p.age = p.age + dt
      local lifeT = p.age / p.life
      if lifeT >= 1.0 or p.y < -20 then
        release(i)
      else
        -- 湍流：多层正弦 + 伪噪声，随高度加大横向扰动
        local rise = clamp((baseY - p.y) / (h * 0.55), 0, 1.5)
        local nx = noise2(p.seed + timeSec * 1.7, p.y * 0.04)
        local ny = noise2(p.seed * 1.3, timeSec * 2.1 + p.x * 0.03)
        local turbX = (nx - 0.5) * (55 + rise * 90) + math.sin(timeSec * 7 + p.seed) * 12
        local turbY = (ny - 0.5) * 20

        -- 升力随寿命衰减；中段最旺
        local lift = -(35 + p.heat * 50) * (1.05 - lifeT * 0.7) * (0.85 + intensity * 0.35)
        p.vx = p.vx + (turbX + p.spin * 3) * dt
        p.vy = p.vy + (lift + turbY) * dt
        -- 阻力
        p.vx = p.vx * (1 - math.min(0.95, dt * 1.8))
        p.vy = p.vy * (1 - math.min(0.6, dt * 0.35))

        p.x = p.x + p.vx * dt
        p.y = p.y + p.vy * dt

        -- 略向中轴收拢，形成尖顶火苗
        local pull = (cx - p.x) * (0.35 + rise * 0.9) * dt
        p.x = p.x + pull

        local fade = (1 - lifeT)
        fade = fade * fade -- 末端更快消失
        local a = fade * (0.28 + p.heat * 0.5) * (0.75 + intensity * 0.35)
        if a > 0.02 then
          local sz = p.size0 * lerp(1.35, 0.35, lifeT) * (0.95 + intensity * 0.2)
          local r, g, b = heat_color(lifeT, p.heat)
          -- 内置火焰小图：外层火舌 + 内核；高热加 spark
          local spr = (p.heat > 0.7 and "flame1") or (p.heat > 0.4 and "flame2") or "flame3"
          nDraw = nDraw + 1
          batch[nDraw] = {
            name = spr, x = p.x, y = p.y - sz * 0.15,
            size = sz * 2.1, a = a * 0.55, r = r, g = g, b = b,
          }
          nDraw = nDraw + 1
          batch[nDraw] = {
            name = spr, x = p.x, y = p.y - sz * 0.25,
            size = sz * 1.35, a = a, r = r, g = g, b = b,
          }
          if lifeT > 0.55 and p.heat > 0.35 then
            nDraw = nDraw + 1
            batch[nDraw] = {
              name = "ember1", x = p.x + (noise1(p.seed) - 0.5) * 4,
              y = p.y, size = sz * 0.45, a = a * 0.5, r = r, g = g, b = b,
            }
          end
          if lifeT < 0.2 and p.heat > 0.6 then
            nDraw = nDraw + 1
            batch[nDraw] = {
              name = "spark1", x = p.x, y = p.y - sz * 0.4,
              size = sz * 0.55, a = a * 0.7, r = 255, g = 250, b = 230,
            }
          end
        end
      end
    end
  end

  if nDraw > 0 then
    local budget = 480
    if nDraw > budget then
      local step = nDraw / budget
      local slim = {}
      for i = 1, budget do
        local idx = math.floor((i - 0.5) * step) + 1
        slim[i] = batch[idx]
      end
      engine.draw_sprites(slim)
    else
      engine.draw_sprites(batch)
    end
  end
end
