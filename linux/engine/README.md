# Linux 高刷新率引擎

此补丁针对 Flutter engine `5f77625673248ee5846fbcaf5d3e1a3878386fd7`（本项目当前的 Flutter 3.47.0）。构建完整的 `libflutter_linux_gtk.so`，保留 Flutter 原有插件、窗口、输入、辅助功能和 Dart FFI 接口。自定义产物仅作用于本项目的 bundle。

Wayland 主窗口通过独立、desynchronized 的 `wl_subsurface` 和 EGL window surface 提交内容。Flutter raster 线程在原有 GL context 中将合成帧 blit 到窗口并 swap，避开每帧 GTK/Cairo 整窗重绘；GTK 继续负责窗口装饰、输入和悬浮歌词。`wl_surface.frame` 回调在 swap 前注册，驱动 `FlutterEngineOnVsync`；屏幕信息只用于预测下一帧预算。启动使用一次 bootstrap，合成器停止回调时使用有界超时，结束引擎前取消待处理回调。

Flutter 的 GL context 最初以 surfaceless 模式使用，默认 framebuffer 的绘制目标可能为 `GL_NONE`。切换 EGL surface 本身不会恢复这个状态；直接 blit 前必须显式选择 `GL_BACK`，完成后恢复原状态。否则会成功 swap 空帧，帧率统计正常但窗口全黑。构建脚本同时启用 Skia 和 Flutter 的 Fontconfig 支持，确保中文等系统字体可以回退。

隐藏时释放子表面，恢复时等 GTK 顶层窗口完成 map 后重新创建；缩放/尺寸变化更新 buffer scale 和位置。没有 Flutter layer 的帧会清除之前的内容。GL 和 Wayland 对象的销毁与 raster 提交互斥，未结束的 presentation feedback 会一并释放。

X11、软件渲染及无法创建 EGL surface 的设备继续使用 GTK renderer。设置 `AETHERIA_DIRECT_WAYLAND=0` 可在同一构建中对照旧路径。当前验证范围为单主窗口、NVIDIA RTX 4060 Laptop、KDE Wayland、165Hz；混合刷新率多屏、VRR 与其他驱动尚未实测。

## 构建

需要准备好对应 revision 的 Flutter engine checkout 及其依赖，按 Flutter 的 engine 构建说明完成 `gclient sync`，并使 depot_tools、引擎匹配的 Clang/LLD、Ninja 和 `wayland-scanner` 可用。新增依赖是 Wayland client/EGL 开发库。Flutter sysroot 中的裁剪版共享库需要兼容的 LLVM linker；不要使用 GNU BFD 替代 LLD。

构建脚本会对 checkout 中的 GTK host 应用固定版本补丁；遇到其他本地修改会停止。已有 GN 输出目录可复用，`--out-dir` 可以指定已配置的目录。

```bash
python3 scripts/build_linux_engine.py --flutter-source /path/to/flutter --mode release
AETHERIA_LINUX_ENGINE_DIR="$PWD/build/linux_engine" \
  flutter build linux --release --target=lib/main.dart --no-pub
```

后续构建也需传入 `AETHERIA_LINUX_ENGINE_DIR`。CMake 会验证自定义引擎与 Flutter SDK revision 一致，然后把引擎和许可证随应用打包。Profile 使用同样的流程，把 `--mode` 和 `--release` 换成 `profile` / `--profile`。默认 Flutter SDK 的缓存不需要替换。

## 测量

`AETHERIA_PRESENTATION_TRACE` 指定 CSV 输出文件，记录合成器的 `wp_presentation.presented` 和 `discarded`。文件使用追加模式，开始一轮测量前应清空。只有存在真实 presentation feedback 时，分析脚本才会计算实际 FPS。

```bash
: > build/presentations.csv
AETHERIA_LINUX_ENGINE_DIR="$PWD/build/linux_engine" \
AETHERIA_PRESENTATION_TRACE="$PWD/build/presentations.csv" GDK_BACKEND=wayland \
  flutter drive -d linux --profile --no-pub \
    --driver=test_driver/ui_performance_driver.dart \
    --target=integration_test/high_refresh_render_test.dart
python3 scripts/analyze_presentation.py build/presentations.csv --min-refresh-ratio 0.97
```

测试先预热 3 秒，然后保持动画 10 秒。分析器取预热后的 9 秒完整区间，保留所有长帧间隔，检查实际呈现帧率至少为报告刷新率的 97%。Flutter 的 wall FPS、raster 耗时另存于 `build/ui_performance/ui_performance.json`，不替代呈现统计。可通过 `integration_test/ui_latency_test.dart` 测量 5000 首歌曲下的拖选和详情抽屉。

在仍使用上述动画测试入口的 Profile bundle 上执行 `bash scripts/test_linux_high_refresh.sh`，会测试缩放、最大化、两次隐藏恢复以及销毁，并检查恢复后确有新帧呈现。传入 bundle 的绝对路径也可测试 Release。测试使用 `AETHERIA_FRAME_CAPTURE` 导出前几帧的 Flutter 和 EGL window 像素，并通过 Pillow 逐字节验证非空画面，防止空帧通过帧率检查。像素读回仅在显式设置该环境变量时执行，性能测量时应移除它。该生命周期分析目前针对使用 CLOCK_MONOTONIC feedback 的 KWin。测试结束后，应使用 `--target=lib/main.dart` 重新构建正式应用，并实际截取窗口检查文字、布局与内容。

上游仍有独立的帧调度工作：[Flutter #191245](https://github.com/flutter/flutter/issues/191245)。最新结果见 [黑屏修复与可见画面验证](../../docs/performance/linux-rendering-fix-2026-10-08.md)。早期仅按呈现回调计数的记录已撤回有效帧率结论。
