# Lua 窗口特效（UI）

与根目录 DSP 脚本分离：这里的脚本跑在 **UI 线程**，叠画在主播放窗口分层缓冲上。

## 管线

```
OnTimer(~30fps) → Invalidate
OnPaint → Lua on_frame（入队绘制 + 色/透明覆盖）
       → 皮肤绘制（含本帧颜色/透明度）
       → FixGdiAlpha → FlushOverlay → 还原皮肤覆盖 → Present
```

菜单：**Lua 窗口特效**（枚举本目录 `*.lua`）。  
皮肤绑定：在皮肤编辑器选中 `main.window` → 背景 → **Lua特效**，写入 `--lua-ui-effect: <stem>`；播放器切肤后自动加载。

## 脚本约定

```lua
function on_frame(dt, w, h) end   -- 必需；dt 秒，w/h 整窗逻辑客户区（含 --board）
function on_init(w, h) end        -- 可选
function on_resize(w, h) end      -- 可选
function on_shutdown() end        -- 可选
```

## 宿主 API

| API | 说明 |
|-----|------|
| `engine.is_playing()` | 是否正在播放 |
| `engine.vis_energy()` | 近期 PCM RMS 能量，约 0..1（**不**接管频谱绘制） |
| `engine.vis_levels(n)` | `n`（1..32）个对数频带电平，1-based，约 0..1（**不**接管） |
| `engine.claim_vis()` | 本帧接管 `main.vis`，宿主跳过原生频谱 |
| `engine.vis_rect()` | 返回 `main.vis` 的 `x,y,w,h`，并 **claim**；失败无返回值 |
| `engine.list_roles()` | 主窗可抖 role id 表（不含 `main.window`） |
| `engine.role_rect(id)` | 返回 `x,y,w,h`（映射后、不含 shake/scale）；失败无返回值 |
| `engine.set_role_shake(id, dx, dy)` | 本帧该组件平移（约 ±12）；命中测试不偏移 |
| `engine.set_role_scale(id, scale)` | 本帧绕中心缩放（约 0.5..1.8，`1`=原大）；命中测试不缩放 |
| `engine.set_role_angle(id, deg)` | 本帧绕中心旋转（度，可累加；`\|deg\|<0.01` 清除）；命中测试不旋转 |
| `engine.role_angle(id)` | 读本帧已设角度（未设为 `0`） |
| `engine.set_role_color(id, r,g,b [,a])` | 本帧文字色（rgb 0..255，a 0..1）；`main.window`/装饰兼改衬底 |
| `engine.set_role_opacity(id, op)` | 本帧组件透明度（0..1 或 0..100） |
| `engine.set_role_visible(id, visible)` | 设置组件运行时可见性覆盖并返回 effective 值；隐藏后不绘制、不命中；覆盖持续到 clear 或脚本卸载 |
| `engine.toggle_role_visible(id)` | 翻转组件本地运行时可见性并返回 effective 值（仍受隐藏父级约束） |
| `engine.clear_role_visible(id)` | 清除运行时覆盖、恢复皮肤 `visible` 基础值并返回 effective 值 |
| `engine.role_visible(id)` | 返回组件当前 effective 可见性（含父级约束） |
| `engine.set_window_opacity(op)` | 本帧主窗衬底透明度（`main.window` `--window-opacity`） |
| `engine.set_control_opacity(op)` | 本帧主窗控件透明度（`main.window` `--control-opacity`） |
| `engine.position()` / `duration()` | 当前位置 / 时长（秒，≥0，上限约 7 天） |
| `engine.progress()` | 进度 0..1 |
| `engine.seek(sec)` / `seek_ratio(r)` | 跳转；`sec`/`r` 须有限，分别夹紧到 `[0,duration]` / `[0,1]` |
| `engine.volume()` / `set_volume(v)` | 音量读写，夹紧 0..1；`set_volume` 返回实际值 |
| `engine.file_path()` | 当前文件 utf8 路径；无则 `nil`（路径最长 4096） |
| `engine.track_info()` | `{path,title,artist,album,...codec,sample_rate,channels,bitrate,duration}` |
| `engine.tag_capability([path])` | `"none"` / `"readonly"` / `"readwrite"` |
| `engine.tag_read([path])` | `tags, err`；字段见下；缺省路径=当前曲 |
| `engine.tag_write(tags [, path])` | `ok, err`；部分字段合并写入；**勿每帧调用** |
| `engine.wasapi_exclusive()` | 独占**偏好** |
| `engine.wasapi_exclusive_active()` | 设备会话是否正处于独占 |
| `engine.window_rect()` | 主窗屏幕矩形 `x,y,w,h`（宽高 0..65535） |
| `engine.client_size()` | 逻辑客户区 `w,h`（含 `--board` 阴影边） |
| `engine.board()` | `main.window` 的 `--board`：`left, top, right, bottom`（逻辑像素） |
| `engine.content_rect()` | 去掉 board 后的实体区 `x, y, w, h`（与叠画裁剪一致） |
| `engine.theme_color()` | `r,g,b,a,fromTheme`：皮肤 `main.window` 的 `--theme-color`；未设则回退 accent；`fromTheme` 表示是否来自主题色 |
| `engine.is_dragging()` / `is_resizing()` | 主窗是否正在拖动 / 缩放 |
| `engine.set_paint_while_drag(bool)` | 保留接口（宿主始终定时刷新原生界面）；重特效请在 `on_frame` 里对 `is_dragging`/`is_resizing` 直接 `return` |
| `engine.draw_dot(x, y, size, alpha)` | **点**：白色软点 |
| `engine.draw_points(t)` | **点**：`t[i]={x,y,size,alpha[,r,g,b]}` |
| `engine.draw_line(x0,y0,x1,y1 [, thick=1, r,g,b, a])` | **线**：线段 |
| `engine.draw_rect(x,y,w,h [, thick=1, r,g,b, a])` | **线**：矩形描边 |
| `engine.fill_rect(x,y,w,h [, r,g,b, a])` | **面**：实心矩形 |
| `engine.fill_triangle(x1,y1,x2,y2,x3,y3 [,r,g,b,a])` | **面**：实心三角形 |
| `engine.fill_quad(x1..y4 [,r,g,b,a])` | **面**：实心四边形（顶点绕序，拆两三角形） |
| `engine.draw_circle(x, y, r, r8, g8, b8, a)` | **面**：实心软圆 |
| `engine.draw_sprite(name,x,y,size [,a [,r,g,b]])` | **精灵**：内置/particles 贴图（中心点，size=最长边） |
| `engine.draw_sprites(t)` | **精灵**：批量 `{name,x,y,size,a,r,g,b}` |
| `engine.list_sprites()` | 可用精灵名表 |

```lua
-- 播放时显示频谱，停止/暂停时隐藏；重复写入同一值不会重复触发布局与重绘。
function on_frame(dt, w, h)
  engine.set_role_visible("main.vis", engine.is_playing())
end
```

叠画会裁到 `main.window` 的 `--board` 以内，阴影/装饰边不落特效。`on_frame` 的 `w,h` 与 `role_rect`/`vis_rect` 仍是整窗坐标（含 board），不要整体偏移。粒子若只需在实体区生成，用 `engine.content_rect()`。

绘制、角色变换与动态 `visible` 仅在 `on_frame`（及同帧 `on_init`/`on_resize`）内可调用；播放/标签/窗口 API 在脚本已加载时可调用。
超时 / 错误会自动关闭特效。`tag_write` 写当前打开文件时会 Stop+Close 再重开（与标签对话框相同）。  
标签字段：`title/artist/album/album_artist/year/comment/genre/lyrics/track(0..9999)`；字符串字段最长 4096（`lyrics` 256KiB，`year` 32）。

节奏建议在 **Lua** 里做（包络、相对均值 onset、落速映射），宿主只提供能量/频带。`snow.lua` 即按此方式跟随播放。

## 示例

| 文件 | 效果 |
|------|------|
| `snow.lua` | 主窗口飘雪 |
| `rain.lua` | 主窗口下雨（斜雨丝，跟中高频） |
| `starfield.lua` | 星空闪烁 + 偶发流星 |
| `bassquake.lua` | 低音：transport 按钮抖动 + 缩放 |
| `spectrum.lua` | 接管 `main.vis`：经典分段 LED 频谱 + 峰值帽 |
| `spectrum_bars.lua` | 接管 `main.vis`：频谱柱粒子风格 |
| `spectrum_poly.lua` | 接管 `main.vis`：仿 C++ LED 频谱（`fill_quad`/`fill_triangle`） |
| `fog.lua` | 雾气 / 尘埃（大软点慢漂） |
| `fireflies.lua` | 萤火虫（游走闪烁） |
| `sakura.lua` | 樱花 / 落叶（慢飘摆动） |
| `sakura_fall.lua` | 樱花飘落（纯粉白花瓣；读主题色靠拢樱花粉；拖窗跳过绘制） |
| `autumn_leaves.lua` | 秋天落叶（读皮肤主题色染色；未设则秋色色板） |
| `matrix_rain.lua` | 矩阵雨（竖列赛博点串） |
| `solar_system.lua` | 太阳系（太阳 + 行星公转） |
| `embers.lua` | 灰烬亮点（底部升起、飘摆闪烁；无整团火焰） |
| `role_spin.lua` | 组件旋转 API 示例（封面转 + 播放键摆） |
| `fire.lua` | 火焰粒子（实验；观感有限） |
| `color_wash.lua` | 全屏叠色（低频暖 / 高频冷色温） |
| `color_pulse.lua` | 按节奏改窗体/组件颜色与透明度（API 示例） |
| `media_probe.lua` | 进度/音量/文件信息/标签/独占/窗口位置 API 示例 |
