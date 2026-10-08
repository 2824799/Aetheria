# 点击、拖选与 Linux 帧调度复查 · 2026-10-07

本轮先对提交 c93d145 增加可失败的复现测试，再修改应用代码，并在同机原生 Wayland / Profile 模式下比较旧版与新版。屏幕为 2560×1440、165Hz，桌面缩放 1.25，Flutter 3.47.0。旧版使用独立临时工作区，同一测试入口、同一 fullyLive 帧策略；测试包含 5000 首合成歌曲、120 次鼠标拖选更新和 10 次详情抽屉开关。

## 确认与修复

- 拖选的每个 PointerMove 都调用歌曲表 setState，重建表头、列表及所有已挂载行。改为独立 CustomPainter，通过 repaint listenable 绘制最新矩形；只在选中行范围改变时更新行背景，静态单元格复用。
- 播放及当前行状态由整个表订阅，改为每行只订阅自身播放、当前行和运行状态。列宽调整只在拖动结束/取消时保存，避免每个移动事件都写整套偏好设置。
- 快速按下/松开在同一帧时，旧控件会丢掉按压反馈；现在业务回调仍立即执行，按压视觉至少显示一帧。按下立即达到反馈状态，释放使用 80ms 动画；悬停和高亮直接绘制，不叠加 150ms 的颜色过渡。该机制统一覆盖普通按钮、图标、标签、选项、开关、菜单、列表项和页签。
- 歌曲行播放按钮外层曾有 320ms 的整行点击屏蔽，紧接着点歌曲行可能无反应。删除时间屏蔽，嵌套按钮由手势竞争处理；拖选只屏蔽本次拖动的行点击，下一次按下立即恢复。
- 行背景的 3px 边框吃掉列宽，使窄窗口出现右侧溢出。边框改为前景绘制，行与表头列宽一致。
- 桌面标签折叠的每次滚动会重建整个 MainContent；改为局部 ValueNotifier，歌曲表保留原组件。
- 主布局打开抽屉时重复创建 MainContent；现在复用同一组件。详情内容首次打开后保留状态，关闭时隐藏、禁止命中和停用 ticker，不再每次销毁和加载封面。动画的面板与遮罩独立合成，不再将其同时包进整页 RepaintBoundary。
- 详情页只订阅使用的音频状态；隐藏的滚动歌词停止响应位置通知。输入框清空和元数据编辑入口使用公共点击控件；仅有右键回调的列表项也能交互。

## 旧版 / 新版实测

| 指标 | 旧版 | 新版 |
| --- | ---: | ---: |
| 拖选导致 displaySongs 再次读取 | 121 | 0 |
| 拖选导致歌词标记/单元格检查 | 9,680 | 0 |
| 拖选平均帧构建耗时 | 1.783ms | 0.174ms |
| 拖选最大帧构建耗时 | 5.675ms | 0.541ms |
| 拖选平均栅格化耗时 | 2.312ms | 2.033ms |
| 拖选最大栅格化耗时 | 7.621ms | 4.112ms |
| 抽屉平均帧构建耗时 | 0.521ms | 0.407ms |
| 抽屉最大帧构建耗时 | 16.379ms | 14.731ms |
| 抽屉平均栅格化耗时 | 2.424ms | 2.499ms |
| 实际帧时间戳间隔中位数 | 16,667µs | 16,667µs |
| Flutter 报告屏幕刷新率 | 164.898Hz | 164.898Hz |

拖选平均构建成本下降约 90%，但不能把构建成本的下降等同于整体 FPS 提升。抽屉仍有首次构建峰值，栅格化均值没有改善。框架的默认 16.67ms 超预算统计也不能用来证明满足 165Hz 的 6.06ms 预算。

统计来自合成歌曲和测试音频 Provider，不含真实音频/DSP、真实封面首次解码、网络同步及完整输入到屏幕的呈现延迟；不能据此宣称所有实际负载都已消除卡顿。原生 integration_test 插件有未检测到提示，但 Flutter Driver 通过并写出了统计回调。

原始比较结果保存在 [ui-input-latency-2026-10-07.json](ui-input-latency-2026-10-07.json)。

## 尚未修复：Linux 165Hz 的帧调度

fullyLive 下抽屉采样得到约 348 个帧间隔，中位数仍是 16.667ms，与当前 Flutter Linux GTK embedder 的实现吻合：初始化 FlutterProjectArgs 时没有提供 vsync_callback，fallback 调度按固定 1/60 秒触发。屏幕刷新率信息被报告为约 165Hz，并不代表应用实际按该频率生成帧。

这条限制没有通过修改按钮动画或拖选代码解除。需要在 Flutter Linux embedder 中接入 GTK/GDK 原生 frame clock 并提供引擎 vsync 回调，再独立验证多显示器、不同刷新率、窗口隐藏/最小化及 Wayland/X11。

源码依据（与本机 Flutter engine revision 5f77625673 对应）：

- [Linux fl_engine.cc](https://github.com/flutter/flutter/blob/5f77625673/engine/src/flutter/shell/platform/linux/fl_engine.cc)：FlutterProjectArgs 初始化。
- [VsyncWaiterFallback](https://github.com/flutter/flutter/blob/5f77625673/engine/src/flutter/shell/common/vsync_waiter_fallback.cc)：固定 60Hz 的帧间隔。
- [VsyncWaiterEmbedder](https://github.com/flutter/flutter/blob/5f77625673/engine/src/flutter/shell/platform/embedder/vsync_waiter_embedder.cc)：原生 vsync 回调合同。

## 验证与复测

新增测试覆盖：快速点击下一帧可见反馈及立即激活，七类公共控件，键盘激活、禁用状态、嵌套开关、取消拖动、菜单首击、清空搜索；拖选下一帧像素变化及松手清除、零整表重建、Ctrl 累加/反向拖选/取消、歌曲行播放后紧接着打开详情；抽屉连续开关后移除可点击遮罩且只请求一次封面。

完整 Flutter 测试 78 项通过；分析无问题。Linux Profile 比较与 Release 普通应用构建通过。性能测试产物使用专门测试入口，不能作为正式应用安装。

    flutter test --no-pub
    flutter analyze --no-pub
    flutter drive -d linux --profile --driver=test_driver/ui_performance_driver.dart --target=integration_test/ui_latency_test.dart
    flutter build linux --release --target=lib/main.dart --no-pub
