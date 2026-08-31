-- 爵士 EQ「夸张验证版」——听感要一眼能出（闷低频/狠提中频/砍高频）
-- 正常爵士曲线太轻，难判断 Lua DSP 是否生效；本脚本专用于跑通验证。
--
-- 系数在 Lua；样点热循环走宿主 engine.biquad_process。
-- 使用：菜单勾选或 --lua scripts\jazz_eq.lua；建议关闭自带 EQ。

local PI = math.pi
local Q = 1.41421356237 -- ~1 octave，与 C++ Equalizer 一致

local freqs = { 31, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000 }
local gains_db = { -12, -12, -10, -4, 6, 12, 10, 2, -10, -12 }
local preamp_db = -8.0

local filters = {}
local preamp_gain = 1.0
local configured_rate = 0
local configured_ch = 0

local limiter_gain = 1.0
local limiter_attack = 0.05
local limiter_release = 0.002

local function db_to_lin(db)
  return 10 ^ (db / 20)
end

local function make_peaking(sample_rate, freq, q, gain_db)
  if sample_rate <= 0 or freq <= 0 or q <= 0 then
    return { b0 = 1, b1 = 0, b2 = 0, a1 = 0, a2 = 0, z1 = 0, z2 = 0 }
  end

  local nyquist = sample_rate * 0.49
  if freq > nyquist then
    freq = nyquist
  end

  local A = 10 ^ (gain_db / 40)
  local w0 = 2 * PI * freq / sample_rate
  local cosw0 = math.cos(w0)
  local sinw0 = math.sin(w0)
  local alpha = sinw0 / (2 * q)

  local b0n = 1 + alpha * A
  local b1n = -2 * cosw0
  local b2n = 1 - alpha * A
  local a0n = 1 + alpha / A
  local a1n = -2 * cosw0
  local a2n = 1 - alpha / A

  return {
    b0 = b0n / a0n,
    b1 = b1n / a0n,
    b2 = b2n / a0n,
    a1 = a1n / a0n,
    a2 = a2n / a0n,
    z1 = 0,
    z2 = 0,
  }
end

local function rebuild(sample_rate, channels)
  filters = {}
  preamp_gain = db_to_lin(preamp_db)
  limiter_gain = 1.0
  configured_rate = sample_rate
  configured_ch = channels

  for band = 1, #freqs do
    filters[band] = {}
    local gd = gains_db[band]
    for ch = 1, channels do
      if math.abs(gd) < 0.05 then
        filters[band][ch] = { b0 = 1, b1 = 0, b2 = 0, a1 = 0, a2 = 0, z1 = 0, z2 = 0, bypass = true }
      else
        local f = make_peaking(sample_rate, freqs[band], Q, gd)
        f.bypass = false
        filters[band][ch] = f
      end
    end
  end
end

local function reset_state()
  for band = 1, #filters do
    for ch = 1, #filters[band] do
      local f = filters[band][ch]
      f.z1 = 0
      f.z2 = 0
    end
  end
  limiter_gain = 1.0
end

function on_configure(sample_rate, channels)
  rebuild(sample_rate, channels)
end

function on_reset()
  reset_state()
end

function process(pcm, frames, channels, sample_rate)
  if sample_rate ~= configured_rate or channels ~= configured_ch or #filters == 0 then
    rebuild(sample_rate, channels)
  end
  if type(engine.biquad_process) ~= "function" then
    error("engine.biquad_process unavailable")
  end
  limiter_gain = engine.biquad_process(
    pcm, frames, channels, filters,
    preamp_gain, limiter_gain, limiter_attack, limiter_release
  )
end
