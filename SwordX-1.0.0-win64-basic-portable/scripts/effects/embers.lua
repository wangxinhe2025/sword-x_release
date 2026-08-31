-- 灰烬亮点：全屏稀疏余烬，受缓变气流卷着飘（非直线上升）

local MAX = 56
local particles = {}
local free = {}
local timeSec = 0
local energySmooth = 0
local pulseEnv = 0
local energyAvg = 0.02
local spawnAcc = 0
-- 缓变风场（整窗共享，像空气团）
local windX, windY = 0, -12
local gustX, gustY = 0, 0
local windTargetX, windTargetY = 8, -18
local windRetarget = 0

local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

local function lerp(a, b, t)
  return a + (b - a) * t
end

local function noise1(x)
  local s = math.sin(x * 12.9898) * 43758.5453
  return s - math.floor(s)
end

-- 空间相关的伪噪声，做局部涡流
local function flow_at(x, y, t, seed)
  local n1 = noise1(x * 0.011 + t * 0.17 + seed)
  local n2 = noise1(y * 0.013 - t * 0.13 + seed * 1.7)
  local n3 = noise1(x * 0.007 - y * 0.009 + t * 0.09 + seed * 0.3)
  local ang = (n1 * 2 + n2 + n3) * math.pi * 2
  local mag = 0.45 + n2 * 0.9
  return math.cos(ang) * mag, math.sin(ang) * mag
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

local function count_alive()
  local n = 0
  for i = 1, #particles do
    if particles[i].alive then
      n = n + 1
    end
  end
  return n
end

local function spawn_one(w, h, intensity, forceAnywhere)
  local i = alloc()
  if not i then
    return
  end

  local kindRoll = math.random()
  local kind = (kindRoll < 0.5 and 1) or (kindRoll < 0.85 and 2) or 3
  local hot = kind == 1 and (0.55 + math.random() * 0.45) or (0.2 + math.random() * 0.5)

  -- 全屏出生：多数偏下半区，也有从侧边/中部「卷入」的
  local x, y
  local zone = math.random()
  if forceAnywhere or zone < 0.55 then
    x = math.random() * w
    y = h * (0.35 + math.random() * 0.62)
  elseif zone < 0.78 then
    -- 侧边卷入
    x = (math.random() < 0.5) and (-4 + math.random() * 10) or (w - 6 + math.random() * 10)
    y = math.random() * h * 0.85
  else
    x = math.random() * w
    y = h * (0.15 + math.random() * 0.35)
  end

  local life = lerp(2.8, 6.5, 1 - hot * 0.35) * (0.9 + math.random() * 0.5)
  if kind == 3 then
    life = life * 1.35
  end

  -- 初速跟当前风场，再加一点乱流，避免齐刷刷同向
  local jitter = 10 + math.random() * 18
  local p = particles[i]
  p.alive = true
  p.kind = kind
  p.x = x
  p.y = y
  p.vx = windX * (0.4 + math.random() * 0.5) + (math.random() - 0.5) * jitter
  p.vy = windY * (0.35 + math.random() * 0.55) + (math.random() - 0.35) * (jitter * 0.6)
  p.life = life
  p.age = 0
  p.hot = hot
  p.seed = math.random() * 1000
  p.phase = math.random() * math.pi * 2
  p.freq = 1.8 + math.random() * 5.5 -- 闪烁快慢各不相同
  p.flashPhase = math.random() * math.pi * 2
  p.flashFreq = 0.35 + math.random() * 1.4 -- 偶发猛亮
  p.dimBias = 0.15 + math.random() * 0.45 -- 平时偏暗程度
  p.drag = 0.55 + math.random() * 0.7
  p.size0 = (kind == 1 and lerp(0.85, 1.6, hot))
    or (kind == 2 and lerp(1.2, 2.2, hot))
    or lerp(1.8, 3.2, math.random())
  p.spin = (math.random() - 0.5) * 2.2
end

local function retarget_wind(intensity)
  -- 偶尔换一股风向：偏上但带明显横向，像穿堂风
  local side = (math.random() < 0.5) and -1 or 1
  windTargetX = side * (6 + math.random() * 28 + intensity * 10)
  windTargetY = -(6 + math.random() * 22 + intensity * 8)
  -- 偶发几乎水平的气流
  if math.random() < 0.22 then
    windTargetY = windTargetY * (0.15 + math.random() * 0.35)
    windTargetX = windTargetX * (1.2 + math.random() * 0.6)
  end
  windRetarget = 1.6 + math.random() * 3.8
end

local function update_wind(dt, intensity)
  windRetarget = windRetarget - dt
  if windRetarget <= 0 then
    retarget_wind(intensity)
  end
  local ease = math.min(1, dt * (0.35 + math.random() * 0.15))
  windX = lerp(windX, windTargetX, ease)
  windY = lerp(windY, windTargetY, ease)

  -- 短促阵风
  if math.random() < dt * (0.35 + pulseEnv * 1.2) then
    local side = (math.random() < 0.5) and -1 or 1
    gustX = side * (18 + math.random() * 40 + pulseEnv * 35)
    gustY = -(8 + math.random() * 28) + (math.random() - 0.5) * 16
  end
  gustX = gustX * (1 - math.min(1, dt * 1.8))
  gustY = gustY * (1 - math.min(1, dt * 1.8))
end

local function update_rhythm(dt)
  if not engine.is_playing() then
    energySmooth = energySmooth * (1 - math.min(1, dt * 1.8))
    pulseEnv = pulseEnv * (1 - math.min(1, dt * 3.2))
    return
  end
  local levels = engine.vis_levels(8)
  local bass = (levels and levels[1] or 0) * 0.55
    + (levels and levels[2] or 0) * 0.30
    + (levels and levels[3] or 0) * 0.15
  local e = math.max(bass * 0.85, (engine.vis_energy() or 0) * 0.75)
  local atk = math.min(1, dt * 12)
  local rel = math.min(1, dt * 5)
  if e > energySmooth then
    energySmooth = lerp(energySmooth, e, atk)
  else
    energySmooth = lerp(energySmooth, e, rel)
  end
  energyAvg = lerp(energyAvg, energySmooth, math.min(1, dt * 0.9))
  local onset = clamp(energySmooth - energyAvg * 1.08, 0, 1)
  if onset > pulseEnv then
    pulseEnv = lerp(pulseEnv, onset, math.min(1, dt * 18))
  else
    pulseEnv = pulseEnv * (1 - math.min(1, dt * 3.8))
  end
end

local function ember_color(hot, flicker)
  local t = clamp(1 - hot * 0.85 + (1 - flicker) * 0.15, 0, 1)
  local r, g, b
  if t < 0.25 then
    local u = t / 0.25
    r, g, b = 255, math.floor(lerp(245, 200, u)), math.floor(lerp(210, 90, u))
  elseif t < 0.6 then
    local u = (t - 0.25) / 0.35
    r, g, b = 255, math.floor(lerp(200, 110, u)), math.floor(lerp(90, 35, u))
  else
    local u = (t - 0.6) / 0.4
    r = math.floor(lerp(255, 90, u))
    g = math.floor(lerp(110, 40, u))
    b = math.floor(lerp(35, 28, u))
  end
  return r, g, b
end

function on_init(w, h)
  particles, free = {}, {}
  timeSec = 0
  energySmooth, energyAvg, pulseEnv, spawnAcc = 0, 0.02, 0, 0
  windX, windY, gustX, gustY = 6, -14, 0, 0
  retarget_wind(0.3)
  engine.set_paint_while_drag(false)
  for _ = 1, 22 do
    spawn_one(w, h, 0.3, true)
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
  local intensity = clamp(0.15 + energySmooth * 0.85 + pulseEnv * 0.6, 0, 1.4)
  update_wind(dt, intensity)

  local alive = count_alive()
  -- 安静约 20，重拍可到 MAX
  local target = math.floor(20 + intensity * 22 + pulseEnv * 12)
  target = clamp(target, 16, MAX)
  local rate = 3.5 + intensity * 5 + pulseEnv * 8
  if alive < target then
    spawnAcc = spawnAcc + rate * dt
  else
    spawnAcc = 0
  end
  while spawnAcc >= 1 and count_alive() < target do
    spawnAcc = spawnAcc - 1
    spawn_one(w, h, intensity, false)
  end

  local batch = {}
  local n = 0
  local wx = windX + gustX
  local wy = windY + gustY

  for i = 1, #particles do
    local p = particles[i]
    if p.alive then
      p.age = p.age + dt
      local lifeT = p.age / p.life
      if lifeT >= 1.0 then
        release(i)
      else
        p.phase = p.phase + p.freq * dt * (0.8 + pulseEnv * 0.4)
        local fx, fy = flow_at(p.x, p.y, timeSec, p.seed)
        -- 气流：全局风 + 局部涡流 + 个体自旋；越「轻」越跟风
        local follow = p.drag * (0.85 + (1 - p.hot) * 0.35)
        local ax = (wx * 1.1 + fx * 42 + p.spin * 10) * follow
        local ay = (wy * 1.05 + fy * 28 - 4 - p.hot * 6) * follow
        -- 偶发侧向「被掀起」
        if math.random() < dt * 0.15 then
          ax = ax + (math.random() - 0.5) * 50
          ay = ay - math.random() * 25
        end

        p.vx = p.vx + ax * dt
        p.vy = p.vy + ay * dt
        -- 空气阻力：速度被风「托着」而不是匀速直冲
        local damp = 1 - math.min(0.92, dt * (1.4 + follow * 0.6))
        p.vx = p.vx * damp + wx * (1 - damp) * 0.35
        p.vy = p.vy * damp + wy * (1 - damp) * 0.35

        p.x = p.x + p.vx * dt
        p.y = p.y + p.vy * dt

        -- 出界：从对侧/底部再卷入，保持全屏分布
        local pad = 8
        if p.x < -pad then
          p.x = w + pad * 0.5
          p.vx = p.vx * 0.3 + windX * 0.2
        elseif p.x > w + pad then
          p.x = -pad * 0.5
          p.vx = p.vx * 0.3 + windX * 0.2
        end
        if p.y < -pad then
          -- 顶部飘出：从下半区重新卷入，寿命继续
          p.y = h * (0.55 + math.random() * 0.4)
          p.x = math.random() * w
          p.vx = windX * 0.4 + (math.random() - 0.5) * 12
          p.vy = windY * 0.3
          p.age = p.age * 0.55
        elseif p.y > h + pad then
          p.y = h * 0.2 + math.random() * h * 0.3
          p.vy = windY * 0.5 - math.random() * 8
        end

        local envelope = 1
        if lifeT < 0.1 then
          envelope = lifeT / 0.1
        elseif lifeT > 0.6 then
          envelope = (1 - lifeT) / 0.4
        end
        envelope = envelope * envelope

        -- 明暗闪光：平时压暗，快速正弦 + 不规则尖峰猛亮
        p.flashPhase = p.flashPhase + p.flashFreq * dt
        local breath = 0.5 + 0.5 * math.sin(p.phase)
        breath = breath * breath -- 更长时间偏暗
        local spike = math.sin(p.flashPhase * 2.7 + p.seed)
        local flash = 0
        if spike > 0.78 then
          -- 尖峰：突然亮一下
          flash = ((spike - 0.78) / 0.22) ^ 0.45
        elseif math.sin(p.phase * 0.41 + p.seed * 2.1) > 0.94 then
          flash = 0.55 + 0.45 * math.random() -- 偶发乱闪
        end
        -- flick: 0 近熄 → 1 全亮；对比拉大
        local flick = clamp(p.dimBias * 0.35 + breath * (1 - p.dimBias) * 0.55 + flash * 0.95, 0, 1)
        if flash > 0.55 then
          flick = clamp(flick + 0.25, 0, 1)
        end
        -- 节拍时整体更容易亮一下
        flick = clamp(flick + pulseEnv * 0.2 * breath, 0, 1)

        local baseA = (p.kind == 1 and 0.62) or (p.kind == 2 and 0.48) or 0.22
        local a = clamp(
          envelope * flick * baseA * (0.55 + p.hot * 0.55) * (0.65 + intensity * 0.35),
          0, 0.95)
        -- 暗相位仍画一点点，避免「消失」；很暗时几乎看不见
        if a > 0.012 then
          local sz = p.size0 * lerp(1.15, 0.45, lifeT)
            * (0.75 + flick * 0.55 + intensity * 0.1)
          local r, g, b = ember_color(p.hot * (0.55 + flick * 0.55) * (1 - lifeT * 0.35), flick)
          if p.kind == 3 then
            r = math.floor(r * 0.5 + 36)
            g = math.floor(g * 0.45 + 28)
            b = math.floor(b * 0.4 + 26)
            a = a * 0.65
          end

          -- 暗时几乎只有一点核；亮时晕大、核白
          local haloA = a * lerp(0.06, 0.22, flick)
          n = n + 1
          batch[n] = {
            x = p.x, y = p.y, size = sz * lerp(1.6, 3.2, flick),
            a = haloA, r = r, g = g, b = b,
          }
          n = n + 1
          batch[n] = { x = p.x, y = p.y, size = sz, a = a, r = r, g = g, b = b }
          if flick > 0.62 then
            n = n + 1
            batch[n] = {
              x = p.x, y = p.y, size = sz * lerp(0.35, 0.55, flick),
              a = a * lerp(0.5, 0.95, flick),
              r = 255, g = math.floor(lerp(220, 252, flick)), b = math.floor(lerp(160, 235, flick)),
            }
          end
        end
      end
    end
  end

  if n > 0 then
    engine.draw_points(batch)
  end
end
