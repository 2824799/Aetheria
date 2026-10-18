# 滚轮短惯性、输入延迟与独立 UI 线程 · 2026-10-17

本轮为鼠标滚轮增加约 90ms 的平滑收尾，并将 Flutter UI 与 GTK 平台线程分开。Release 实际呈现中，滚轮约 **164.5fps**，抽屉活动约 **163–165fps**；600 首歌曲连续跨表拖动滚动条约 **99.4fps**，仍未达到 165fps。测试开始于 10 月 17 日，正式桌面版验证与更新于 10 月 18 日完成。

## 测量条件

- KDE Wayland、NVIDIA RTX 4060 Laptop、165.003Hz；2560×1440 物理视图，DPR=2。
- 备份真实曲库的 516 首歌曲并补齐到 600 行，保留中文、日文、标签等真实数据；不写原始数据库。正式界面截图验证时加载副本中的 516 首原始歌曲。
- 使用真实 MainLayout、SongTable 和 DetailPane；TestAudio 模拟播放时钟，没有真实音频/DSP、网络同步负载。
- 连续六趟拖动真实滚动条，包含首次扫表；滚轮、完整抽屉开关、中途反向单独计时。另有八次相隔 140ms 的大幅拖条跳动，测量隔离输入延迟。
- Flutter FrameTiming 记录构建、raster、总跨度和 vsync 等待；Wayland presentation feedback 记录实际呈现。抽屉只统计动画活动区间，不把点击间等待计入帧率。
- 对比使用同一已修复 GL_BACK 和 Fontconfig 的引擎版本。每组均为一次完整有效 Release 测试，保留所有长帧；不是跨机器或持续播放负载的保证。

## 与本日上一轮 Release 对比

| 指标 | 上一轮 | 本轮 |
| --- | ---: | ---: |
| 连续跨表拖条，实际平均呈现 | 79.98fps | 99.44fps |
| 首趟扫表 | 51.3fps | 98.4fps |
| 拖条构建 P50 / P95 | 2.47 / 16.84ms | 2.29 / 6.63ms |
| 拖条最大构建耗时 | 30.73ms | 10.82ms |
| 拖条最大实际呈现间隔 | 39.75ms | 21.57ms |
| 滚轮实际平均呈现 | 108.21fps | 164.49fps |
| 完整抽屉打开 / 关闭 | 130.60 / 133.12fps | 164.36 / 164.46fps |
| 中途反向打开 / 关闭 | 139.07 / 140.72fps | 163.11 / 165.25fps |

165Hz 的单帧预算约 6.06ms。拖条最大构建 10.82ms，FrameTiming 总跨度最大 13.98ms；实际呈现最大间隔 21.57ms，仍足以感到顿卡。滚轮最大构建 3.13ms、总跨度 5.02ms，仍有一次约 11.98ms 的呈现间隔。完整抽屉测试包含首次构建，峰值仍为 20.44ms；动画平均接近刷新率不代表所有峰值消失。有限动画窗口里略高于 165 的估算值是计时边界差异。

## 阻塞定位与线程对照

此前所用引擎策略将 Dart UI 工作与 GTK 平台事件放在同一线程，UI 排版和帧调度会互相延后。现在通过 `fl_dart_project_set_ui_thread_policy(..., FL_UI_THREAD_POLICY_RUN_ON_SEPARATE_THREAD)` 使用独立 UI 线程。

为区分线程策略与文字预处理的收益，对同一个最终 Release 二进制、相同曲库再设置 `AETHERIA_UI_THREAD=platform` 运行控制组：

| 指标 | 合并 UI / 平台线程 | 默认独立 UI 线程 |
| --- | ---: | ---: |
| 滚轮实际呈现 | 100.81fps | 164.49fps |
| 滚轮 vsync overhead P95 | 3.12ms | 0.15ms |
| 完整抽屉打开 / 关闭 | 116.35 / 123.61fps | 164.36 / 164.46fps |
| 连续拖条实际呈现 | 89.69fps | 99.44fps |
| 拖条最大构建耗时 | 20.02ms | 10.82ms |
| 拖条 vsync overhead P95 | 3.21ms | 0.39ms |

拖条原生提交的锁等待 P95 约 0.001ms，swap 前 GL 调用段 P95 约 0.111ms，EGL swap 调用 P95 约 0.106ms。这些是 CPU 侧调用时长，不能当作完整 GPU 执行计时；但结合线程控制组，主要瓶颈指向 UI 排版和调度，未观察到长锁等待或长 swap 阻塞。CPU/GPU 整体占用低也不能说明每帧都能赶上期限，串行工作和等待会使刷新机会错过。

## 输入到实际呈现

拖动事件带序号和时间戳，持久帧回调记录该帧已处理的最新序号。通过 raster 时间窗口关联原生提交序号，再关联 `presented_frame`，匹配到真实呈现。连续测试事件实际发送速率约 173Hz。

| 场景 | 样本 | P50 | P95 | 最大 |
| --- | ---: | ---: | ---: | ---: |
| 连续拖条，合并线程控制组 | 424 | 19.41ms | 25.80ms | 33.97ms |
| 连续拖条，本轮默认 | 413 | 17.36ms | 23.73ms | 27.62ms |
| 八次隔离大幅跳动，本轮默认 | 8 | 18.02ms | 20.49ms | 21.81ms |

这是**测试注入 Dart pointer 事件到对应画面实际呈现**的延迟，不包括物理鼠标、GTK 收到事件之前的时间或 LCD 响应。隔离跳动只有八个样本，不能用其 P95 代替长期尾延迟。连续拖动时，旧位置画面呈现之际已处理的新输入数量中位数仍为 2、最多 5；用户所说的追鼠标感还没有彻底消除。当前提交到呈现的延迟 P50 为 9.98ms、P95 为 15.99ms，后续仍需压缩这段与文字布局峰值。

早期 Profile 输入基线最长约 55.51ms，构建最大 41.24ms，另存原始数据；它与本轮 Release 模式不同，不用于计算严格的性能提升比例。

## 实现与验证

- 鼠标滚轮使用 90ms ease-out，连续输入保留总滚动距离，最多两行进入缓动尾段；反向时立即丢弃旧方向余量，按住滚动条或触摸拖动立即接管。触摸板和减少动态效果设置保留直接响应。
- 标题、歌手文字在空闲时分片预排版，复用实际行的样式和尺寸；交互后暂停 200ms。每片最多四个标签，在标签之间检查约 0.75ms 预算，单次原生排版不能被中途抢占。缓存仍有 2048 项上限，字体改变会失效。
- 根据有无歌词标记区分标题宽度，避免重复预处理。拖条阶段仍有 511 次文字布局 miss；队列排空不代表每个单元格都已缓存。
- 104 项 Flutter 回归测试通过，包括滚轮收尾、反向、拖动取消、触摸板、减少动态效果、拖条一帧内位置更新、文字像素一致性、字体变化和缓存驱逐。模型在一帧内更新的单元测试不替代物理输入延迟测量。
- `flutter analyze --no-pub` 无问题。原生生命周期覆盖调整尺寸、最大化、两次隐藏恢复和销毁；八个非空 Flutter 源帧与 EGL back buffer 逐字节一致。
- 测试结束后重新构建 `lib/main.dart` 正式 Release，独立配置加载曲库副本，实际截图确认中文、日文与标签正常。日志确认 direct Wayland EGL，线程列表确认 UI 与 GTK 主线程分开。
- 正式 bundle 已原子更新到桌面启动器对应安装目录，保留旧版备份，并核对启动文件、Dart 应用库、自定义引擎三项 SHA256。当前仍在运行的旧程序需完全退出后从快捷方式重开。

## 原始数据与复现

生成数据仅保留本地，由 Git 忽略：统计为 `linux-scroll-input-2026-10-17.json`，三组原始 Flutter 报告为 `linux-scroll-input-raw-2026-10-17.json.gz`，呈现 trace 为 `linux-scroll-input-{release,merged-control,profile-before}-2026-10-17.csv.gz`。关键结果记录在本文，下面命令可重新生成测量数据。

准备可丢弃的曲库副本后运行。下面构建的是测试入口，测试后需重新构建正式入口：

```bash
AETHERIA_LINUX_ENGINE_DIR="$PWD/build/linux_engine" flutter build linux \
  --release --no-pub --target=integration_test/desktop_stress_test.dart \
  --dart-define=AETHERIA_BENCH_LIBRARY=/absolute/path/to/disposable-library-copy
python3 scripts/run_desktop_stress.py build/linux/x64/release/bundle \
  --output build/scroll-release
AETHERIA_UI_THREAD=platform python3 scripts/run_desktop_stress.py \
  build/linux/x64/release/bundle --output build/scroll-release-merged
python3 scripts/analyze_desktop_stress.py \
  build/scroll-release/report.json build/scroll-release/presentations.csv \
  --output build/scroll-release/summary.json
AETHERIA_LINUX_ENGINE_DIR="$PWD/build/linux_engine" flutter build linux \
  --release --no-pub --target=lib/main.dart
```

Runner 隔离测试配置、清空追加 trace，仅在测试通过且报告完整时成功；失败立即退出。性能测试关闭像素读回；生命周期像素验证与正式窗口截图分别执行。
