# 鼠标滚轮速度衔接 · 2026-10-18

针对连续滚动时“一下快、一下慢”的反馈，本轮替换了滚轮运动模型。原来的每次输入都会重启 90ms ease-out，快滚时还会立即跳过超过 104px 的待滚距离。即使实际呈现接近 165fps，运动速度本身仍会形成脉冲。

现在整个滚轮过程使用同一个 ticker。新输入只更新目标，三次 Hermite 曲线从当前可见位置和当前速度接上，到目标时速度降至零；没有跨帧之间的位置跳跃。反向输入放弃旧方向剩余距离和速度，拖动、按住滚动条、程序跳转会直接取消收尾。停手后最长约 180ms 收尾，用来衔接较慢的滚轮间隔；触摸板和减少动态效果设置仍直接响应。

## 固定输入下的速度对比

用同一份 600 行 ListView、同样的输入距离和每 6ms 一次的采样，分别运行上一版已提交的 controller 与本轮 controller。预热至少 800ms 后，按每帧实际位移计算速度，避免只看平均帧率。

下表为速度的标准差除以平均速度，越低越平稳。这是固定时钟下的运动模型对比，不是浏览器实测。

| 滚轮输入间隔 | 上一版速度波动 | 本轮速度波动 |
| --- | ---: | ---: |
| 12ms | 35.70% | 0.004% |
| 36ms | 50.13% | 0.34% |
| 60ms | 64.10% | 1.18% |
| 90ms | 92.11% | 3.40% |
| 120ms | 120.73% | 8.08% |

120ms 慢滚时，上一版速度范围是平均速度的 0–3.71 倍，本轮为 0.845–1.090 倍。12ms 快滚时，上一版单次输入可让内容直接跳约 40.7px，本轮所有输入都保持当时可见位置不变，位移只在帧回调中发生。输入总距离保留，停稳后不漂移。

## 真实列表 Release 测量

KDE Wayland、RTX 4060 Laptop、165.003Hz，2560×1440 物理视图、DPR=2。使用真实曲库副本补齐至 600 行，真实 SongTable、标签和文字布局；测试音频时钟替代真实音频/DSP、同步负载。

在原有快速滚轮场景外，加入 30 / 60 / 90 / 120ms 四种固定间隔输入。记录每个输入前后的 offset、各 Flutter 帧的 offset，再通过原生提交序号与 presentation feedback 关联实际呈现位置。忽略前 800ms 的起步阶段，按相邻呈现的位置差与时间差计算实际画面速度。

| 请求输入间隔 | 实际输入间隔中位数 | 稳态实际呈现 | 呈现速度波动 | 最大构建耗时 |
| --- | ---: | ---: | ---: | ---: |
| 30ms | 32.01ms | 164.42fps | 14.04% | 3.31ms |
| 60ms | 62.03ms | 164.99fps | 8.47% | 1.02ms |
| 90ms | 92.04ms | 165.00fps | 7.95% | 1.02ms |
| 120ms | 122.04ms | 165.00fps | 9.47% | 0.88ms |

原有快速滚轮实际呈现 164.62fps，最大构建 2.84ms，最大呈现间隔 12.11ms。所有输入的即时位置跳跃均为 0。原生画面仍有调度抖动：30ms 场景的单帧速度范围约为均速的 0.51–1.96 倍，最长呈现间隔 12.12ms，不能把固定时钟测试中接近匀速的结果等同于每个屏幕帧都完全匀速。90 / 120ms 场景最长呈现间隔约为 6.37 / 6.31ms。

## 验证与复现

- 111 项 Flutter 回归测试通过，包括五种连续输入速度、即时位置与速度连续、总距离、变速、反向、两端边界、触摸接管、hold / jump 取消及减少动态效果。
- `flutter analyze --no-pub` 无问题，分析脚本通过 Python 编译检查。
- 完整原生 Release 压测通过，包括原有拖条、滚轮、完整抽屉和中途反向场景。
- 测试结束后重新构建 `lib/main.dart` 正式 Release，在独立配置下截图确认真实曲库、中文和日文正常显示，日志确认直接 Wayland EGL。桌面快捷方式对应程序已原子更新，保留上一版备份；启动文件、Dart 应用库和引擎的 SHA256 与正式 bundle 一致。完全退出旧进程后重新打开生效。

本机原始记录位于 `build/wheel-motion/`，由 Git 忽略：`comparison.json` 为固定输入对比，`native-release/report.json`、`presentations.csv` 和 `summary.json` 为真实呈现记录。

```bash
flutter test --no-pub test/song_table_wheel_test.dart
AETHERIA_LINUX_ENGINE_DIR="$PWD/build/linux_engine" flutter build linux \
  --release --no-pub --target=integration_test/desktop_stress_test.dart \
  --dart-define=AETHERIA_BENCH_LIBRARY=/absolute/path/to/disposable-library-copy
python3 scripts/run_desktop_stress.py build/linux/x64/release/bundle \
  --output build/wheel-motion/native-release --timeout 100
python3 scripts/analyze_desktop_stress.py \
  build/wheel-motion/native-release/report.json \
  build/wheel-motion/native-release/presentations.csv \
  --output build/wheel-motion/native-release/summary.json
AETHERIA_LINUX_ENGINE_DIR="$PWD/build/linux_engine" flutter build linux \
  --release --no-pub --target=lib/main.dart
```
