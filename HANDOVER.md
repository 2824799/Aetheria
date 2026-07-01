# Aetheria 项目移交与编译指南 (React -> Flutter/Rust 重构版)

本项目已成功从原有的 `Tauri + React` 架构重构为 `Flutter + Rust` 架构，支持 **Windows 桌面端** 和 **Android 移动端 (arm64-v8a)**。

---

## 1. 项目核心架构 (Project Architecture)

项目采用 **Flutter 作为前端 UI 呈现**，**Rust 作为底层逻辑核心（数据库与文件解析）**，两者通过 `flutter_rust_bridge` (FRB v2) 以及 `cargokit` 进行原生双向通信。

### 目录结构说明
* `/lib` : Flutter 前端代码
  * `lib/main.dart` : 应用入口，初始化了 Rust 桥接接口、应用路由与主题提供者。
  * `lib/core/theme/` : UI 主题管理。包含 `UIThemeProvider`，内置 `Dark`、`Light`、`Pink` 三套与原 React 版本 1:1 对应的颜色变量及毛玻璃特效控制。
  * `lib/features/library/` : 音乐库核心业务模块
    * `ui/` : 前端 UI 组件（`main_layout.dart`、`sidebar.dart`、`tag_filter.dart`、`song_table.dart`、`play_bar.dart`、`detail_pane.dart` 等）。
    * `providers/` : 状态管理（Riverpod）
      * `LibraryProvider` : 管理扫描音乐目录、导入文件、同步 Rust 端 SQLite 数据库状态。
      * `AudioPlayerProvider` : 管理音频播放器状态（播放、暂停、进度条拖拽、音量、循环与随机模式）。
* `/rust` : 底层 Rust 代码
  * `rust/src/api/` : 暴露给 Dart 的 FRB v2 API 接口（如音乐导入、数据库查询等）。
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
* **输出路径**：`D:\python\app\build\windows\x64\runner\Release\aetheria.exe`
* *注意*：运行打包好的 `aetheria.exe` 时，必须保证同级目录下的所有 `.dll` 依赖文件完整。

### Android 编译 (只限 arm64-v8a)
* **指令**：
  ```bash
  flutter build apk --target-platform android-arm64
  ```
* **输出路径**：`D:\python\app\build\app\outputs\flutter-apk\app-release.apk`

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

1. **主题变量统一**：所有的 UI 组件应当通过 `ref.watch(uiThemeProvider)` 获取当前主题的 CSS 对应变量（如 `bgApp`、`textNormal` 等），严禁在组件内硬编码颜色值。
2. **音频状态联动**：如果遇到播放进度条、音量或播放状态不一致的 bug，应优先排查 `lib/features/library/providers/audio_player_provider.dart` 的状态监听逻辑。
3. **新增 Rust 接口**：如果修改了 `rust/src/api/` 下的 Rust 函数，请务必在根目录运行 `flutter_rust_bridge_codegen` 重新生成 Dart 桥接代码。
