-- 人声消除（卡拉 OK / 「人生消除」简易版）
-- 原理：多数流行歌人声偏置中（L≈R），用 L-R / R-L 抵消中央成分，保留左右差异（伴奏）。
-- 限制：仅立体声有效；人声不完全居中、或伴奏也居中时效果会变差/伤伴奏。
-- 建议：关掉自带 EQ，避免叠乘。

local last_channels = 2

function on_configure(_, channels)
  last_channels = channels
end

function on_reset()
end

-- process：宿主对每一块 PCM 调用一次（约 15ms）
-- pcm 1-based 交错 float；立体声：pcm[i*2+1]=L, pcm[i*2+2]=R
function process(pcm, frames, channels, sample_rate)
  if channels < 2 then
    return -- 单声道无法做中置消除
  end

  for i = 0, frames - 1 do
    local li = i * channels + 1
    local ri = li + 1
    local l = pcm[li]
    local r = pcm[ri]
    -- 差分：去掉相关的中置人声；*0.5 避免电平偏大
    local side = (l - r) * 0.5
    pcm[li] = side
    pcm[ri] = -side
    -- 多余声道静音（若有）
    for ch = 3, channels do
      pcm[i * channels + ch] = 0.0
    end
  end
end
