# Aetheria 项目移交与编译指南 (React -> Flutter/Rust 重构版)

本项目已从原有的 `Tauri + React` 架构重构为 `Flutter + Rust` 架构，支持 **Windows / Linux 桌面端** 和 **Android 移动端**。

---

## 1. 项目核心架构 (Project Architecture)

项目采用 **Flutter 作为前端 UI 呈现**，**Rust 作为底层逻辑核心（数据库与文件解析）**，两者通过 `flutter_rust_bridge` (FRB v2) 以及 `cargokit` 进行原生双向通信。

### 目录结构说明
* `/lib` : Flutter 前端代码
  * `lib/main.dart` : 应用入口，初始化了 Rust 桥接接口、应用路由与主题提供者。
  * `lib/core/theme/` : UI 主题管理。包含 `UIThemeProvider`，内置 `dark`、`light`、`pink`、`pinkDark` 四套配色（`app_theme_config.dart`），规范见 `UI_CONTRACT.md`。
  * `lib/core/providers/` : 状态管理（`provider` + `ChangeNotifier`）
    * `LibraryProvider` : 歌曲、标签、歌单、筛选与导入，同步 Rust 端 SQLite 数据库状态。
    * `AudioPlayerProvider` : 播放器状态（播放、暂停、进度、音量、循环与随机模式、音频处理设置）。
    * `SyncProvider` : 局域网镜像同步。
  * `lib/features/` : 按功能划分的 UI（详见 `lib/features/README.md`）
    * `layout/` : 桌面端外壳 `main_layout.dart` 与移动端 `mobile_layout.dart`。
    * `library/` : 歌曲表格、标签筛选与管理、导入、设置。
    * `player/` : 播放条、详情抽屉、歌词面板、音源版本操作。
    * `sidebar/` : 桌面端侧边导航。
* `/rust` : 底层 Rust 代码
  * `rust/src/api/` : 暴露给 Dart 的 FRB v2 API 接口（`music.rs` 音乐库、`playback.rs` 播放控制），只做转发。
  * `rust/src/library/` : 音乐库业务逻辑（导入、歌曲/版本、标签、歌单、歌词、维护）。
  * `rust/src/database/` : 底层 SQLite 数据库初始化、版本迁移和 SQL 交互。
  * `rust/src/models/` : 对应数据库的歌曲 (`Song`)、播放列表 (`Playlist`) 数据模型。
* `/rust_builder` : `cargokit` 自动构建套件，负责在不同平台上交叉编译 Rust 代码为共享库。

---

## 2. 编译与打包指南 (Compilation Guide)

### Windows 编译
* **指令**：
  ```bash
  flutter build windows
  ```
* **输出路径**：项目目录下的 `build/windows/x64/runner/Release/aetheria.exe`。
* *注意*：运行打包好的 `aetheria.exe` 时，必须保证同级目录下的所有 `.dll` 依赖文件完整。

### Android 编译 (只限 arm64-v8a)
* **指令**：
  ```bash
  flutter build apk --target-platform android-arm64
  ```
* **输出路径**：项目目录下的 `build/app/outputs/flutter-apk/app-release.apk`。

### Linux 编译
* **指令**：`flutter build linux --release`
* **输出路径**：项目目录下的 `build/linux/x64/release/bundle/`；分发时保留整个目录。

---

## 3. 已知的重要编译修复 (Crucial Gradle Fixes)

在 Android 编译过程中，由于第三方插件（如 `file_picker`）内部写死了较低的编译 SDK 版本，会导致与高版本 Android 生命期插件冲突（引发 AAR Metadata 检查失败）。
为此，我们对 **`android/build.gradle.kts`** 注入了** Gradle 动态生命周期拦截器**：

```kotlin
subprojects {
    if (project.state.executed) {
        val android = project.extensions.findByName("android")
        if (android is com.android.build.gradle.BaseExtension) {
            android.compileSdkVersion(36)
        }
    } else {
        project.afterEvaluate {
            val android = project.extensions.findByName("android")
            if (android is com.android.build.gradle.BaseExtension) {
                android.compileSdkVersion(36)
            }
        }
    }
}
```
* **作用**：不论插件是处于已评估还是未评估阶段，都会强制将 `compileSdkVersion` 提升至 36。**切勿随意还原此段逻辑，否则会导致 Android 编译立即崩溃。**

---

## 4. 后续 UI 调整与 Bug 修复注意事项

1. **主题变量统一**：UI 组件通过 `context.tokens` 获取 `AppThemeConfig` 的颜色（如 `bgApp`、`textPrimary`）；主题状态由 `provider` 管理，规范见 `lib/core/theme/UI_CONTRACT.md`。
2. **音频状态联动**：如果遇到播放进度条、音量或播放状态不一致的 bug，应优先排查 `lib/core/providers/audio_player_provider.dart` 的状态监听逻辑。
3. **新增 Rust 接口**：如果修改了 `rust/src/api/` 下的 Rust 函数，请务必在根目录运行 `flutter_rust_bridge_codegen` 重新生成 Dart 桥接代码。

## 5. 重构验收（2026-11-11）

保留库模块、状态层、UI 拆分及主题改动，并补修以下边界：

* 播放器停止和销毁排在尚未完成的开流之后，避免同步替换文件时音频流重新出现。
* Dart 播放、封面和 Android 导出与 Rust 共用相同的文件名约束：只取末段，拒绝盘符相对路径和 NTFS 数据流名称；导出文件名兼容两种平台的分隔符。
* 并发导入在 SQLite 写事务内再次检查 MD5，失败时回滚记录并清理音频与歌词副本。

验证：`flutter analyze` 无问题；`flutter test` 137 项通过，截图入口默认跳过，单独启用后 24 项通过并复查截图；`cargo test` 45 项通过、1 项声卡测试忽略。Linux 调试构建与 Android arm64 API 26 的 `cargo ndk check` 通过。Windows 构建、Android 整包及真实设备的播放/交互尚未验证。
