# Linux 低显存高刷定制引擎

此补丁针对 Flutter engine `371f77202a73e8dff57a8b3bff75bca55c090aee`（本项目当前的 Flutter 3.50.0）。构建完整的 `libflutter_linux_gtk.so`，保留 Flutter 原有插件、窗口、输入、辅助功能和 Dart FFI 接口。自定义产物仅作用于本项目的 bundle。

## 主要改动

1. **原生 Wayland 分数缩放（`wp_fractional_scale_v1` + `wp_viewporter`）**：
   - 在 `FlWaylandDisplay` / `FlSubsurface` 绑定 `wp_fractional_scale_manager_v1` 与 `wp_viewporter`。
   - 收到合成器的 `preferred_scale`（如 KDE Plasma 125% 缩放下为 `150/120 = 1.25`）后，将子表面设为 `buffer_scale = 1` + `wp_viewport_set_destination(logical_w, logical_h)`，按原生物理像素（如 `2560×1368` 而非 GTK3 整数 2× 的 `4096×2188`）分配缓冲并向 Flutter 报告真实 `double pixel_ratio`，同时同步缩放鼠标、滚轮和触摸坐标。
   - 不支持该协议的合成器自动回退至 GTK3 整数缩放。
2. **直出单层零中间 FBO + 双向 GPU Fence**：
   - 单图层 OpenGL backing store 帧不再分配 `FlViewRendererSubsurface` 的中间全屏 `FlFramebuffer`，直接将其纹理交由 `FlSubsurfaceEGL` 渲染至无深度模板的 `wl_egl_window` 交换链，并在呈现前后用 `FlGLFence` 做 GPU 侧双向同步。
   - 空图层帧直接清屏 FBO 0，同样不分配中间 FBO。
3. **修复 Flutter 3.50.0 在 NVIDIA 上的 1/4 裁切回归**：
   - 修正 `FlCompositorOpenGL::composite_layer` 的 NDC 偏移与浮点比例计算（适配 `[-1, 1]` 顶点缓冲），防止在禁用 `glBlitFramebuffer` 的 NVIDIA 驱动上走着色器路径时画面被偏移裁切到左下角 1/4。
4. **165Hz 直出 Wayland 呈现与生命周期加固**：
   - 保留 `AetheriaVsync`、`wl_subsurface_set_desync`、`wl_surface.frame` 回调驱动及 `wp_presentation` 诊断追踪（`AETHERIA_PRESENTATION_TRACE`、`AETHERIA_FRAME_CAPTURE`）。
   - 补充 `unmap` 释放子表面与顶层窗口 `map` 后重建，确保隐藏/恢复后持续出帧。
   - 设置 `AETHERIA_DIRECT_WAYLAND=0` 可回退至同步 subsurface 路径进行对照；设置 `AETHERIA_LINUX_ENGINE_DIR=stock` 可在 CMake 中显式回退官方引擎。

## 构建

需要准备好对应 revision 的 Flutter engine checkout 及其依赖，按 Flutter 的 engine 构建说明完成 `gclient sync`，并使 `wayland-scanner`、`ninja`、`vpython3` 可用。构建脚本会对 checkout 中的 Linux host 应用固定版本补丁并启用 Skia/Flutter 的 Fontconfig 支持（确保中文等系统字体回退）：

```bash
python3 scripts/build_linux_engine.py --flutter-source /path/to/flutter --mode release
flutter build linux --release --target=lib/main.dart --no-pub
```

`linux/engine/use_custom_engine.cmake` 会在 `build/linux_engine/<mode>/libflutter_linux_gtk.so` 存在且 `engine.version` 与当前 Flutter SDK 一致时自动选用定制引擎（也可通过 `AETHERIA_LINUX_ENGINE_DIR` 显式指定目录，或传入 `stock` 禁用）。Profile 模式将 `--mode` 与 `--release` 替换为 `profile` / `--profile`。

## 测量与验证

- 高刷生命周期与像素逐字节校验：`bash scripts/test_linux_high_refresh.sh /path/to/bundle`
- 悬浮歌词 KWin 全屏置顶与穿透：`bash scripts/test_linux_desktop.sh --kwin-fullscreen`
- 呈现帧率分析：`python3 scripts/analyze_presentation.py build/presentations.csv --min-refresh-ratio 0.97`
