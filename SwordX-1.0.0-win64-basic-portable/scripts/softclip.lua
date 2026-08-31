-- 简易直流阻断 + 软削波示例
-- DC 在 Lua；tanh 批处理走宿主 engine.softclip。

local prev = {}
local alpha = 0.995
local drive = 1.8

function on_configure(_, channels)
  prev = {}
  for ch = 1, channels do
    prev[ch] = 0.0
  end
end

function on_reset()
  for i = 1, #prev do
    prev[i] = 0.0
  end
end

function process(pcm, frames, channels, _)
  for i = 0, frames - 1 do
    for ch = 1, channels do
      local idx = i * channels + ch
      local x = pcm[idx]
      local y = x - prev[ch]
      prev[ch] = prev[ch] + alpha * y
      pcm[idx] = y
    end
  end
  -- Lua 5.5 默认无 math.tanh（COMPAT 关闭）；软削波走宿主原语
  engine.softclip(pcm, frames, channels, drive)
end
