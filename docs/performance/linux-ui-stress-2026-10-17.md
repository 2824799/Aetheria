# 600 首歌曲列表与可打断抽屉 · 2026-10-17

本文保留本日第一轮结果；后续滚轮平滑、输入延迟和线程策略测量见[第二轮报告](linux-scroll-input-2026-10-17.md)。

本轮已改善反复拖动列表及抽屉的响应。正式 Release 测量中，连续拖动滚动条平均由 **46.3fps 提到 80.0fps**，重复扫过已布局的条目约 **89.6–94.4fps**。抽屉活动时段实际呈现约 **130.6–140.7fps**，并未稳定达到 165fps。首次浏览整表仍有明显的文字布局成本。

## 测试条件与方法

- KDE Wayland、RTX 4060 Laptop、165.003Hz，GTK scale=2。前后 Release 均为 2560×1440 物理视图、Flutter DPR=2。
- 从真实曲库的 SQLite 备份读取 516 首歌曲，复制条目补齐至 600 行，保留标题、标签、音源元数据及已有封面路径。测试不写入原始数据库。
- 使用真实 MainLayout、SongTable、DetailPane。TestAudio 模拟每 250ms 更新的播放时钟；没有真实音频/DSP、网络同步负载。
- 按住真实滚动条命中区域，连续六趟跨越整个列表，每趟 120 次鼠标移动；480 次滚轮事件；12 次完整抽屉开关；20 次中途反向操作。
- Flutter FrameTiming 测构建和 raster 耗时；Wayland presentation feedback 测实际呈现时间。抽屉按 AnimationStatus 活动窗口统计，相邻点击之间的等待不计入动画帧率。
- 基线为 e3bd8ac 的应用代码，前后使用同一份已修复 GL_BACK 和 Fontconfig 的自定义引擎。陈旧 Profile 引擎产生的早期数据已排除。

## Release 对比

| 场景 / 指标 | 修改前 | 修改后 |
| --- | ---: | ---: |
| 六趟全程拖动，实际平均呈现 | 46.32fps | 79.98fps |
| 第一趟首次扫过 | 55.3fps | 51.3fps |
| 其余五趟 | 36.1–52.3fps | 89.6–94.4fps |
| 拖动构建 P50 / P95 | 11.32 / 23.05ms | 2.47 / 16.84ms |
| 拖动呈现间隔 P50 / P95 | 21.81 / 33.82ms | 10.85 / 27.52ms |
| 滚轮实际平均呈现 | 74.68fps | 108.21fps |
| 滚轮构建 P95 | 7.40ms | 1.13ms |
| 完整抽屉打开 / 关闭，活动呈现 | 98.75 / 100.42fps | 130.60 / 133.12fps |
| 中途反向打开 / 关闭，活动呈现 | 120.91 / 126.73fps | 139.07 / 140.72fps |
| 关闭点击后约 28ms 的位移，中位值 | 1.67 逻辑 px | 156.02 逻辑 px |
| 鼠标回到拖动起点后的列表位置 | 全表 21.28% | 全表 0.0032% |

抽屉修改后的常见呈现间隔约 6.1ms，但 P95 约 12.1ms；不能用中位间隔倒数声称稳定 165fps。Profile 重复测量中，全程拖动约 69–78fps，抽屉不同活动阶段约 99–137fps，说明仍存在运行和呈现波动。上表是各一次相同 Release 条件的测量，不是跨机器保证。

第一趟首次扫过没有得到改善，约 51fps，仍需处理首次中文/日文文字布局。缓存的收益主要在随后反复拖动，没有消除冷布局成本。即使滚轮 CPU 构建已低于 6.06ms 预算，实际呈现仍约 108fps，后续需要继续分离输入到达、调度和提交节奏，不能仅凭构建耗时推断屏幕帧率。

## 实现与正确性

- 抽屉 controller 直接保存可见进度，每次从当前位置向目标运动，关闭使用向外快速移动的曲线。打开 240→180ms，完整关闭 168→126ms；剩余距离按当前进度缩短。关闭请求立即释放列表点击，允许点下一首反向打开。
- 表格只保留一条固定的垂直滚动条，排除表头和内部横向滚动通知；拖动期间不自动折叠标签区，避免轨道变化。修复 FittedBox / 横向溢出时的命中坐标。
- 上下预建行由各八行降为各两行；每行只查询一次歌词标记；没有缩放动作的歌曲行不创建 AnimatedScale。
- 普通标签直接用 Row，仅溢出时创建横向滚动组件，仍可查看长标签集。
- 表格拥有最多 2048 项的 TextPainter 布局缓存。键包含样式、宽度、缩放、方向和 locale；驱逐保留仍在使用的布局，字体变化会失效。文字选择、辅助间距覆盖和 fade 使用 Flutter 原有 Text 实现。
- LTR / RTL、clip / ellipsis 的四项像素逐字节对比通过；缓存驱逐、字体变化、宽度和样式变化通过；600 行真实 thumb 命中、轨道稳定和抽屉打断回归通过。100 项 Flutter 测试通过，analyze 无问题。

最终以 lib/main.dart 重新构建 Release，并在独立配置下加载曲库副本检查实际 KWin 窗口：中文、日文、标签和列表正常显示，日志确认 direct Wayland EGL。正式 bundle 已原子替换至桌面启动器对应的安装目录，并保留旧版备份；已运行的旧进程需完全退出后重开。

## 数据与复现

生成数据仅保留本地，由 Git 忽略：统计为 `linux-ui-stress-2026-10-17.json`，修改前后 Release trace 为 `linux-ui-stress-{before,after}-2026-10-17.csv.gz`。关键结果记录在本文，下面命令可重新生成测量数据。

准备曲库副本后构建测试入口，不能将这个测试 bundle 安装为正式应用：

```bash
AETHERIA_LINUX_ENGINE_DIR="$PWD/build/linux_engine" flutter build linux \
  --release --no-pub --target=integration_test/desktop_stress_test.dart \
  --dart-define=AETHERIA_BENCH_LIBRARY=/absolute/path/to/disposable-library-copy
python3 scripts/run_desktop_stress.py build/linux/x64/release/bundle \
  --output build/desktop_stress_release
python3 scripts/analyze_desktop_stress.py \
  build/desktop_stress_release/report.json \
  build/desktop_stress_release/presentations.csv \
  --output build/desktop_stress_release/summary.json
```

runner 为测试进程隔离 XDG 配置、清空追加式 trace，在测试结束后关闭它创建的进程。未提供曲库路径时使用 600 首合成条目。测试后正式应用须以 `--target=lib/main.dart` 重新构建；性能测试时关闭像素读回，正式界面另外做可见画面检查。
