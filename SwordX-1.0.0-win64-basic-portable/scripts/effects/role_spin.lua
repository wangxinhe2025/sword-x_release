-- 组件旋转示例：封面缓转 + 播放键随低音轻摆

local coverAng = 0
local energySmooth = 0

local function lerp(a, b, t)
  return a + (b - a) * t
end

function on_init(w, h)
  coverAng = 0
  energySmooth = 0
end

function on_frame(dt, w, h)
  local e = 0
  if engine.is_playing() then
    e = engine.vis_energy() or 0
    local levels = engine.vis_levels(4)
    if levels then
      e = math.max(e, (levels[1] or 0) * 0.8 + (levels[2] or 0) * 0.2)
    end
  end
  energySmooth = lerp(energySmooth, e, math.min(1, dt * 8))

  -- 封面持续旋转；越响转得越快（与皮肤 --spin 叠加）
  local rpm = 8 + energySmooth * 36
  coverAng = coverAng + dt * rpm * 6 -- deg/sec ≈ rpm*6
  engine.set_role_angle("main.cover", coverAng)
  -- 读回验证（也可留给其它逻辑）
  -- local a = engine.role_angle("main.cover")

  -- 播放键：随能量左右轻摆
  local sway = math.sin((coverAng * 0.07) + energySmooth * 3) * (4 + energySmooth * 14)
  engine.set_role_angle("main.play", sway)
  engine.set_role_angle("main.pause", sway * 0.85)
end
