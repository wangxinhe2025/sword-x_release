-- 半音量增益示例（验证 Lua DSP 闭环）
-- pcm: 1-based 交错 float 缓冲，可写；#pcm == frames * channels

local gain = 0.5

function on_configure(sample_rate, channels)
  -- 可用于分配延迟线等；本例仅记录
  _G.sample_rate = sample_rate
  _G.channels = channels
end

function on_reset()
  -- Seek / 切歌时清空滤波器状态（本例无状态）
end

-- process：宿主对每一块 PCM 调用一次（约 15ms，帧数 ≈ sample_rate/66，至少 64）
--
-- @param pcm          userdata，带 __index / __newindex / __len
--                     1-based 可写 float 缓冲；交错布局 L R L R ...
--                     下标：第 i 帧（0-based）第 ch 声道（1-based）→ pcm[i * channels + ch]
--                     #pcm == frames * channels
--                     样本范围约 -1.0 ~ 1.0；就地修改即可，宿主再写回设备格式（s16/s32/float）
-- @param frames       number，本块「每声道」采样点数（帧数），不是总样本数
-- @param channels     number，声道数（立体声一般为 2）
-- @param sample_rate  number，当前输出采样率（Hz），与设备协商结果一致
--
-- 注意：跑在播放线程；过重会导致卡顿，超时会被宿主 bypass。
--       Seek / 切歌后会先调 on_reset（若有）。采样率或声道变化会调 on_configure。
function process(pcm, frames, channels, sample_rate)
  local n = frames * channels
  for i = 1, n do
    pcm[i] = pcm[i] * gain
  end
end
