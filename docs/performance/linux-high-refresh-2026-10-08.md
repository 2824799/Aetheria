# Linux 60 → 165Hz 验证 · 2026-10-08

> 后续屏幕验证发现该版本实际呈现黑帧：EGL 默认绘制目标为 GL_NONE。下述帧率只能证明提交/呈现回调频率，不能作为有效画面达到 165fps 的证据。原有“已验证可用”的结论撤回；请参见[修复及重新验证记录](linux-rendering-fix-2026-10-08.md)。

首次测量在本机 KDE Wayland、NVIDIA RTX 4060 Laptop、165Hz 显示器上记录了 Profile **165.00fps**、Release **163.89fps** 的 `wp_presentation.presented` 通知。后续像素验证证实这些提交包含黑帧。本文件保留为排查记录，不作为有效画面的高刷新率证据。

## 实现

针对当前 Flutter engine `5f77625673248ee5846fbcaf5d3e1a3878386fd7` 构建完整 Linux GTK 引擎。主窗口的 Flutter 内容由 raster 线程通过 EGL 直接提交到 Wayland 子表面；GTK 继续处理窗口和输入。每帧不再请求 GTK/Cairo 整窗重绘。子表面的 frame callback 在 EGL swap 前注册，并用于驱动 Flutter vsync；无 layer 的空帧会清除旧内容。

窗口隐藏时销毁 EGL/Wayland 子表面，顶层完成重新映射后再创建；修复了最初版本中恢复后不再呈现的问题。新引擎通过项目构建配置打包，版本与 SDK 校验一致。

## 实际呈现

测试入口为 `integration_test/high_refresh_render_test.dart`，持续移动大矩形并重绘背景，先预热 3 秒，再记录 10 秒。下表取其中连续 9 秒，保留长帧和间隔，屏幕报告 165.003Hz。Profile 与 Release 为两次独立测量。

| 指标 | Profile | Release |
| --- | ---: | ---: |
| 实际呈现帧率 | 165.004fps | 163.889fps |
| 呈现帧数 | 1,485 | 1,475 |
| 测量跨度 | 8.994s | 8.994s |
| 帧间隔 P50 | 6.061ms | 6.061ms |
| 帧间隔 P95 | 6.151ms | 6.158ms |
| 帧间隔 P99 | 6.202ms | 6.213ms |
| 最长帧间隔 | 6.260ms | 12.144ms |
| 超过 1.5 个刷新周期的间隔 | 0 | 10 |

Release 测量仍有约 0.7% 的长间隔，因此结果应描述为约 164–165fps。全程 trace 分别还有 17 / 1 次 discarded 通知，包含测量区间外的启动、预热与结束阶段；不能把它们当成上表采样段的丢帧数量。

对照此前的 [UI 延迟记录](ui-input-latency-2026-10-07.md)，应用动画中位时间戳间隔为 16.667ms。本轮也验证了同一 Release 引擎在 X11 上可启动并完成测试；X11 仍使用原有 GTK 路径，不在此次 165Hz 提升范围内。

## 实际 UI 和生命周期

5000 首合成歌曲的 Profile 测试通过，详情抽屉动画时间戳间隔中位数 **6.251ms**。拖选平均构建 **0.069ms**、平均栅格化 **1.058ms**；抽屉平均构建 **0.226ms**、平均栅格化 **1.451ms**。这些耗时来自 Flutter，不能替代上表的物理呈现数据，也不能据此保证真实封面解码、音频/DSP、同步等全部负载都达到 165fps。

原生测试覆盖调整尺寸、最大化、还原、两次隐藏/显示及销毁。隐藏期间没有继续呈现，恢复后第一秒分别收到 160 / 160 帧。测试器退出时仍记录了 GTK 信号断开和 implicit-view removal 警告，旧 GTK 路径对照同样复现，两个进程均正常退出。多屏混合刷新率、VRR 和其他 GPU 驱动尚未验证。

78 项 Flutter 测试通过，`flutter analyze --no-pub` 无问题；Profile / Release 动画测试和原生生命周期测试通过。最终 Release bundle 已用 `lib/main.dart` 重新构建。

## 数据与复现

- [全部统计及 UI 原始报告](linux-high-refresh-2026-10-08.json)
- [Profile 原始 presentation trace](linux-high-refresh-profile-2026-10-08.csv.gz)
- [Release 原始 presentation trace](linux-high-refresh-release-2026-10-08.csv.gz)
- [构建、测量和回归命令](../../linux/engine/README.md)

`scripts/analyze_presentation.py` 会在反馈不足、测量不完整、时间戳不递增时失败；`--min-refresh-ratio 0.97` 校验实际呈现达到显示器刷新率的 97%。原始 trace 使用追加模式，每轮测量需先清空文件。
