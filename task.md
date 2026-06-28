# Aetheria 开发任务清单

## Phase 1: 环境探测与项目初始化
- [x] 查看 `create-tauri-app` 命令的参数帮助信息
- [x] 在 `d:\python\app` 初始化 Tauri + Vite + React + TS 项目
- [x] 验证 Tauri 基本窗口可正常启动并拉起本地开发服务

## Phase 2: 数据库与存储服务（Rust 后端）
- [x] 在 Cargo.toml 中引入相关依赖 (`rusqlite`, `lofty`, `uuid`, `serde`, `serde_json` 等)
- [x] 编写目录初始化逻辑（自动在程序运行目录下创建 `library/` 与 `library/files/`）
- [x] 编写 SQLite 数据库初始化与建表（Schema）逻辑
- [x] 注册 Tauri 自定义资源传输协议（Asset Protocol），允许前端流式播放托管目录中的音乐

## Phase 3: 核心业务 Command 实现（Rust 后端）
- [x] 编写 `import_song` 接口：复制外部音频，提取元数据，生成 UUID 移入托管文件夹并写入数据库
- [x] 编写 `export_song` 接口：复制托管音频并重命名为原文件名导出到指定外部路径
- [x] 编写 `get_songs` 接口：从数据库中读取并拼装歌曲、音频版本及标签数据
- [x] 编写 `update_version_status` 接口：更新指定音频版本的启用状态或主播放状态
- [x] 编写 `add_tag`、`delete_tag` 以及 `tag_song` 标签关联管理接口

## Phase 4: 现代化 UI 界面开发（前端 React）
- [x] 设计精美的深色毛玻璃（Glassmorphism）布局架构
- [x] 实现标签过滤矩阵（Tag Matrix）交互与动态筛选逻辑
- [x] 实现歌曲主列表（Song List）及双击/点击展示多音频版本抽屉
- [x] 实现底部播放条与 Web Audio API 音谱实时绘制（Waveform Visualizer）
- [x] 实现动态播放队列管理与传统歌单操作支持

## Phase 5: 打包发布与绿色版便携性验证
- [x] 导入各种格式音频进行功能验证
- [x] 进行打包构建（Tauri Build），验证生成的 exe 能否解压即用且数据相对存储
