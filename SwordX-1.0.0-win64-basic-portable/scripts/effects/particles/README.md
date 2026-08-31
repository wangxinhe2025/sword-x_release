# 内置 / 可替换粒子贴图

供 Lua `engine.draw_sprite` / `draw_sprites` 使用。

## 内置名（引擎内也有程序化回退）

| stem | 用途 |
|------|------|
| `flame1` | 主火舌（较高） |
| `flame2` | 中火舌 |
| `flame3` | 细火舌 |
| `ember1` / `ember2` | 余烬圆点 |
| `spark1` | 高亮火星 |

同名 `*.png` 放本目录会**覆盖**内置位图；也可新增其它 stem（仅字母数字/下划线，勿以 `_` 开头）。

建议尺寸：最长边 12–48 px，透明 PNG。

重新生成内置图：`python _gen_flames.py`
