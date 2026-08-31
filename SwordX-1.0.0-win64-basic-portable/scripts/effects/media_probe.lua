-- 示例：播放进度/音量/文件信息/标签/独占/窗口位置（宿主已做边界夹紧）
-- tag_write 会关文件重开，勿每帧调用；写标签示例默认注释。

local lastPath = ""

function on_init(w, h)
  lastPath = engine.file_path() or ""
  -- 可选写标签（默认关闭）：
  -- local cap = engine.tag_capability()
  -- if cap == "readwrite" then
  --   engine.tag_write({ comment = "probed by media_probe.lua" })
  -- end
end

function on_frame(dt, w, h)
  local playing = engine.is_playing()
  local prog = clamp01(engine.progress() or 0)
  local vol = clamp01(engine.volume() or 0)
  local path = engine.file_path() or ""
  local excl = engine.wasapi_exclusive()
  local exclOn = engine.wasapi_exclusive_active()
  local cw, ch = engine.client_size()

  -- 底边：进度（绿）+ 音量（蓝细线）
  if cw and ch and cw > 8 and ch > 8 then
    local y0 = ch - 5
    engine.fill_rect(0, y0, cw, 3, 40, 40, 48, 0.5)
    engine.fill_rect(0, y0, prog * cw, 3, 80, 200, 140, 0.9)
    engine.fill_rect(0, y0 + 3, vol * cw, 2, 90, 160, 255, 0.75)
  end

  -- 左上角：独占状态（灰=关偏好 / 黄=偏好开 / 红=会话独占中）
  local r, g, b = 90, 90, 90
  if exclOn then
    r, g, b = 255, 90, 70
  elseif excl then
    r, g, b = 240, 180, 60
  end
  engine.draw_circle(10, 10, playing and 5 or 4, r, g, b, 0.9)

  -- 换曲读标签与 track_info（只读）
  if path ~= "" and path ~= lastPath then
    lastPath = path
    engine.tag_read()
    engine.track_info()
    -- 边界演示（不会越界）：engine.seek(-1) / seek_ratio(2) 会被夹紧
    -- engine.seek_ratio(0)
  end
end

function clamp01(v)
  if v < 0 then return 0 end
  if v > 1 then return 1 end
  return v
end
