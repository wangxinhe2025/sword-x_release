-- 人声增强（时域 Mid 增益版）
-- 原理：提升居中成分 Mid=(L+R)/2，Side 略收一点，让干声更靠前。
-- 限制：居中乐器/混响也会被抬；单声道无效。建议关掉自带 EQ。

local mid_boost = 1.85   -- Mid 增益（>1 增强人声）
local side_keep = 0.9    -- Side 保留（略降可更突出中置）
local makeup = 0.92      -- 总电平略收，减轻削顶

function on_configure(_, _)
end

function on_reset()
end

function process(pcm, frames, channels, sample_rate)
  if channels < 2 then
    return
  end

  for i = 0, frames - 1 do
    local li = i * channels + 1
    local ri = li + 1
    local l = pcm[li]
    local r = pcm[ri]
    local mid = 0.5 * (l + r) * mid_boost
    local side = 0.5 * (l - r) * side_keep
    l = (mid + side) * makeup
    r = (mid - side) * makeup
    if l > 1 then l = 1 elseif l < -1 then l = -1 end
    if r > 1 then r = 1 elseif r < -1 then r = -1 end
    pcm[li] = l
    pcm[ri] = r
    for ch = 3, channels do
      pcm[i * channels + ch] = 0
    end
  end
end
