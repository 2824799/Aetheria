# Aetheria

Aetheria 是一个以 **Flutter + Rust** 为核心技术栈构建的本地音乐播放器与音乐库管理应用。它的目标不是简单地“打开一个音频文件播放”，而是把本地音乐文件托管、歌曲与多音源版本管理、歌词检索与绑定、桌面/安卓悬浮歌词、标签过滤、歌单整理、音频 DSP、局域网整库镜像同步等能力整合成一套可维护的个人音乐库系统。

当前代码重点面向：

- **Windows 桌面端**：完整桌面布局、Rust 原生音频输出、桌面悬浮歌词透明窗口。
- **Android 移动端**：移动端布局、播放通知栏、MediaSession、系统悬浮窗歌词、局域网同步辅助能力。

项目已经从早期方案演进为当前的 **Flutter UI + Provider 状态层 + Rust 数据/音频核心 + 平台原生桥接** 架构。Flutter 负责界面、交互和状态编排；Rust 负责 SQLite 数据库、音频文件导入、元数据解析、封面提取、歌词持久化、音频解码/播放/DSP；Android Kotlin 与 Windows C++ 补齐通知栏、悬浮窗、设备名、组播锁、窗口绘制等平台能力。

> 本 README 按当前仓库代码重新整理，优先以 `lib/`、`rust/`、`android/`、`windows/` 的真实实现为准，而不是旧文档中的历史描述。

## 目录

- [项目定位](#项目定位)
- [当前状态](#当前状态)
- [功能总览](#功能总览)
- [核心功能详解](#核心功能详解)
- [技术架构](#技术架构)
- [目录结构](#目录结构)
- [数据目录与数据库](#数据目录与数据库)
- [开发环境](#开发环境)
- [快速开始](#快速开始)
- [常用开发命令](#常用开发命令)
- [平台说明](#平台说明)
- [Flutter / Rust 桥接说明](#flutter--rust-桥接说明)
- [音频引擎说明](#音频引擎说明)
- [局域网同步协议说明](#局域网同步协议说明)
- [UI 设计系统与约束](#ui-设计系统与约束)
- [测试](#测试)
- [常见问题](#常见问题)
- [已知边界](#已知边界)
- [许可证](#许可证)

## 项目定位

Aetheria 面向下面这些场景：

- 你有很多散落在不同目录里的本地音乐文件，希望整理成一个统一托管的音乐库。
- 同一首歌有多个版本，例如不同码率、不同格式、现场版、修复版、伴奏版，希望在一首歌下集中管理。
- 你希望明确指定某首歌的默认播放版本，并且能随时切换。
- 你希望为歌曲绑定同步歌词、翻译歌词、罗马音歌词，必要时能绑定到具体音源版本。
- 你希望在 Windows 或 Android 上使用可自定义样式的悬浮歌词。
- 你有多台设备，希望在同一个局域网里把一台设备的音乐库镜像同步到另一台设备。
- 你希望播放器底层更可控，支持输出设备检测、音高调整、音量均衡、峰值保护、抖动和性能统计。

## 当前状态

| 模块 | 当前实现 |
| --- | --- |
| 桌面端 | Windows 是当前重点支持平台 |
| 移动端 | Android 是当前重点支持平台 |
| UI 框架 | Flutter |
| 状态管理 | `provider` / `ChangeNotifier` |
| 核心数据与音频 | Rust |
| Flutter / Rust 通信 | `flutter_rust_bridge` 2.12.0 |
| 数据库 | SQLite（`rusqlite` bundled） |
| 音频解码 / 元数据 | `symphonia`、`lofty` |
| 音频输出 | `cpal` |
| 音高处理 | 内置 resample，集成 Rubber Band LiveShifter |
| 歌词来源 | 本地、LRCLIB、网易云音乐、QQ 音乐、酷狗音乐 |
| 局域网同步 | UDP 发现 + HTTP 拉取 + 临时 token 授权 + 镜像覆盖 |
| 主题 | Dark、Light、Pink、Pink Dark |
| 主要构建目标 | Windows、Android |

## 功能总览

Aetheria 当前已经实现的主要功能包括：

- 音乐库初始化、切换托管目录、重置音乐库。
- 单文件、多文件、整文件夹导入。
- 文件夹导入前的音频元数据预览与勾选。
- 支持 `mp3`、`wav`、`flac`、`m4a`、`ogg`、`aac` 导入扫描。
- 音频文件 MD5 去重。
- 标题、歌手、专辑、时长、码率、采样率、位深、响度、文件大小等元数据读取。
- 内嵌封面提取与 `covers/` 缓存。
- 同名 `.lrc` 歌词文件复制与本地候选识别。
- 歌曲级歌词与音源版本级歌词。
- 多音源版本管理、默认版本切换、版本导出、版本删除。
- 歌曲彻底删除，包括数据库记录、托管音频、同名歌词、封面清理。
- 歌曲列表搜索、标签过滤、歌单过滤。
- Explorer 风格自然排序。
- 桌面歌曲表列宽调整、列顺序拖拽、布局持久化。
- 桌面多选、范围选择、框选、右键菜单。
- 移动端抽屉、搜索、标签过滤、长按菜单、迷你播放器、歌曲详情 Sheet。
- 标签创建、编辑、删除、颜色、分类、三态过滤。
- 歌单创建、重命名、删除、添加歌曲、移除歌曲、复制/剪切/粘贴式整理。
- 播放、暂停、上一首、下一首、进度拖动、音量调节。
- 列表循环、随机播放、单曲循环。
- 播放状态恢复，包括歌曲、版本、位置、队列、音量。
- Rust 原生音频输出设备状态展示。
- 音高调整、Rubber Band / resample 算法切换。
- 输出缓冲、输出延迟模式、峰值保护、整数输出抖动、音量均衡。
- 开发者模式下的 Rust 音频引擎调用树性能统计、JSON 复制和 Markdown 报告导出。
- 在线歌词检索、候选预览、保存、选择、删除、偏移调整。
- LRC / QRC / 逐字歌词片段解析。
- 滚动歌词高亮、翻译显示、滚动到某行后从该时间点播放。
- Windows 桌面悬浮歌词窗口。
- Android 系统悬浮窗歌词。
- 悬浮歌词样式、颜色、透明度、大小、位置、锁定、置顶、刷新帧率等设置。
- Android 通知栏播放控制与 MediaSession。
- Android 导出音频到系统 Downloads/Aetheria。
- Android 设备名读取、组播锁、悬浮窗权限、通知权限。
- 局域网设备发现、同步审批、临时授权 token、manifest 校验、MD5 校验、同步备份、失败回滚。

## 核心功能详解

### 1. 音乐库初始化与托管目录

Aetheria 使用一个“托管音乐库目录”作为应用数据根目录。首次启动时：

1. Flutter 初始化 `RustLib`。
2. 读取 `SharedPreferences` 中保存的 `aetheria-library-path`。
3. 如果存在已保存路径，则使用该路径初始化 Rust 侧库目录。
4. 如果不存在，则默认使用应用文档目录。
5. Rust 初始化目录结构和 SQLite 数据库。

托管目录中通常包含：

```text
<library_path>/
├─ database.db
├─ database.db-wal
├─ database.db-shm
├─ files/
├─ covers/
├─ sync_backups/
└─ .sync_tmp/
```

说明：

- `database.db` 是主 SQLite 数据库。
- `files/` 保存导入后的托管音频文件。
- `covers/` 保存从音频文件中提取出的封面。
- `sync_backups/` 保存局域网同步覆盖前的备份。
- `.sync_tmp/` 是同步下载远端库时的临时目录。
- SQLite 开启了 WAL，连接时会设置 `foreign_keys = ON`、`journal_mode = WAL`、`synchronous = NORMAL`。

用户可以在设置中切换托管路径。切换后会重新初始化该路径下的数据库并加载对应音乐库。

### 2. 音频导入

当前支持两种主要导入方式：

- 导入单首或多首音频文件。
- 导入整个文件夹。

文件夹导入流程更加完整：

1. 选择目录。
2. Rust 递归扫描目录下支持的音频文件。
3. Flutter 分批预览文件元数据。
4. 弹出导入预览窗口。
5. 用户可以全选、取消全选、逐项勾选。
6. 只导入最终勾选的文件。

支持扫描和导入的扩展名：

```text
mp3
wav
flac
m4a
ogg
aac
```

导入时 Rust 会做这些事情：

- 使用 `lofty` 读取标签和基础音频属性。
- 使用 `symphonia` 对时长做更可靠的估算。
- 对原始 AAC 做特殊时长处理，避免只依赖不可靠的容器元数据。
- 读取标题、歌手、专辑。
- 读取码率、采样率、位深、文件大小。
- 快速计算响度指标。
- 读取文件字节并计算 MD5。
- 如果 MD5 已存在于 `audio_files` 表，则拒绝重复导入。
- 生成 UUID 文件名并复制到 `files/`。
- 如果源音频旁边有同名 `.lrc`，会复制到托管音频旁边。
- 尝试提取内嵌封面并保存到 `covers/<song_id>.<ext>`。
- 写入 `songs` 与 `audio_files` 表。
- 第一个音源版本自动成为默认版本。

导入后的托管文件名不再依赖原始文件名，原始名称会保存在数据库的 `original_name` 字段中。

### 3. 音源版本管理

Aetheria 把“同一首歌的不同音频文件版本”作为一等实体管理。每首歌可以拥有多个 `AudioVersion`。

每个音源版本保存：

- 版本 ID。
- 所属歌曲 ID。
- 托管相对路径。
- 原始文件名。
- 文件格式。
- 码率。
- 采样率。
- 时长。
- 文件大小。
- 是否启用。
- 是否默认版本。
- MD5。
- 位深。
- 响度。
- 是否已经完成完整元数据扫描。

用户可以：

- 给现有歌曲补充新的音源版本。
- 把某个版本设为默认版本。
- 播放某个指定版本。
- 导出某个版本的物理音频文件。
- 删除某个版本。

默认版本切换逻辑：

- 同一首歌只能有一个默认版本。
- 设置新默认版本时，会先清空该歌曲所有版本的 `is_primary`。
- 再把目标版本设为默认，并确保 `is_enabled = 1`。
- 如果当前歌曲正在播放，切换默认版本时会尽量保留当前播放进度。

删除版本逻辑：

- 会删除该版本对应的托管音频文件。
- 会删除该托管音频旁边的 `.lrc` 文件。
- 会删除绑定到该版本的歌词记录。
- 会删除 `audio_files` 表记录。
- 如果删除的是默认版本，并且歌曲还有其它版本，会自动挑选一个剩余版本作为默认版本。

### 4. 歌曲删除与音乐库重置

彻底删除歌曲时会：

- 查询并删除该歌曲所有托管音频文件。
- 删除每个音频文件旁边的 `.lrc`。
- 删除歌曲绑定的歌词。
- 删除歌曲记录。
- 删除歌曲封面文件。
- 通过数据库外键级联清理标签关系和歌单关系。

重置音乐库时会：

- 清空核心数据库表。
- 重建 `files/` 与 `covers/` 目录。
- 重新写入默认标签。

这是不可逆操作，适合重新整理整个库时使用。

### 5. 元数据刷新

设置页提供两个刷新入口：

- 刷新整个音乐库。
- 仅刷新未完整扫描的歌曲。

刷新会逐首歌曲、逐个音源版本执行：

- 重新读取码率。
- 重新读取采样率。
- 重新读取时长。
- 重新读取位深。
- 执行完整响度扫描。
- 将 `metadata_scanned` 标记为已完成。

刷新界面会显示：

- 当前刷新进度。
- 总歌曲数。
- 当前处理的歌曲标题。
- 空库或无未扫描歌曲时的提示。

### 6. 歌曲列表与桌面表格

桌面端主列表是自定义歌曲表，不是普通的系统表格控件。

默认列包括：

| 列 | 含义 |
| --- | --- |
| 歌曲名称 | 歌曲标题，同时显示歌词标记等状态 |
| 歌手 | 歌手名称，缺失时显示未知歌手 |
| 标签 | 当前歌曲绑定的标签 Chip |
| 版本数 | 该歌曲拥有的音源版本数量 |
| 默认音质 | 默认版本的格式、采样率、位深、码率、响度等概要 |

桌面表格支持：

- 表头拖拽调整列顺序。
- 表头拖拽调整列宽。
- 列顺序保存到 `aetheria-song-table-column-order`。
- 列宽保存到 `aetheria-song-table-column-width-*`。
- 单击选中。
- 双击播放。
- `Ctrl` / `Cmd` 追加或取消选择。
- `Shift` 范围选择。
- 鼠标框选多首歌曲。
- 右键打开上下文菜单。
- 当前播放歌曲高亮。
- 当前激活详情歌曲高亮。
- 歌词可用时显示 `LRC` 标记。

右键菜单支持：

- 复制所选歌曲。
- 剪切所选歌曲。
- 彻底删除歌曲。
- 从当前歌单移除。
- 添加到任意歌单。
- 粘贴到当前歌单。

删除歌曲时有二次确认文案，会明确提示数据库记录和本地音频文件都会删除。

### 7. 搜索、排序与过滤

搜索框会过滤：

- 歌曲标题。
- 歌手。
- 专辑。

非歌单视图下，歌曲会使用 Explorer 风格自然排序：

- Windows Rust 侧使用 `StrCmpLogicalW`。
- Dart 侧也实现了自然排序逻辑，保证桌面与移动端显示尽量一致。
- 排序时会先按标题，再按歌手，再按 ID。

歌单视图下不会重新自然排序，而是保留用户在歌单中的排序顺序。

标签过滤支持：

- `AND`：必须包含所有正向标签。
- `OR`：包含任意正向标签即可。
- 排除标签：只要命中排除标签就过滤掉。

标签点击是三态循环：

```text
未参与过滤 -> 正向包含 -> 反向排除 -> 未参与过滤
```

### 8. 标签系统

标签由独立的 `tags` 表管理，可以绑定到多首歌曲。标签字段包括：

- 名称。
- 颜色。
- 分类。

默认种子标签包括：

| 分类 | 默认标签 |
| --- | --- |
| 语言 | 中文、英文、日韩 |
| 流派 | 纯音乐、摇滚、流行、民谣、古典 |
| 情绪 | 伤感、治愈、欢快 |

标签管理弹窗支持：

- 新建标签。
- 编辑已有标签。
- 删除标签。
- 设置标签颜色。
- 选择预设分类。
- 输入自定义分类。

标签管理弹窗中的分类预设包括：

```text
流派
语言
情绪
场景
自定义
```

歌曲详情页的“标签管理”页可以直接为当前歌曲勾选或取消标签。

### 9. 歌单系统

歌单由 `playlists` 与 `playlist_songs` 管理。

支持：

- 创建歌单。
- 重命名歌单。
- 删除歌单。
- 将歌曲加入歌单。
- 从当前歌单移除歌曲。
- 歌单内保存排序字段。
- 在当前歌单中展示用户定义顺序。
- 桌面端右键菜单添加到歌单。
- 移动端长按菜单添加到歌单。
- 复制 / 剪切 / 粘贴式整理。

删除歌单只删除歌单与歌单关系，不删除歌曲和音频文件。

复制 / 剪切 / 粘贴逻辑：

- 复制：记录歌曲 ID 和来源歌单。
- 剪切：记录歌曲 ID 和来源歌单。
- 粘贴：添加到目标歌单。
- 如果是剪切且来源歌单与目标歌单不同，会从来源歌单移除。

### 10. 歌词系统

歌词系统包含“发现候选、预览、保存、选择、显示、偏移、悬浮输出”几部分。

歌词可以绑定到两个层级：

- 歌曲级：适用于整首歌所有版本。
- 音源版本级：适用于某个具体版本，优先级高于歌曲级歌词。

保存的歌词字段包括：

- 歌词 ID。
- 歌曲 ID。
- 可选音源版本 ID。
- 来源。
- 来源 ID。
- 标题。
- 歌手。
- 歌词正文。
- 翻译歌词。
- 罗马音歌词。
- 偏移量，单位毫秒。
- 是否被选中。
- 更新时间。

#### 本地歌词来源

本地候选包括：

- 音频文件内嵌歌词。
- 托管音频旁边的同名 `.lrc`。
- 原始文件名对应的 `.lrc`。
- 旧版 `songs.lyrics` 字段里的遗留歌词。

#### 在线歌词来源

当前搜索服务会并发请求多个来源：

- LRCLIB。
- 网易云音乐。
- QQ 音乐。
- 酷狗音乐。
- 本地歌词候选。

候选会按来源、ID、标题、歌手去重。

候选加载逻辑：

- LRCLIB 候选通常直接包含同步歌词或纯文本歌词。
- 网易云音乐候选保存 ID，预览时再请求歌词、翻译和罗马音。
- QQ 音乐候选保存 songmid，预览时请求并处理可能的 Base64 / HTML 转义内容。
- 酷狗候选保存 hash，预览时先查歌词候选，再下载歌词内容。

#### 歌词管理界面

详情面板里的“歌词管理”支持：

- 搜索歌词候选。
- 查看当前已保存歌词。
- 打开候选预览。
- 保存候选歌词。
- 手动粘贴歌词并保存。
- 调整歌词偏移。
- 删除歌词。
- 选择某条已保存歌词作为当前使用版本。
- 保存成功后刷新歌曲列表的 `LRC` 标记。
- 通知悬浮歌词重新加载。

#### 歌词显示

详情面板里的“滚动歌词”支持：

- 自动加载当前歌曲/版本的已选歌词。
- 如果版本级歌词存在，优先使用版本级歌词。
- 如果没有保存歌词，则回退到旧版歌曲字段。
- 显示来源与偏移量。
- 按播放位置高亮当前行。
- 显示翻译行。
- 自动滚动。
- 用户滚动时显示居中 Seek Guide。
- 点击 Seek Guide 可跳转到居中歌词行对应时间点。
- 如果没有歌词，可以一键进入歌词管理。

### 11. 歌词格式解析

当前歌词解析支持多种常见格式：

#### 标准 LRC 时间轴

```text
[01:23.45]歌词正文
[01:23:45]歌词正文
[01:23.456]歌词正文
```

支持一行多个时间戳：

```text
[00:10.00][01:10.00]重复歌词
```

#### QRC / 逗号时间轴

支持类似：

```text
[12345,3000]歌词正文
```

其中第一个数字是开始毫秒，第二个数字是持续时长。

#### 逐字 / 片段时间

支持相对片段：

```text
[00:10.00](0,300)你(300,300)好
[00:10.00]<0,300>你<300,300>好
```

也支持绝对片段：

```text
[00:10.00]<00:10.10>你<00:10.40>好
```

解析器会为行和片段补齐结束时间，用于计算悬浮歌词进度和逐行进度。

#### 元数据行

类似下面的元数据行会被忽略：

```text
[ar:Artist]
[ti:Title]
[al:Album]
```

### 12. 悬浮歌词

悬浮歌词由 Flutter 的 `FloatingLyricsProvider`、`FloatingLyricsBridge` 和平台原生实现共同完成。

通用能力：

- 开启 / 关闭悬浮歌词。
- 锁定歌词窗口。
- 暂停时淡出。
- 显示翻译歌词。
- 显示下一行歌词。
- 紧凑多行模式。
- 当前行加粗。
- 当前行放大。
- 文字阴影。
- 左对齐、居中、右对齐。
- 字体大小调节。
- 行间距调节。
- 刷新帧率调节。
- 透明度调节。
- 未播放颜色自定义。
- 已播放颜色自定义。
- 阴影颜色自定义。
- 窗口宽度与高度调节。
- 记忆窗口位置和尺寸。
- 重置样式。
- 重置窗口位置。

Flutter 侧会定时读取：

- 当前播放歌曲。
- 当前音源版本。
- 当前播放位置。
- 已选歌词。
- 翻译歌词。
- 偏移量。
- 悬浮歌词样式配置。

然后生成一帧歌词数据：

- 当前行文本。
- 翻译文本。
- 下一行文本。
- 紧凑模式下的更多上下文行。
- 当前行播放进度。
- 是否正在播放。
- 是否需要暂停淡出。
- 歌曲标题。
- 歌手。

#### Windows 悬浮歌词

Windows 端通过 `windows/runner/floating_lyric_window.cpp` 实现。

能力包括：

- 单独透明分层窗口。
- GDI+ 绘制歌词文本。
- 绘制阴影。
- 绘制已播放进度填充。
- 支持始终置顶。
- 支持锁定后鼠标穿透。
- 支持拖拽移动。
- 支持边缘缩放。
- 支持圆角背景。
- 支持将窗口边界变化回传给 Flutter。
- 支持从 Flutter 更新样式和歌词帧。

Windows MethodChannel 名称：

```text
com.aetheria.app/notification
```

虽然名称沿用了 notification，但其中也承载了悬浮歌词相关方法。

#### Android 悬浮歌词

Android 端通过 `FloatingLyricService.kt` 实现。

能力包括：

- 使用系统悬浮窗权限。
- 使用前台服务承载悬浮歌词。
- 显示服务通知。
- 使用 `WindowManager` 添加悬浮 View。
- 支持拖拽移动。
- 支持锁定。
- 支持窗口大小更新。
- 支持样式和歌词帧更新。
- 支持边界变化回传 Flutter。
- 暂停时按配置降低透明度。

Android 首次使用悬浮歌词时，需要授予：

```text
SYSTEM_ALERT_WINDOW
```

### 13. 播放控制

播放器状态由 `AudioPlayerProvider` 管理，底层播放由 Rust 音频引擎完成。

用户可用控制：

- 播放。
- 暂停。
- 上一首。
- 下一首。
- 拖动进度条。
- 调节音量。
- 切换播放模式。
- 打开/关闭详情面板。
- 在详情面板中切换播放版本。

播放模式包括：

- 列表循环。
- 随机播放。
- 单曲循环。

播放状态恢复会保存：

- 上次播放歌曲 ID。
- 上次播放音源版本 ID。
- 上次播放位置。
- 上次播放队列。
- 音量。

启动后如果有可恢复状态：

- 会恢复当前歌曲、版本、队列和进度。
- 默认不会自动开始播放。
- 第一次按播放时再真正准备 Rust 播放。

播放结束处理：

- 单曲循环会回到开头继续播放。
- 其它模式会进入下一首。

### 14. Android 通知栏与 MediaSession

Android 原生层提供播放通知栏。

通知栏支持：

- 显示歌曲标题。
- 显示歌手。
- 显示播放/暂停状态。
- 显示播放进度。
- 显示总时长。
- 上一首。
- 播放/暂停。
- 下一首。
- 显示内嵌封面大图。

通知栏操作会通过 MethodChannel 回调 Flutter：

```text
previous
toggle
next
seek:<positionMs>
```

Android 端还接入了 `MediaSessionCompat`，用于系统媒体控制入口。

### 15. 音频 DSP 与输出设置

设置页的“播放设置”提供多个音频相关选项。

#### 与其他应用一起播放

Android 上可开启“与其他应用一起播放”，允许本软件与其它音频应用混音播放。

#### 主动音量均衡

音量均衡会根据当前队列中默认音源版本的响度计算一个参考响度，然后对较大的歌曲进行压低，不主动抬高声音小的歌曲。

设置项：

- 是否启用音量均衡。
- 均衡强度。

#### 输出状态

设置页会展示 Rust 音频输出信息，包括：

- 当前输出设备名。
- 采样率。
- 声道数。
- 样本格式。
- 设备缓冲设置。
- 输出延迟模式。
- 应用侧输出缓冲毫秒数。
- 当前队列缓冲毫秒数。
- 欠载次数。
- 剪裁保护计数。
- 峰值 dB。

#### 输出延迟模式

支持：

```text
shared-default
shared-low-latency
shared-stable
```

Rust 侧会根据设备支持的缓冲范围选择合适帧数：

- 低延迟倾向 256 frames。
- 稳定模式倾向 1024 frames。
- 默认模式使用设备默认。

如果固定缓冲创建失败，会回退到默认缓冲。

#### 输出音调调节器

支持：

- 开启 / 关闭输出变调。
- 半音级音高调节。
- 处理缓冲大小。
- Rubber Band 算法。
- resample 算法。

预设处理缓冲：

```text
120ms  超低延迟
240ms  平衡
480ms  稳定
960ms  高容错
```

也支持自定义缓冲，Rust 侧会限制在合理范围内。

Rubber Band 设置：

- `latency`：低延迟窗口。
- `quality`：高质量窗口。
- formant preserved：保留人声音色。

Resampler 设置：

- `standard`：标准 sinc。
- `high`：更高质量 sinc。

#### 峰值保护与抖动

峰值保护：

- DSP 后会检测峰值。
- 超过安全范围时应用软限幅。
- 记录被保护的样本数量。

整数输出抖动：

- 当设备输出格式不是 f32 时使用。
- 对 i16、u16、i32、u8 等输出格式加入 TPDF dither。
- 用于降低量化失真。

#### 热重载 DSP

大部分 DSP 设置改变后，如果当前歌曲已经准备播放，会重新启动当前 Rust 播放链路并 seek 回原位置，尽量减少用户感知中断。

### 16. 输出设备变化处理

Android 原生层会监听音频路由变化并回调 Flutter。

桌面/通用逻辑会定期读取 Rust 默认输出设备名。若发现默认输出设备发生变化：

- 当前有播放上下文时，会在合适时机重建当前播放。
- 尽量跟随系统默认输出设备切换。

### 17. 开发者模式与性能报告

设置页包含“开发者模式”标签页。

开启后 Rust 音频引擎会记录调用树统计，内容包括：

- 函数调用次数。
- CPU 总耗时。
- CPU 自耗时。
- 墙上总耗时。
- 墙上自耗时。
- 平均 CPU 耗时。
- 最大 CPU 耗时。
- 线程维度统计。
- 完整调用路径。

界面支持：

- 开启 / 关闭性能统计。
- 清零统计。
- 复制 JSON 报告。
- 导出 Markdown 详细报告。
- 在界面中查看函数热点。

Rust 报告会说明：

- 采集模式是 instrumented call tree。
- CPU 时间优先使用线程 CPU 时钟。
- 不支持的平台回退到墙上时钟。
- 未埋点的第三方解码器、操作系统和 Dart/Flutter VM 代码会归入最近的 Aetheria 父函数。

### 18. 局域网镜像同步

局域网同步由 `SyncProvider` 实现，是当前项目的重要功能之一。

同步定位：

- 它不是双向合并。
- 它不是云盘增量冲突解决。
- 它是“以对方音乐库为准”的镜像覆盖同步。

同步服务启动后会：

- 开启本地 HTTP 服务，端口由系统分配。
- 绑定 UDP 发现端口 `43871`。
- 每 4 秒发送一次广播。
- 每 10 秒清理一次过期设备。
- Android 上申请 Wi-Fi Multicast Lock 提升发现稳定性。

UDP 广播内容包括：

- 类型：`aetheria-sync-announcement`。
- 协议版本。
- 设备 ID。
- 设备名称。
- HTTP 服务端口。
- 歌曲数量。
- 音源版本数量。

发现设备后界面会显示：

- 设备名。
- 地址与端口。
- 歌曲数。
- 版本数。
- 最近发现状态。

#### 同步审批流程

发起同步时：

1. 本机向远端 `POST /sync/request`。
2. 请求中带本机设备 ID、设备名和 request ID。
3. 远端界面弹出授权请求。
4. 远端用户可以同意或拒绝。
5. 同意后远端生成临时 token。
6. token 有效期 30 分钟。
7. 后续 manifest、database、file 请求都必须带 `X-Aetheria-Sync-Token`。

#### HTTP 接口

同步 HTTP 服务支持：

| 路径 | 方法 | 含义 |
| --- | --- | --- |
| `/sync/request` | POST | 请求远端审批 |
| `/sync/manifest` | GET | 获取远端数据库与文件清单 |
| `/sync/database` | GET | 下载远端 `database.db` |
| `/sync/file?path=files/...` | GET | 下载某个托管音频文件 |

#### Manifest 内容

远端 manifest 包含：

- 设备 ID。
- 设备名。
- 数据库大小。
- 数据库 MD5。
- `files/` 下每个文件的相对路径。
- 每个文件大小。
- 每个文件 MD5。

本地会缓存文件 MD5，缓存键包含：

- 文件路径。
- 文件大小。
- 修改时间。

这样可以减少重复计算。

#### 镜像同步流程

拉取远端音乐库时：

1. 请求远端授权。
2. 获取 manifest。
3. 下载远端 `database.db` 到临时目录。
4. 校验数据库大小。
5. 如果 manifest 提供 MD5，则校验数据库 MD5。
6. 比对本地 `files/` 与远端文件清单。
7. 下载本地缺失或内容不同的远端文件。
8. 校验文件大小。
9. 如果远端提供 MD5，则校验文件 MD5。
10. 停止本地播放。
11. checkpoint 本地数据库 WAL。
12. 创建同步备份目录。
13. 将需要移除或替换的本地文件移动到备份目录。
14. 安装下载好的远端文件。
15. 删除本地数据库 WAL / SHM sidecar。
16. 用远端数据库覆盖本地数据库。
17. 重新初始化库路径。
18. 重新加载音乐库。
19. 重新广播本机设备状态。

如果覆盖过程中失败，会尝试：

- 删除已安装的新文件。
- 把已移动到备份目录的文件还原。
- 用备份数据库恢复本地数据库。

同步完成后状态会显示：

```text
同步完成，已以 <设备名> 的音乐库为准
```

#### 同步安全限制

文件路径必须满足：

- 必须以 `files/` 开头。
- 不允许 `..`。
- 不允许连续斜杠。
- 不允许空路径片段。

同步只处理音乐库托管文件，不会任意读写系统其它路径。

#### 同步不会同步的内容

当前同步的是音乐库数据库和 `files/` 音频文件。下面这些本机偏好不会随库同步：

- 当前主题。
- 播放音量。
- DSP 设置。
- 悬浮歌词样式。
- 悬浮歌词窗口位置。
- 开发者模式设置。
- 文件哈希缓存。

### 19. 移动端体验

移动端有独立布局，不是桌面布局的简单缩放。

移动端主界面包括：

- 顶部菜单按钮。
- 搜索框。
- 标签管理入口。
- 设置入口。
- 可折叠标签过滤器。
- 当前歌单标题和歌曲数量。
- 歌曲列表。
- 底部迷你播放器。

移动端抽屉支持：

- 查看全部歌曲。
- 查看歌单列表。
- 新建歌单。
- 歌单重命名。
- 歌单删除。

移动端歌曲条目支持：

- 点击播放。
- 长按打开操作菜单。
- 显示歌曲标题、歌手、标签、版本/音质信息等。

移动端长按菜单支持：

- 查看详情。
- 添加到歌单。
- 从当前歌单移除。
- 彻底删除歌曲。

移动端歌曲详情 Sheet 支持：

- 查看歌曲信息。
- 播放控制相关入口。
- 标签管理。
- 歌词管理。
- 音源版本管理。
- 添加新版本。
- 导出版本。
- 删除版本。

### 20. 设置页

设置页按功能分为多个标签：

- 个性外观。
- 播放设置。
- 桌面歌词 / 安卓悬浮歌词。
- 音乐库管理。
- 局域网同步。
- 开发者模式。

#### 个性外观

内置主题：

- 深邃暗色。
- 纯净亮色。
- 温润粉樱。
- 暮樱暗粉。

主题会持久化保存到：

```text
aetheria-theme
```

#### 音乐库管理

支持：

- 查看当前托管路径。
- 选择新托管路径。
- 导入音频。
- 导入目录。
- 刷新整个数据库。
- 仅刷新未完整扫描歌曲。
- 查看刷新进度。

#### 播放设置

支持：

- 与其他应用一起播放。
- 主动音量均衡。
- 均衡强度。
- 输出状态查看。
- 输出延迟模式。
- 变调开关。
- 半音调节。
- 处理缓冲。
- 变调算法。
- Rubber Band 窗口。
- Rubber Band formant 保持。
- 重采样质量。
- 峰值保护。
- 整数输出抖动。

#### 悬浮歌词设置

支持：

- 显示悬浮歌词。
- Android 请求悬浮窗权限。
- 锁定歌词窗口。
- Windows 保持置顶。
- 暂停时降低透明度。
- 对齐方式。
- 窗口宽度。
- 窗口高度。
- 字体大小。
- 歌词间距。
- 刷新帧率。
- 透明度。
- 当前行加粗。
- 当前行轻微放大。
- 紧凑显示多行。
- 文字阴影。
- 显示翻译歌词。
- 显示下一行歌词。
- 未播放/已播放/阴影颜色。
- 重置样式。
- 重置窗口位置。

#### 局域网同步

支持：

- 启动同步服务。
- 刷新发现设备。
- 清空设备列表。
- 查看本机设备名。
- 查看本机同步端口。
- 查看同步错误。
- 审批对方同步请求。
- 拒绝对方同步请求。
- 查看同步进度。
- 从发现设备同步到本机。

#### 开发者模式

支持：

- 启用性能统计。
- 清零统计。
- 复制 JSON。
- 导出详细 Markdown 报告。
- 查看采集模式、CPU 时钟、线程数、统计时长。
- 查看函数热点。

## 技术架构

### 总体结构

```text
Aetheria
├─ Flutter UI
│  ├─ MaterialApp / ThemeData
│  ├─ Provider 状态层
│  ├─ 桌面与移动端布局
│  ├─ 歌曲表、播放栏、详情面板、设置页
│  ├─ 歌词显示、歌词管理、悬浮歌词桥接
│  └─ MethodChannel 调用平台原生能力
│
├─ Rust Core
│  ├─ SQLite 初始化与连接
│  ├─ 音乐导入、元数据读取、封面提取
│  ├─ 歌曲、版本、标签、歌词、歌单持久化
│  ├─ 音频解码、输出、DSP、设备信息
│  ├─ 本地 HTTP Range 音频服务
│  └─ 通过 flutter_rust_bridge 暴露 API
│
├─ Android Native
│  ├─ MethodChannel
│  ├─ 通知栏播放控制
│  ├─ MediaSession
│  ├─ 悬浮歌词前台服务
│  ├─ Downloads 导出
│  ├─ 通知/悬浮窗权限
│  ├─ Wi-Fi Multicast Lock
│  └─ 音频路由变化回调
│
└─ Windows Native
   ├─ Flutter Windows runner
   ├─ MethodChannel
   └─ GDI+ 透明悬浮歌词窗口
```

### Flutter 侧核心 Provider

| Provider | 文件 | 职责 |
| --- | --- | --- |
| `UIThemeProvider` | `lib/core/providers/ui_theme_provider.dart` | 主题读取、切换和持久化 |
| `LibraryProvider` | `lib/core/providers/library_provider.dart` | 音乐库、歌曲、标签、歌单、搜索、过滤、导入、删除、刷新 |
| `AudioPlayerProvider` | `lib/core/providers/audio_player_provider.dart` | 播放状态、队列、音量、播放模式、DSP、通知栏、恢复状态 |
| `SyncProvider` | `lib/core/providers/sync_provider.dart` | 局域网发现、HTTP 同步服务、审批、拉取、镜像覆盖 |
| `FloatingLyricsProvider` | `lib/core/providers/floating_lyrics_provider.dart` | 悬浮歌词开关、样式、窗口位置、刷新通知 |

### Rust 侧核心模块

| 模块 | 文件 | 职责 |
| --- | --- | --- |
| API | `rust/src/api/music.rs` | 暴露给 Dart 的主要业务接口 |
| Simple API | `rust/src/api/simple.rs` | 简单桥接示例 |
| 数据库连接 | `rust/src/database/connection.rs` | 库目录、文件目录、SQLite 连接 |
| 数据库结构 | `rust/src/database/schema.rs` | 建表、迁移、默认标签 |
| 音频播放 | `rust/src/audio/player.rs` | cpal 输出、解码管线、缓冲、播放控制 |
| DSP | `rust/src/audio/dsp.rs` | 响度、流式解码、重采样、变调 |
| Rubber Band | `rust/src/audio/rubberband.rs` | Rubber Band LiveShifter FFI 封装 |
| 音频 HTTP 服务 | `rust/src/audio/server.rs` | 本地 Range 请求服务 |
| 性能统计 | `rust/src/audio/profiler.rs` | 调用树性能报告 |
| 模型 | `rust/src/models/` | Song、AudioVersion、Tag、SavedLyric、Playlist |

## 目录结构

```text
.
├─ android/
│  └─ app/
│     ├─ build.gradle.kts
│     ├─ CMakeLists.txt
│     └─ src/main/
│        ├─ AndroidManifest.xml
│        └─ kotlin/com/aetheria/aetheria/
│           ├─ MainActivity.kt
│           └─ FloatingLyricService.kt
│
├─ integration_test/
│  └─ simple_test.dart
│
├─ lib/
│  ├─ main.dart
│  ├─ core/
│  │  ├─ providers/
│  │  │  ├─ audio_player_provider.dart
│  │  │  ├─ floating_lyrics_provider.dart
│  │  │  ├─ library_provider.dart
│  │  │  ├─ sync_provider.dart
│  │  │  └─ ui_theme_provider.dart
│  │  ├─ theme/
│  │  │  ├─ app_theme_config.dart
│  │  │  ├─ aetheria_theme.dart
│  │  │  ├─ theme.dart
│  │  │  ├─ tokens/
│  │  │  └─ UI_CONTRACT.md
│  │  ├─ utils/
│  │  │  └─ audio_quality.dart
│  │  └─ widgets/
│  │     └─ Aether UI primitives
│  │
│  ├─ features/
│  │  ├─ layout/
│  │  │  ├─ main_layout.dart
│  │  │  ├─ mobile_layout.dart
│  │  │  └─ mobile/
│  │  ├─ library/
│  │  │  └─ ui/
│  │  │     ├─ main_content.dart
│  │  │     ├─ settings_modal.dart
│  │  │     ├─ settings/
│  │  │     ├─ song_table.dart
│  │  │     ├─ song_table/
│  │  │     ├─ tag_filter.dart
│  │  │     └─ tag_manager_modal.dart
│  │  ├─ lyrics/
│  │  │  ├─ floating_lyrics_bridge.dart
│  │  │  └─ lyric_timeline.dart
│  │  ├─ player/
│  │  │  └─ ui/
│  │  │     ├─ detail_pane.dart
│  │  │     ├─ lyrics_panel.dart
│  │  │     ├─ lyrics/
│  │  │     ├─ play_bar.dart
│  │  │     └─ song_cover_art.dart
│  │  └─ sidebar/
│  │     └─ ui/sidebar.dart
│  │
│  ├─ services/
│  │  ├─ lyric_search_service.dart
│  │  └─ native_audio_helper.dart
│  │
│  └─ src/rust/
│     └─ flutter_rust_bridge 生成代码
│
├─ rust/
│  ├─ Cargo.toml
│  ├─ build.rs
│  ├─ src/
│  │  ├─ api/
│  │  ├─ audio/
│  │  ├─ database/
│  │  ├─ models/
│  │  ├─ frb_generated.rs
│  │  └─ lib.rs
│  └─ vendor/rubberband/
│
├─ rust_builder/
│  └─ cargokit / Flutter FFI plugin glue
│
├─ test/
│  ├─ floating_lyrics_provider_test.dart
│  ├─ library_provider_test.dart
│  ├─ theme_primitives_test.dart
│  └─ widget_test.dart
│
├─ test_driver/
│  └─ integration_test.dart
│
├─ windows/
│  ├─ CMakeLists.txt
│  └─ runner/
│     ├─ floating_lyric_window.cpp
│     ├─ floating_lyric_window.h
│     ├─ flutter_window.cpp
│     ├─ flutter_window.h
│     └─ main.cpp
│
├─ flutter_rust_bridge.yaml
├─ pubspec.yaml
├─ HANDOVER.md
└─ README.md
```

## 数据目录与数据库

### 数据库表

当前 SQLite 主要表如下：

#### `songs`

保存歌曲基础信息。

| 字段 | 含义 |
| --- | --- |
| `id` | 歌曲 ID |
| `title` | 标题 |
| `artist` | 歌手 |
| `album` | 专辑 |
| `lyrics` | 旧版遗留歌词字段 |
| `cover_path` | 封面相对路径 |
| `rating` | 评分 |
| `created_at` | 创建时间 |
| `updated_at` | 更新时间 |

#### `audio_files`

保存每首歌的音源版本。

| 字段 | 含义 |
| --- | --- |
| `id` | 音源版本 ID |
| `song_id` | 所属歌曲 |
| `filepath` | 托管相对路径 |
| `original_name` | 原始文件名 |
| `format` | 文件格式 |
| `bitrate` | 码率 |
| `sample_rate` | 采样率 |
| `duration` | 时长 |
| `file_size` | 文件大小 |
| `is_enabled` | 是否启用 |
| `is_primary` | 是否默认版本 |
| `md5` | 文件 MD5 |
| `bit_depth` | 位深 |
| `loudness` | 响度 |
| `metadata_scanned` | 是否完整扫描 |
| `created_at` | 创建时间 |

#### `tags`

保存标签定义。

| 字段 | 含义 |
| --- | --- |
| `id` | 自增标签 ID |
| `name` | 标签名 |
| `color` | 标签颜色 |
| `category` | 标签分类 |
| `created_at` | 创建时间 |

#### `song_tags`

歌曲与标签的多对多关系。

#### `lyrics`

保存歌词。

| 字段 | 含义 |
| --- | --- |
| `id` | 歌词 ID |
| `song_id` | 所属歌曲 |
| `audio_version_id` | 可选音源版本 |
| `source` | 来源 |
| `source_id` | 来源 ID |
| `title` | 歌词标题 |
| `artist` | 歌词歌手 |
| `content` | 歌词正文 |
| `translation` | 翻译歌词 |
| `romanized` | 罗马音歌词 |
| `offset_ms` | 偏移毫秒 |
| `is_selected` | 是否当前选中 |
| `created_at` | 创建时间 |
| `updated_at` | 更新时间 |

#### `playlists`

保存歌单。

| 字段 | 含义 |
| --- | --- |
| `id` | 歌单 ID |
| `name` | 歌单名 |
| `description` | 描述 |
| `created_at` | 创建时间 |

#### `playlist_songs`

歌单与歌曲关系，并保存排序字段。

| 字段 | 含义 |
| --- | --- |
| `playlist_id` | 歌单 ID |
| `song_id` | 歌曲 ID |
| `sort_order` | 歌单内顺序 |

### 自动迁移

数据库初始化时会自动检查并补齐旧库缺失字段：

- `audio_files.md5`
- `audio_files.bit_depth`
- `audio_files.loudness`
- `audio_files.metadata_scanned`

### 索引

当前会创建这些索引：

- `idx_audio_files_song`
- `idx_song_tags_song`
- `idx_song_tags_tag`
- `idx_lyrics_song_version`

## 开发环境

建议准备：

- Flutter SDK。
- Dart SDK，项目约束为 `^3.12.2`。
- Rust stable toolchain。
- Android Studio / Android SDK，构建 Android 时需要。
- Visual Studio 2022 C++ 桌面开发工具链，构建 Windows 时需要。
- CMake / Ninja，通常随 Flutter Windows 工具链配置。

项目关键依赖：

| 依赖 | 用途 |
| --- | --- |
| `flutter_rust_bridge` | Flutter 与 Rust 桥接 |
| `provider` | Flutter 状态管理 |
| `shared_preferences` | 本地偏好持久化 |
| `path_provider` | 应用文档目录 |
| `file_picker` | 文件和目录选择 |
| `audio_session` | 音频会话 |
| `crypto` | Dart 侧哈希能力 |
| `rusqlite` | Rust SQLite |
| `lofty` | 音频标签和元数据 |
| `symphonia` | 音频解码和时长估算 |
| `cpal` | 跨平台音频输出 |
| `md5` | 文件去重与同步校验 |
| `uuid` | ID 生成 |

## 快速开始

### 1. 获取 Dart / Flutter 依赖

```powershell
flutter pub get
```

### 2. 准备 Rust 工具链

如果本机还没有 Rust：

```powershell
rustup default stable
```

### 3. 运行 Windows 版本

```powershell
flutter run -d windows
```

### 4. 运行 Android 版本

```powershell
flutter run -d android
```

### 5. 构建 Windows Release

```powershell
flutter build windows
```

默认输出位置：

```text
build/windows/x64/runner/Release/aetheria.exe
```

运行时需要保留同目录下 Flutter、插件和 native asset 生成的 DLL / data 文件。

### 6. 构建 Android APK

```powershell
flutter build apk --target-platform android-arm64
```

默认输出位置：

```text
build/app/outputs/flutter-apk/app-release.apk
```

当前 Android release 构建仍使用 debug signingConfig，正式发布前需要替换为自己的签名配置。

## 常用开发命令

```powershell
flutter pub get
flutter analyze
flutter test
flutter run -d windows
flutter run -d android
flutter build windows
flutter build apk --target-platform android-arm64
flutter_rust_bridge_codegen
```

## 平台说明

### Windows

Windows 是当前桌面端重点平台。

相关能力：

- Flutter Windows runner。
- Rust `cpal` 音频输出。
- GDI+ 桌面悬浮歌词窗口。
- 透明分层窗口。
- 置顶、拖拽、缩放、锁定穿透。
- 输出设备变化检测。

Windows runner 额外链接：

- `dwmapi.lib`
- `gdiplus.lib`

### Android

Android 是当前移动端重点平台。

Android Manifest 权限包括：

- `INTERNET`
- `ACCESS_NETWORK_STATE`
- `ACCESS_WIFI_STATE`
- `CHANGE_WIFI_MULTICAST_STATE`
- `POST_NOTIFICATIONS`
- `SYSTEM_ALERT_WINDOW`
- `FOREGROUND_SERVICE`
- `FOREGROUND_SERVICE_MEDIA_PLAYBACK`

Android 原生能力：

- 初始化 Rust / Oboe 所需 Android context。
- 播放通知栏。
- MediaSession。
- 通知栏操作回调。
- 系统 Downloads 导出。
- 系统悬浮窗歌词。
- 悬浮窗权限请求。
- 通知权限请求。
- 获取设备名。
- Wi-Fi Multicast Lock。
- 音频路由变化监听。
- 启动时尽量选择更高刷新率显示模式。

Android Gradle 当前配置：

- `compileSdk = 36`
- Kotlin JVM target 17
- Java 17
- Android Gradle Plugin 9.0.1
- Kotlin Android Plugin 2.3.20
- 依赖 `androidx.media:media:1.7.0`

根 `android/build.gradle.kts` 中有一段对子工程 `compileSdkVersion(36)` 的兼容逻辑，用来避免部分插件因为 compileSdk 过低触发 AAR Metadata 检查失败。不要随意删除。

### iOS / macOS / Linux

`rust_builder` 作为 Flutter FFI 插件模板声明了多个平台，仓库中也包含 cargokit 的跨平台构建胶水。但当前应用根目录实际重点代码和平台原生实现集中在 Windows 与 Android。其它平台不是当前 README 所描述的主要交付目标。

## Flutter / Rust 桥接说明

桥接配置位于：

```text
flutter_rust_bridge.yaml
```

当前配置：

```yaml
rust_input: crate::api
rust_root: rust/
dart_output: lib/src/rust
```

Rust API 入口：

```text
rust/src/api/music.rs
rust/src/api/simple.rs
```

Dart 生成代码：

```text
lib/src/rust/
```

如果修改 Rust 暴露给 Flutter 的函数、参数、返回模型或模块结构，需要重新生成桥接代码：

```powershell
flutter_rust_bridge_codegen
```

生成后通常再执行：

```powershell
flutter pub get
```

再重新构建目标平台。

## 音频引擎说明

### 本地播放链路

当前主播放链路是 Rust 原生音频链路：

```text
音频文件
  -> symphonia 解码
  -> 声道转换
  -> 采样率转换
  -> 响度归一/音量均衡
  -> 变调处理
  -> 峰值保护
  -> 输出格式转换与抖动
  -> cpal 默认输出设备
```

### 流式解码

Rust 使用 `StreamDecoder` 分包解码音频，避免一次性把整个文件解码进内存。播放过程中使用环形缓冲在解码线程和音频回调线程之间传递样本。

### 输出格式

输出设备配置优先选择：

- 默认输出设备。
- 默认采样率。
- 默认声道数。
- f32 输出格式。

如果设备默认不是 f32，会回退到设备默认格式，并在整数格式输出前按设置加入 dither。

### 本地 HTTP Range 音频服务

Rust 还包含一个本地 HTTP Range 服务：

```text
127.0.0.1:16860-16865
```

如果固定端口不可用，会让系统分配随机端口。

服务支持：

- `GET`
- `HEAD`
- `OPTIONS`
- `Range` 请求。
- `206 Partial Content`。
- CORS 头。
- 音频 MIME 推断。

支持 MIME 包括：

- `mp3` -> `audio/mpeg`
- `flac` -> `audio/flac`
- `wav` -> `audio/wav`
- `m4a` -> `audio/mp4`
- `ogg` -> `audio/ogg`
- `aac` -> `audio/aac`
- `wma` -> `audio/x-ms-wma`

当前主要播放链路使用 Rust 原生输出；这个服务保留为本地音频流式访问能力。

## 局域网同步协议说明

同步协议由 Dart 层实现，不依赖云服务。

### 发现层

```text
UDP 43871
```

广播 JSON：

```json
{
  "type": "aetheria-sync-announcement",
  "version": 1,
  "deviceId": "...",
  "deviceName": "...",
  "port": 12345,
  "songCount": 10,
  "versionCount": 12,
  "reply": false
}
```

收到别人的广播后：

- 如果不是自己的设备 ID，就加入设备列表。
- 如果对方不是 reply 包，会向对方地址回发一次公告。
- 超过 45 秒未更新的设备会被清理。

### 授权层

远端审批成功后返回：

```json
{
  "approved": true,
  "token": "...",
  "expiresAt": "..."
}
```

后续请求必须带：

```text
X-Aetheria-Sync-Token: <token>
```

### 数据层

同步的数据包括：

- `database.db`
- `files/` 下的托管音频文件

不会同步：

- `covers/`
- `.sync_tmp/`
- `sync_backups/`
- 本机偏好设置

注意：虽然封面目录不在文件同步范围内，但数据库中保存了封面相对路径。当前代码可以在需要时通过 `ensureSongCover` 从音频文件重新提取封面。

## UI 设计系统与约束

Aetheria 已经抽出自己的 UI primitives 和主题 token。

主题目录：

```text
lib/core/theme/
```

通用组件目录：

```text
lib/core/widgets/
```

主要 UI primitives 包括：

- `AetherSurface`
- `AetherPressable`
- `AetherButton`
- `AetherIconButton`
- `AetherTextField`
- `AetherSlider`
- `AetherSeekBar`
- `AetherChip`
- `AetherBadge`
- `AetherChoiceGroup`
- `AetherSwitch`
- `AetherSwitchTile`
- `AetherListTile`
- `AetherSectionHeader`
- `AetherDialog`
- `showAetherDialog`
- `showAetherConfirmDialog`
- `showAetherModalPage`
- `showAetherMenu`
- `AetherDropdown`
- `showAetherSheet`
- `AetherEmptyState`
- `showAetherProgressDialog`
- `showAetherToast`

新 UI 应优先使用：

```dart
import 'package:aetheria/core/widgets/widgets.dart';
import 'package:aetheria/core/theme/theme.dart';
```

UI 约束详见：

```text
lib/core/theme/UI_CONTRACT.md
lib/core/README.md
```

关键规则：

- 颜色从 `AppThemeConfig` / `context.tokens` 读取。
- 新代码优先使用语义 token，例如 `textPrimary`、`bgElevated`、`borderSubtle`。
- 不在 feature UI 中硬编码颜色。
- 间距使用 `AetherSpace`。
- 圆角使用 `AetherRadius`。
- 字号使用 `AetherType`。
- 图标尺寸使用 `AetherIconSize`。
- 动效使用 `AetherMotion`。
- 高频交互不做装饰性动画。
- 弹窗、菜单、Sheet、Toast 使用 Aether primitives。

## 测试

当前测试覆盖包含：

- `FloatingLyricsProvider` 窗口位置判断与歌词 revision 通知。
- `LibraryProvider` 自然排序与歌单顺序保持。
- 主题 token、动效 token、歌词调色板。
- Aether UI primitives 的基本渲染与交互。
- 主题设置中“暮樱暗粉”选项存在。
- 简单 integration test 入口。

运行测试：

```powershell
flutter test
```

静态分析：

```powershell
flutter analyze
```

## 常见问题

### 启动后为什么是空库？

Aetheria 维护自己的托管音乐库。首次启动只会初始化数据库和目录，不会自动扫描整个电脑或手机。需要手动导入音频文件或目录。

### 导入后原文件会被移动吗？

不会移动原文件。导入会复制音频到托管库的 `files/` 目录，并用 UUID 作为托管文件名。

### 为什么重复导入会失败？

Rust 会对音频文件计算 MD5。如果库中已经存在相同 MD5 的音频版本，会拒绝重复导入。

### 为什么有些歌曲没有封面？

封面来自音频文件内嵌图片。如果音频没有内嵌封面，或封面解析失败，就不会生成 `covers/` 文件。

### 为什么同名 LRC 有时没显示？

导入时会复制源音频旁边的同名 `.lrc` 到托管音频旁边。歌词管理也会尝试读取托管音频同名 `.lrc` 和原始文件名同名 `.lrc`。如果文件名、编码或内容为空，可能不会作为可用候选显示。

### 为什么局域网同步后本机歌曲变少？

当前同步策略是镜像覆盖。以远端为准：

- 远端有、本机没有：下载到本机。
- 远端没有、本机有：本机删除或移动到备份。
- 双方都有但大小或 MD5 不同：用远端替换。

因此同步前要确认目标设备就是你想复制的“主库”。

### 同步失败后会不会把本机库弄坏？

同步覆盖前会创建备份目录。覆盖过程中如果失败，会尝试回滚已安装文件、已移动文件和数据库。但任何文件系统操作都可能受权限、磁盘空间、杀毒软件等外部因素影响，所以重要音乐库仍建议额外备份。

### Android 悬浮歌词不显示怎么办？

检查：

- 是否开启悬浮歌词。
- 是否授予 `SYSTEM_ALERT_WINDOW` 权限。
- 系统是否限制前台服务或后台弹窗。
- 是否有正在播放且已加载歌词的歌曲。

### Android 通知栏没有显示怎么办？

检查：

- 是否授予通知权限。
- 当前是否已经选择歌曲。
- 是否播放过或准备过当前歌曲。
- Android 系统是否关闭了应用通知。

### 为什么修改 Rust API 后 Dart 报错？

需要重新生成 FRB 代码：

```powershell
flutter_rust_bridge_codegen
flutter pub get
```

然后重新构建目标平台。

### 为什么 Android 构建出现 AAR Metadata 或 compileSdk 问题？

根 `android/build.gradle.kts` 中有对子工程 `compileSdkVersion(36)` 的兼容逻辑。先确认这段逻辑没有被删除或改坏。

### 为什么播放设备切换后声音不对？

应用会检测默认输出设备变化并尝试重建播放链路。但系统蓝牙、独占设备、驱动切换可能存在延迟。可以暂停再播放，或重新选择歌曲触发重建。

## 已知边界

- 当前重点支持 Windows 与 Android。
- 局域网同步是整库镜像覆盖，不是双向合并。
- 没有云账户、云曲库或跨互联网同步。
- 在线歌词源依赖第三方接口，稳定性和返回结果不由本项目控制。
- 目前没有完整的发布签名配置，Android release 使用 debug signingConfig。
- `covers/` 不作为同步文件清单的一部分，必要时会从音频重新提取。
- `rust_builder` 包含多平台 FFI 模板，但当前应用主要原生能力集中在 Windows 和 Android。
- 自动化测试覆盖了部分核心逻辑和 UI primitive，但没有覆盖所有复杂桌面/移动交互。

## 维护建议

如果继续开发，建议优先关注：

- Rust API 改动后同步更新 FRB 生成代码。
- 不要绕过 `LibraryProvider` 直接在 UI 里操作数据库。
- 不要绕过 `AudioPlayerProvider` 直接操作播放状态。
- 新 UI 使用 Aether primitives 和 theme tokens。
- 新增同步文件类型时，必须更新 manifest、路径安全校验、备份/回滚逻辑。
- 新增音频格式时，同时检查导入扫描、元数据读取、HTTP MIME、平台导出 MIME。
- 修改悬浮歌词 payload 时，同时检查 Flutter bridge、Android service、Windows runner。
- 修改数据库结构时，在 `schema.rs` 中加入兼容旧库的迁移逻辑。

## 相关文档

建议同时阅读：

- `HANDOVER.md`
- `lib/core/README.md`
- `lib/core/theme/UI_CONTRACT.md`
- `lib/features/README.md`
- `lib/services/README.md`
- `rust_builder/README.md`

## 许可证

本仓库包含 `LICENSE` 文件，许可条款以仓库内许可证文本为准。
