# SonicVault (高性能多版本本地音乐管理软件)

SonicVault 是一款基于 **Tauri 2.0 (Rust) + SQLite + Vite + React (TypeScript)** 开发的高性能、现代化本地音乐播放与管理软件。

## 核心设计理念

- **歌曲对象核心 (Song-Object Centric)**：与传统播放器“一个文件即一首歌”不同，SonicVault 将“歌曲实体”与“音频文件”解耦。一首歌可以关联多个音频版本（如 FLAC 无损版、MP3 版、Live 版等），并在 UI 中自由启用或切换。
- **全局多维标签池 (Tag Matrix)**：提供高度自定义的全局标签系统，支持多标签的 AND/OR 复合条件过滤，实现超越传统歌单的音乐管理方式。
- **免安装绿色便携 (Portable)**：软件内所有的数据库与导入的音频文件均保存在软件根目录下的 `library/` 中，使用相对路径管理，解压即用，支持整体打包移动。

## 技术栈

- **桌面客户端框架**：Tauri 2.0 (Rust)
- **前端框架**：Vite + React + TypeScript + TailwindCSS
- **本地数据库**：SQLite
- **音频处理**：HTML5 Audio / Web Audio API (前端流式解析与可视化) + Rust (后台文件管理)

## 数据托管说明 (方案 B)

当音频文件导入到 SonicVault 中时，文件会被**复制并托管**到软件目录下的 `library/files/` 中，并以 UUID 进行混淆存储，防止误删。软件提供统一的导入与导出机制。
