-- 人声消除（STFT 频域版）
--
-- 宿主原语：engine.rfft / engine.irfft / engine.spec_gain / engine.vmul
-- Lua 编排：Mid/Side、窗、OLA、人声带 keep 曲线
--
-- 建议关闭自带 EQ。开头约 N 样点延迟（暖机）近静音属正常。
-- 若卡顿：把 n 改成 256，或用 vocal_remove.lua。

local cfg = {
  n = 512,
  vocal_lo = 180,
  vocal_hi = 5000,
  mid_keep_vocal = 0.12,
  mid_keep_bass = 0.85,
  mid_keep_air = 0.55,
}

local PI = math.pi
local N, HOP, BINS = cfg.n, cfg.n // 2, cfg.n // 2 + 1
local sample_rate = 48000
local hann, keep = {}, {}
local time_buf, fft_re, fft_im, synth = {}, {}, {}, {}
local mid_ola = {}
local side_fifo = {}
local in_fifo_l, in_fifo_r = {}, {}
local out_fifo_l, out_fifo_r = {}, {}
local fifo_fill = 0
local out_read, out_write, out_count = 1, 1, 0
local OUT_CAP = 8192
local ready = false

local function rebuild(sr)
  sample_rate = sr
  N = cfg.n
  HOP = N // 2
  BINS = N // 2 + 1
  if type(engine.rfft) ~= "function" then
    error("engine.rfft unavailable")
  end

  for k = 1, N do
    local t = (k - 1) / N
    hann[k] = 0.5 * (1 - math.cos(2 * PI * t))
    time_buf[k], synth[k], mid_ola[k] = 0, 0, 0
  end
  for k = 1, BINS do
    fft_re[k], fft_im[k] = 0, 0
  end

  for k = 0, BINS - 1 do
    local freq = k * sample_rate / N
    local g
    if freq < cfg.vocal_lo then
      local t = freq / cfg.vocal_lo
      g = cfg.mid_keep_bass + (cfg.mid_keep_vocal - cfg.mid_keep_bass) * t
    elseif freq <= cfg.vocal_hi then
      g = cfg.mid_keep_vocal
    else
      local t = math.min(1.0, (freq - cfg.vocal_hi) / math.max(cfg.vocal_hi, 1))
      g = cfg.mid_keep_vocal + (cfg.mid_keep_air - cfg.mid_keep_vocal) * t
    end
    keep[k + 1] = g
  end

  for i = 1, N do
    in_fifo_l[i], in_fifo_r[i], side_fifo[i] = 0, 0, 0
  end
  fifo_fill = 0
  for i = 1, OUT_CAP do
    out_fifo_l[i], out_fifo_r[i] = 0, 0
  end
  out_read, out_write, out_count = 1, 1, 0
  ready = true
end

local function push_out(l, r)
  if out_count >= OUT_CAP then
    out_read = out_read % OUT_CAP + 1
    out_count = out_count - 1
  end
  out_fifo_l[out_write] = l
  out_fifo_r[out_write] = r
  out_write = out_write % OUT_CAP + 1
  out_count = out_count + 1
end

local function pop_out()
  local l = out_fifo_l[out_read]
  local r = out_fifo_r[out_read]
  out_read = out_read % OUT_CAP + 1
  out_count = out_count - 1
  return l, r
end

local function process_one_frame()
  for k = 1, N do
    time_buf[k] = 0.5 * (in_fifo_l[k] + in_fifo_r[k])
  end
  engine.vmul(time_buf, hann)
  engine.rfft(time_buf, fft_re, fft_im)
  engine.spec_gain(fft_re, fft_im, keep)
  engine.irfft(fft_re, fft_im, time_buf)

  for k = 1, N do
    synth[k] = time_buf[k]
  end
  engine.vmul(synth, hann)
  engine.vadd(mid_ola, synth)

  for k = 1, HOP do
    local mid = mid_ola[k]
    local side = side_fifo[k]
    local l = mid + side
    local r = mid - side
    if l > 1 then l = 1 elseif l < -1 then l = -1 end
    if r > 1 then r = 1 elseif r < -1 then r = -1 end
    push_out(l, r)
    mid_ola[k] = 0
  end
  for k = 1, N - HOP do
    mid_ola[k] = mid_ola[k + HOP]
  end
  for k = N - HOP + 1, N do
    mid_ola[k] = 0
  end

  for i = 1, N - HOP do
    in_fifo_l[i] = in_fifo_l[i + HOP]
    in_fifo_r[i] = in_fifo_r[i + HOP]
    side_fifo[i] = side_fifo[i + HOP]
  end
  for i = N - HOP + 1, N do
    in_fifo_l[i], in_fifo_r[i], side_fifo[i] = 0, 0, 0
  end
  fifo_fill = fifo_fill - HOP
end

function on_configure(sr, _)
  rebuild(sr)
end

function on_reset()
  if sample_rate > 0 then
    rebuild(sample_rate)
  end
end

function process(pcm, frames, channels, sr)
  if channels < 2 then
    return
  end
  if (not ready) or sr ~= sample_rate then
    rebuild(sr)
  end

  for i = 0, frames - 1 do
    local li = i * channels + 1
    local ri = li + 1
    local l = pcm[li]
    local r = pcm[ri]
    local side = 0.5 * (l - r)

    fifo_fill = fifo_fill + 1
    in_fifo_l[fifo_fill] = l
    in_fifo_r[fifo_fill] = r
    side_fifo[fifo_fill] = side

    while fifo_fill >= N do
      process_one_frame()
    end

    local ol, orr = 0.0, 0.0
    if out_count > 0 then
      ol, orr = pop_out()
    end
    pcm[li] = ol
    pcm[ri] = orr
    for ch = 3, channels do
      pcm[i * channels + ch] = 0
    end
  end
end
