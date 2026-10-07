# Linux 窗口、启动缩放及桌面歌词排查

验证环境：KDE Plasma / KWin Wayland，2560×1440，系统缩放 125%。分别运行 GTK 的
X11（通过 XWayland）和原生 Wayland 后端。没有把这两项测试等同于 GNOME、所有窗口管理器、
多显示器热插拔或所有分数缩放组合都已实测。

## 问题和修复

| 问题 | 原因 | 修复 |
| --- | --- | --- |
| 关闭重开丢失窗口尺寸 | GTK runner 每次写死 1280×720，没有状态保存 | 保存正常窗口尺寸及最大化状态，使用 GTK 逻辑像素；事件写入防抖，销毁时立即落盘；恢复时限制在当前屏幕工作区内 |
| 快捷方式与双击缩放不一致 | 启动环境及程序副本不同；首次修复漏掉了桌面 `aetheria` 符号链接，它仍指向另一目录下的旧程序 | 程序统一优先原生 Wayland，回退 X11，并尊重显式 `GDK_BACKEND`；桌面可执行链接、desktop 文件和应用菜单统一到安装副本 |
| 歌词置顶、拖动或位置失效 | 普通 Wayland xdg-shell 窗口不支持应用指定全局坐标或强制置顶 | 支持 layer-shell 时创建原生图层窗口，用输出锚点和边距定位、OVERLAY/BOTTOM 切换层级；实现拖动与边缘缩放，释放时保存最终请求尺寸，避免异步 configure 回写旧尺寸。X11 保留窗口管理器拖动 |
| 全屏游戏盖住置顶歌词 | TOP 层高于普通窗口，但 KWin 的活动全屏窗口高于 TOP 层 | 保持置顶使用 OVERLAY 层，保持键盘模式 NONE 和原有输入穿透设置 |
| 无边框外仍有主题装饰 | 只禁用窗口管理器装饰，没有处理 GTK 主题的 CSD 边框、阴影和背景 | 为歌词窗口清除相应 GTK CSS 样式并保留透明绘制 |
| 初始锁定不穿透 | 输入区域在 realize 之前设置；GTK 后续分配尺寸会覆盖区域；代码只处理 X11 | 通过 GTK widget API 保存区域，在 realize 及 size-allocate 后应用；同时支持 X11 和 Wayland |
| 居中/右对齐歌词染色错位 | 按整个可用宽度计算进度；右对齐又额外移动了布局原点 | 按 Pango 实际字形墨迹范围计算进度，布局只对齐一次 |
| 半透明字边混色、颜色覆盖不连续 | 先画未播放文字，再在上面画已播放文字，同时重复画阴影 | 阴影绘制一次，使用硬分界渐变对同一字形掩膜着色一次；不再双重叠色和增加边缘 alpha |
| 改颜色不直观 | 两套重复预设、小色块、只能操作 RGB、输入错误静默变蓝、看不到 alpha | 保留一套较大色块；增加 HSV 色板、透明度、HEX 校验、明暗背景预览；实时预览不写设置，确认才保存，取消恢复原色 |
| 设置预览与实际效果不符 | 两行独立样例不展示播放进度，翻译行直接覆盖原颜色 alpha | 同一行展示进度染色，增加预览进度滑条；保留颜色自身 alpha 并应用整体透明度，提示暂停淡出造成的亮度变化 |

窗口尺寸保存在 `$XDG_CONFIG_HOME/aetheria/window-state.ini`，未设置 XDG_CONFIG_HOME 时使用
`~/.config/aetheria/window-state.ini`。正常尺寸和最大化标记分开保存，最大化尺寸不会覆盖正常尺寸。

## 实测结果

- `flutter analyze`：通过。
- `flutter test`：58 项通过，新增颜色解析、临时预览不落盘、HEX 校验、透明度确认和取消恢复测试。
- `flutter build linux --release`：通过。
- 原生像素测试：左/中/右对齐，中文、拉丁字符、重音、RTL、长句省略，1×/2×，半透明及阴影。
  100% 进度与单次纯色文字绘制逐像素相同；进度变化不增加 alpha、不制造空洞；短句在部分进度时确实显示两种颜色。
- 真实 GTK 窗口：在两种后端均保存 903×617，进程关闭重开后恢复；最大化再关闭重开，恢复最大化，
  取消最大化后仍为 903×617。
- 原生歌词：两种后端均创建 600×100 无装饰窗口，截图检查颜色与透明边界一致。
  X11 查询到初始锁定时输入矩形数量为 0，解锁后恢复非空输入区域。
  Wayland 协议日志确认锁定提交空 `wl_region`，解锁恢复默认 input region。
- Wayland 图层回归：真实 KWin 合成器上创建 layer surface；检查 OVERLAY/BOTTOM 层级切换、
  锁定拒绝拖动、移动边距、右下与左上边缘缩放、位置及尺寸回调、隐藏后重建。
  鼠标回归通过向生产事件处理器发送合成事件驱动，不等同于人工实际鼠标操作。
- 全屏遮挡回归：通过临时 KWin 脚本读取真实窗口叠放顺序及活动窗口。在普通窗口、活动全屏窗口、
  关闭再开启置顶、解锁、歌词隐藏后重建、退出全屏等情形下核对相对顺序；全程确认测试窗口保留
  键盘焦点。负向对照临时使用旧 TOP 层，实际复现全屏窗口盖住歌词，再恢复生产逻辑后歌词位于
  全屏窗口上方。测试对象是原生 Wayland GTK 全屏窗口，未逐一运行各款游戏。
- 实际 release 应用启动：未设置 `GDK_BACKEND`，直接运行 bundle 和桌面上实际的 `aetheria`
  链接都报告 `GdkWaylandDisplay / GTK scale=2 / 1280×720`；隔离测试设置启用歌词，
  两个应用进程均向 KWin 提交 `aetheria-lyrics` 原生 layer surface；全屏修复后的桌面入口复测确认 OVERLAY 层。
  桌面入口进程的 `/proc/<pid>/exe` 确认是 `~/.local/opt/aetheria/aetheria`。
  GTK 的整数 buffer scale 不等于桌面最终的 125% 合成缩放。

可复现：

```sh
# 只测试原生渲染，无需显示服务器。
scripts/test_linux_desktop.sh

# 需 GTK、Wayland、X11/Xext 开发库、wayland-scanner 及已构建的 Flutter Linux embedding。
# 测试使用临时 XDG_CONFIG_HOME，不改真实用户的窗口状态。
# 会短暂出现测试窗口；只运行当前可用的显示后端。
scripts/test_linux_desktop.sh --windows

# 当前 KDE/KWin Wayland 会话；额外需要 Python PyGObject/Gio。
# 短暂创建活动全屏测试窗口，临时 KWin 探针在测试退出时卸载。
scripts/test_linux_desktop.sh --kwin-fullscreen

AETHERIA_DESKTOP_DIAGNOSTICS=1 ./build/linux/x64/release/bundle/aetheria
GDK_BACKEND=x11 AETHERIA_DESKTOP_DIAGNOSTICS=1 ./build/linux/x64/release/bundle/aetheria
```

## 本机入口统一

实际旧进程来自 `~/桌面/aetheria` → `~/app/music/Aetheria/aetheria`，并没有强制 X11 的
环境变量；此前只修复 `.desktop` 文件不足以更新这个入口。现已修正这个符号链接。
桌面可执行链接、desktop 文件及应用菜单均指向 `~/.local/opt/aetheria/aetheria`。
安装包附带动态链接的 gtk-layer-shell 0.10.1、对应源码和许可证，不依赖本机额外安装该库。
项目 release 与安装可执行文件 SHA-256 一致。

首次备份：`~/.local/state/aetheria/backups/linux-ui-20261007-140727/`。
本次替换前安装、desktop 文件及旧符号链接目标记录：
`~/.local/state/aetheria/backups/wayland-20261007-143139/`。
正在运行的旧进程需要退出后重开才能使用更新版本。

没有更改系统分辨率、缩放比例或全局 GTK 设置。默认后端选择在程序内部完成，不依赖桌面文件的私有环境参数。
GTK 首帧诊断由 `AETHERIA_DESKTOP_DIAGNOSTICS` 显式开启。

## Wayland 的边界

在支持 `zwlr_layer_shell_v1` 的桌面（本机 KDE/KWin 已验证）使用原生 Wayland 图层窗口。
开启置顶使用 OVERLAY 层，覆盖活动全屏窗口；关闭后使用 BOTTOM 层，歌词位于普通应用窗口下方。锁定通过空输入区域
实现穿透，键盘交互设置为 NONE，歌词不抢键盘焦点。

不提供该协议的桌面仍使用普通 GTK 窗口，设置页明确提示置顶和固定位置受限，并给出
`GDK_BACKEND=x11` 兼容启动方式。未实测 GNOME、其他合成器、多显示器拖动/热插拔、
各款游戏、XWayland 游戏全屏及各种分数缩放组合，不宣称这些环境全部通过。

依赖源码固定在 gtk-layer-shell v0.10.1（支持本机 GTK 3.24.52），使用 CMake 从随仓库源码构建，
协议 XML 随源码提供。Linux 发布流水线补充 Wayland 开发库和 scanner 依赖。

参考：[gtk-layer-shell API](https://wmww.github.io/gtk-layer-shell/)、
[gtk-layer-shell 0.10.1](https://github.com/wmww/gtk-layer-shell/releases/tag/v0.10.1)、
[Pango 字形范围](https://docs.gtk.org/Pango/method.Layout.get_pixel_extents.html)。
