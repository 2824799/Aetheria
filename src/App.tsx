import { useState, useEffect, useRef } from "react";
import { invoke } from "@tauri-apps/api/core";
import { convertFileSrc } from "@tauri-apps/api/core";
import { 
  Play, Pause, SkipForward, SkipBack, Tag as TagIcon, Plus, Trash2, 
  FolderPlus, Download, Volume2, Search, X, Music, List, CheckSquare, Square, Settings
} from "lucide-react";
import "./App.css";

// 接口定义，与 Rust 后端模型严格匹配
interface Tag {
  id: number;
  name: String;
  color?: string;
  category?: string;
}

interface AudioVersion {
  id: string;
  song_id: string;
  filepath: string;
  original_name: string;
  format?: string;
  bitrate?: number;
  sample_rate?: number;
  duration: number;
  file_size: number;
  is_enabled: boolean;
  is_primary: boolean;
}

interface Song {
  id: string;
  title: string;
  artist?: string;
  album?: string;
  lyrics?: string;
  cover_path?: string;
  rating: number;
  created_at: string;
  versions: AudioVersion[];
  tags: Tag[];
}

const PRESET_COLORS = [
  "#ef4444", "#f97316", "#f59e0b", "#10b981", "#06b6d4", 
  "#3b82f6", "#6366f1", "#8b5cf6", "#d946ef", "#ec4899",
  "#64748b", "#475569"
];

function App() {
  // 数据源状态
  const [songs, setSongs] = useState<Song[]>([]);
  const [tags, setTags] = useState<Tag[]>([]);
  const [libraryPath, setLibraryPath] = useState<string>("");
  
  // 过滤与搜索状态
  const [searchQuery, setSearchQuery] = useState("");
  const [selectedTags, setSelectedTags] = useState<number[]>([]);
  const [filterMode, setFilterMode] = useState<"AND" | "OR">("AND");
  
  // 当前聚焦歌曲及 Tab 状态
  const [activeSong, setActiveSong] = useState<Song | null>(null);
  const [activeTab, setActiveTab] = useState<"versions" | "tags" | "lyrics">("versions");
  
  // 播放器核心状态
  const [playingSong, setPlayingSong] = useState<Song | null>(null);
  const [playingVersion, setPlayingVersion] = useState<AudioVersion | null>(null);
  const [isPlaying, setIsPlaying] = useState(false);
  const [currentTime, setCurrentTime] = useState(0);
  const [duration, setDuration] = useState(0);
  const [volume, setVolume] = useState(0.8);
  
  // UI 模态框及 Loading 状态
  const [isTagModalOpen, setIsTagModalOpen] = useState(false);
  const [isTagManagerOpen, setIsTagManagerOpen] = useState(false);
  const [isSettingsOpen, setIsSettingsOpen] = useState(false);
  const [isImporting, setIsImporting] = useState(false);
  const [importProgress, setImportProgress] = useState("");
  
  // 标签新建属性
  const [newTagName, setNewTagName] = useState("");
  const [newTagColor, setNewTagColor] = useState(PRESET_COLORS[0]);
  const [newTagCategory, setNewTagCategory] = useState("自定义");

  // 主题状态切换逻辑
  const [theme, setTheme] = useState<"dark" | "light" | "pink">(() => {
    return (localStorage.getItem("aetheria-theme") as any) || "dark";
  });

  useEffect(() => {
    document.documentElement.className = "";
    document.documentElement.classList.add(`theme-${theme}`);
    localStorage.setItem("aetheria-theme", theme);
  }, [theme]);

  // 播放器 DOM 引用
  const audioRef = useRef<HTMLAudioElement | null>(null);
  const canvasRef = useRef<HTMLCanvasElement | null>(null);
  const animationRef = useRef<number | null>(null);
  
  // Web Audio API 动效相关
  const audioContextRef = useRef<AudioContext | null>(null);
  const analyserRef = useRef<AnalyserNode | null>(null);
  const sourceRef = useRef<MediaElementAudioSourceNode | null>(null);

  // 初始化加载数据
  const loadLibrary = async () => {
    try {
      const loadedSongs: Song[] = await invoke("get_songs");
      const loadedTags: Tag[] = await invoke("get_tags");
      const libPath: string = await invoke("get_library_path");
      
      setSongs(loadedSongs);
      setTags(loadedTags);
      setLibraryPath(libPath);
    } catch (err) {
      console.error("加载音乐库失败:", err);
    }
  };

  useEffect(() => {
    loadLibrary();
  }, []);

  // 音频初始化与事件监听
  useEffect(() => {
    const audio = new Audio();
    audioRef.current = audio;
    audio.volume = volume;

    const onTimeUpdate = () => setCurrentTime(audio.currentTime);
    const onLoadedMetadata = () => setDuration(audio.duration);
    const onEnded = () => handleNext();

    audio.addEventListener("timeupdate", onTimeUpdate);
    audio.addEventListener("loadedmetadata", onLoadedMetadata);
    audio.addEventListener("ended", onEnded);

    return () => {
      audio.removeEventListener("timeupdate", onTimeUpdate);
      audio.removeEventListener("loadedmetadata", onLoadedMetadata);
      audio.removeEventListener("ended", onEnded);
      audio.pause();
    };
  }, [songs, playingVersion]); // 歌曲库更新时更新下一首逻辑

  // 音波图绘制逻辑
  useEffect(() => {
    if (!canvasRef.current) return;
    const canvas = canvasRef.current;
    const ctx = canvas.getContext("2d");
    if (!ctx) return;

    const draw = () => {
      animationRef.current = requestAnimationFrame(draw);
      ctx.clearRect(0, 0, canvas.width, canvas.height);
      
      if (!analyserRef.current || !isPlaying) {
        // 静止时的波形（绘制微弱的平滑横线波纹）
        ctx.beginPath();
        ctx.strokeStyle = "rgba(99, 102, 241, 0.15)";
        ctx.lineWidth = 2;
        const width = canvas.width;
        const height = canvas.height;
        ctx.moveTo(0, height / 2);
        for (let i = 0; i < width; i++) {
          const y = height / 2 + Math.sin(i * 0.03 + Date.now() * 0.003) * 2;
          ctx.lineTo(i, y);
        }
        ctx.stroke();
        return;
      }

      const analyser = analyserRef.current;
      const bufferLength = analyser.frequencyBinCount;
      const dataArray = new Uint8Array(bufferLength);
      analyser.getByteFrequencyData(dataArray);

      const width = canvas.width;
      const height = canvas.height;
      const barWidth = (width / bufferLength) * 2.5;
      let x = 0;

      for (let i = 0; i < bufferLength; i++) {
        const barHeight = (dataArray[i] / 255) * height * 0.8;
        
        // 渐变填充
        const gradient = ctx.createLinearGradient(0, height, 0, height - barHeight);
        gradient.addColorStop(0, "rgba(99, 102, 241, 0.05)");
        gradient.addColorStop(1, "rgba(168, 85, 247, 0.4)");

        ctx.fillStyle = gradient;
        ctx.fillRect(x, height - barHeight, barWidth - 2, barHeight);

        x += barWidth;
      }
    };

    draw();

    return () => {
      if (animationRef.current) {
        cancelAnimationFrame(animationRef.current);
      }
    };
  }, [isPlaying]);

  // 初始化 Web Audio API 上下文，处理安全策略下的动态激活
  const initAudioAnalyzer = () => {
    if (!audioRef.current || audioContextRef.current) return;

    try {
      const AudioContextClass = window.AudioContext || (window as any).webkitAudioContext;
      const context = new AudioContextClass();
      const analyser = context.createAnalyser();
      analyser.fftSize = 64; // 低频分辨率，以实现流畅的大条形块

      const source = context.createMediaElementSource(audioRef.current);
      source.connect(analyser);
      analyser.connect(context.destination);

      audioContextRef.current = context;
      analyserRef.current = analyser;
      sourceRef.current = source;
    } catch (e) {
      console.warn("无法初始化 Web Audio 分析器:", e);
    }
  };

  // 播放版本控制核心
  const playVersion = (song: Song, version: AudioVersion) => {
    if (!audioRef.current) return;
    
    // 初始化 Web Audio (首次点击激活)
    initAudioAnalyzer();
    if (audioContextRef.current && audioContextRef.current.state === "suspended") {
      audioContextRef.current.resume();
    }

    const isSameVersion = playingVersion && playingVersion.id === version.id;

    if (isSameVersion) {
      if (isPlaying) {
        audioRef.current.pause();
        setIsPlaying(false);
      } else {
        audioRef.current.play().catch(e => console.error(e));
        setIsPlaying(true);
      }
      return;
    }

    // 通过 Tauri asset 协议将本地相对路径的托管音频载入前端
    const absolutePath = libraryPath + "/" + version.filepath;
    const assetUrl = convertFileSrc(absolutePath);

    audioRef.current.src = assetUrl;
    audioRef.current.play()
      .then(() => {
        setPlayingSong(song);
        setPlayingVersion(version);
        setIsPlaying(true);
      })
      .catch((err) => {
        console.error("播放失败:", err);
        alert("无法播放此音频版本，该文件可能损坏或已被移除！");
      });
  };

  // 播放首选/主版本
  const playSong = (song: Song) => {
    // 优先播放 Primary，其次寻找首个启用版本，再次选第一个版本
    let version = song.versions.find(v => v.is_primary && v.is_enabled);
    if (!version) version = song.versions.find(v => v.is_enabled);
    if (!version) version = song.versions[0];

    if (!version) {
      alert("这首歌没有任何可播放的音频版本！");
      return;
    }
    playVersion(song, version);
  };

  // 播放器常规按钮控制
  const handlePlayPause = () => {
    if (!audioRef.current) return;
    if (playingVersion) {
      if (isPlaying) {
        audioRef.current.pause();
        setIsPlaying(false);
      } else {
        audioRef.current.play().catch(e => console.error(e));
        setIsPlaying(true);
      }
    } else if (filteredSongs.length > 0) {
      playSong(filteredSongs[0]);
    }
  };

  // 获取下一首歌曲
  const handleNext = () => {
    if (filteredSongs.length === 0) return;
    let nextIndex = 0;
    if (playingSong) {
      const idx = filteredSongs.findIndex(s => s.id === playingSong.id);
      if (idx !== -1 && idx < filteredSongs.length - 1) {
        nextIndex = idx + 1;
      }
    }
    playSong(filteredSongs[nextIndex]);
  };

  // 获取上一首歌曲
  const handlePrev = () => {
    if (filteredSongs.length === 0) return;
    let prevIndex = filteredSongs.length - 1;
    if (playingSong) {
      const idx = filteredSongs.findIndex(s => s.id === playingSong.id);
      if (idx > 0) {
        prevIndex = idx - 1;
      }
    }
    playSong(filteredSongs[prevIndex]);
  };

  // 拖动播放进度条
  const handleSeek = (e: React.MouseEvent<HTMLDivElement>) => {
    if (!audioRef.current || duration === 0) return;
    const rect = e.currentTarget.getBoundingClientRect();
    const x = e.clientX - rect.left;
    const pct = x / rect.width;
    audioRef.current.currentTime = pct * duration;
    setCurrentTime(pct * duration);
  };

  // 控制音量
  const handleVolumeChange = (e: React.MouseEvent<HTMLDivElement>) => {
    if (!audioRef.current) return;
    const rect = e.currentTarget.getBoundingClientRect();
    const x = e.clientX - rect.left;
    const pct = Math.max(0, Math.min(1, x / rect.width));
    audioRef.current.volume = pct;
    setVolume(pct);
  };

  // 歌曲导入逻辑
  const handleImportSongs = async () => {
    try {
      const paths: string[] = await invoke("select_audio_files");
      if (paths.length === 0) return;

      setIsImporting(true);
      for (let i = 0; i < paths.length; i++) {
        const path = paths[i];
        const filename = path.replace(/^.*[\\/]/, "");
        setImportProgress(`正在导入 (${i + 1}/${paths.length}): ${filename}`);
        await invoke("import_song", { filepath: path });
      }
      
      await loadLibrary();
      // 如果有正选中的歌，更新它的引用以载入最新导入的版本
      if (activeSong) {
        const updatedSongs: Song[] = await invoke("get_songs");
        const found = updatedSongs.find(s => s.id === activeSong.id);
        if (found) setActiveSong(found);
      }
    } catch (err) {
      alert("导入音频失败: " + err);
    } finally {
      setIsImporting(false);
      setImportProgress("");
    }
  };

  // 版本导出逻辑
  const handleExportVersion = async (version: AudioVersion) => {
    try {
      const dir: string | null = await invoke("select_export_directory");
      if (!dir) return;

      setImportProgress("正在导出音频...");
      setIsImporting(true);
      const destPath = await invoke("export_song", { versionId: version.id, exportDir: dir });
      alert(`音频成功导出到:\n${destPath}`);
    } catch (err) {
      alert("导出失败: " + err);
    } finally {
      setIsImporting(false);
      setImportProgress("");
    }
  };

  // 版本启用与主播放状态控制
  const handleVersionStatusChange = async (versionId: string, enabled: boolean, primary: boolean) => {
    try {
      await invoke("update_version_status", { versionId, isEnabled: enabled, isPrimary: primary });
      // 重新载入数据并同步视图
      const loadedSongs: Song[] = await invoke("get_songs");
      setSongs(loadedSongs);
      
      if (activeSong) {
        const found = loadedSongs.find(s => s.id === activeSong.id);
        if (found) setActiveSong(found);
      }

      // 如果当前播放的版本被修改，同步状态
      if (playingVersion && playingVersion.id === versionId) {
        const foundVer = loadedSongs.flatMap(s => s.versions).find(v => v.id === versionId);
        if (foundVer) setPlayingVersion(foundVer);
      }
    } catch (err) {
      console.error(err);
    }
  };

  // 创建自定义标签
  const handleCreateTag = async () => {
    if (!newTagName.trim()) return;
    try {
      await invoke("add_tag", { 
        name: newTagName, 
        color: newTagColor, 
        category: newTagCategory 
      });
      setNewTagName("");
      setIsTagModalOpen(false);
      await loadLibrary();
    } catch (err) {
      alert("创建标签失败: " + err);
    }
  };

  // 删除自定义标签
  const handleDeleteTag = async (tagId: number) => {
    if (!confirm("您确定要永久删除这个标签吗？这将同时解除它与所有关联歌曲的绑定状态。")) return;
    try {
      await invoke("delete_tag", { tagId });
      setSelectedTags(selectedTags.filter(id => id !== tagId));
      await loadLibrary();
    } catch (err) {
      alert("删除标签失败: " + err);
    }
  };

  // 绑定与解绑标签
  const toggleSongTag = async (songId: string, tagId: number, isBound: boolean) => {
    try {
      await invoke("tag_song", { songId, tagId, bind: !isBound });
      
      // 更新库并刷新活跃歌曲引用
      const loadedSongs: Song[] = await invoke("get_songs");
      setSongs(loadedSongs);
      if (activeSong && activeSong.id === songId) {
        const found = loadedSongs.find(s => s.id === songId);
        if (found) setActiveSong(found);
      }
    } catch (err) {
      console.error(err);
    }
  };

  // 标签多维条件动态过滤引擎
  const filteredSongs = songs.filter(song => {
    // 1. 搜索关键词匹配
    const matchesSearch = searchQuery === "" || 
      song.title.toLowerCase().includes(searchQuery.toLowerCase()) ||
      (song.artist && song.artist.toLowerCase().includes(searchQuery.toLowerCase())) ||
      (song.album && song.album.toLowerCase().includes(searchQuery.toLowerCase()));

    if (!matchesSearch) return false;

    // 2. 标签池过滤
    if (selectedTags.length === 0) return true;

    if (filterMode === "AND") {
      // 必须包含全部选中的标签
      return selectedTags.every(tagId => song.tags.some(t => t.id === tagId));
    } else {
      // 包含任意一个选中的标签
      return selectedTags.some(tagId => song.tags.some(t => t.id === tagId));
    }
  });

  // 辅助转换时长格式
  const formatTime = (secs: number) => {
    if (isNaN(secs)) return "0:00";
    const m = Math.floor(secs / 60);
    const s = Math.floor(secs % 60);
    return `${m}:${s < 10 ? "0" : ""}${s}`;
  };

  return (
    <div className="app-container">
      {/* 炫酷磨砂发光斑点 */}
      <div className="ambient-glow glow-1"></div>
      <div className="ambient-glow glow-2"></div>

      {/* 左侧边栏：Aetheria 导航 */}
      <div className="glass-panel sidebar">
        <div className="logo-section">
          <div className="logo-icon">
            <Music size={24} color="white" />
          </div>
          <span className="logo-text">AETHERIA</span>
        </div>

        <div className="menu-group">
          <div className="menu-title">导航中心</div>
          <div className="menu-item active">
            <List size={18} />
            全部歌曲 ({songs.length})
          </div>
          <div className="menu-item" onClick={() => setIsTagManagerOpen(true)}>
            <TagIcon size={18} />
            标签管理器
          </div>
        </div>

        <div className="sidebar-bottom">
          <div className="menu-item" onClick={() => setIsSettingsOpen(true)}>
            <Settings size={18} />
            系统设置
          </div>
          <button className="import-btn" onClick={handleImportSongs}>
            <FolderPlus size={18} />
            导入本地音乐
          </button>
        </div>
      </div>

      {/* 中间栏：歌曲列表与标签过滤池 */}
      <div className="glass-panel main-content">
        <div className="header-row">
          <h2 style={{ margin: 0, fontWeight: 700 }}>曲库大厅</h2>
          <div className="search-container">
            <Search className="search-icon" size={18} />
            <input 
              type="text" 
              placeholder="搜索歌曲、歌手、专辑..." 
              className="search-input"
              value={searchQuery}
              onChange={e => setSearchQuery(e.target.value)}
            />
          </div>
        </div>

        {/* 标签磁贴筛选池 */}
        <div className="tag-matrix-panel">
          <div className="tag-matrix-header">
            <span className="tag-matrix-title">
              <TagIcon size={16} /> 标签多维过滤器
            </span>
            <div className="filter-toggle-container">
              <div 
                className={`filter-toggle-btn ${filterMode === "AND" ? "active" : ""}`}
                onClick={() => setFilterMode("AND")}
                title="歌曲需满足全部选中的标签"
              >
                交集 (AND)
              </div>
              <div 
                className={`filter-toggle-btn ${filterMode === "OR" ? "active" : ""}`}
                onClick={() => setFilterMode("OR")}
                title="歌曲只需满足任意一个选中的标签"
              >
                并集 (OR)
              </div>
            </div>
          </div>
          
          <div className="tag-pool">
            {tags.map(tag => {
              const isSelected = selectedTags.includes(tag.id);
              return (
                <div 
                  key={tag.id}
                  className={`tag-chip ${isSelected ? "selected" : ""}`}
                  style={{ color: tag.color || "#cbd5e1" }}
                  onClick={() => {
                    if (isSelected) {
                      setSelectedTags(selectedTags.filter(id => id !== tag.id));
                    } else {
                      setSelectedTags([...selectedTags, tag.id]);
                    }
                  }}
                >
                  <span style={{ display: 'inline-block', width: 8, height: 8, borderRadius: '50%', backgroundColor: tag.color || "#cbd5e1" }}></span>
                  {tag.name}
                </div>
              );
            })}
            
            <div className="tag-chip" style={{ color: "#a855f7", borderStyle: "dashed" }} onClick={() => setIsTagModalOpen(true)}>
              <Plus size={14} /> 新建标签
            </div>
          </div>
        </div>

        {/* 歌曲信息列表 */}
        <div className="song-list-container">
          <table className="song-table">
            <thead>
              <tr>
                <th style={{ width: "40px" }}></th>
                <th>歌曲名称</th>
                <th>歌手</th>
                <th>绑定的自定义标签</th>
                <th>版本数</th>
                <th>默认音质</th>
              </tr>
            </thead>
            <tbody>
              {filteredSongs.map(song => {
                // 找出用于显示的默认音质格式
                let primaryVer = song.versions.find(v => v.is_primary && v.is_enabled);
                if (!primaryVer) primaryVer = song.versions.find(v => v.is_enabled) || song.versions[0];
                const activeFormat = primaryVer ? primaryVer.format?.toUpperCase() : "无";
                const isThisPlaying = playingSong?.id === song.id;

                return (
                  <tr 
                    key={song.id} 
                    className={`song-row ${activeSong?.id === song.id ? "active" : ""} ${isThisPlaying ? "playing" : ""}`}
                    onClick={() => setActiveSong(song)}
                    onDoubleClick={() => playSong(song)}
                  >
                    <td>
                      <div className="play-row-btn" onClick={(e) => { e.stopPropagation(); playSong(song); }}>
                        {isThisPlaying && isPlaying ? <Pause size={16} /> : <Play size={16} />}
                      </div>
                    </td>
                    <td>
                      <div className="song-title-cell">
                        <span className="song-title-text">{song.title}</span>
                      </div>
                    </td>
                    <td><span className="song-artist-text">{song.artist || "未知歌手"}</span></td>
                    <td>
                      <div className="badge-container">
                        {song.tags.slice(0, 3).map(tag => (
                          <span 
                            key={tag.id} 
                            className="tag-pill"
                            style={{ color: tag.color, border: `1px solid ${tag.color}33`, backgroundColor: `${tag.color}11` }}
                          >
                            {tag.name}
                          </span>
                        ))}
                        {song.tags.length > 3 && <span className="tag-pill" style={{ color: "#64748b" }}>+{song.tags.length - 3}</span>}
                      </div>
                    </td>
                    <td style={{ color: "#94a3b8", fontWeight: 600 }}>{song.versions.length}</td>
                    <td>
                      {activeFormat && (
                        <span className={`format-badge ${activeFormat.toLowerCase()}`}>
                          {activeFormat}
                        </span>
                      )}
                    </td>
                  </tr>
                );
              })}
              
              {filteredSongs.length === 0 && (
                <tr>
                  <td colSpan={6} style={{ textAlign: "center", padding: "40px", color: "#64748b" }}>
                    没有找到符合条件的歌曲，请导入或调整过滤器
                  </td>
                </tr>
              )}
            </tbody>
          </table>
        </div>
      </div>

      {/* 右侧面板：当前选中歌曲的详细属性与多版本版本挂载 */}
      <div className="glass-panel detail-pane">
        {activeSong ? (
          <>
            <div className="detail-header">
              <div className="cover-container">
                <div className="cover-glow"></div>
                <Music size={52} color="rgba(255,255,255,0.7)" />
              </div>
              <div className="detail-title">{activeSong.title}</div>
              <div className="detail-artist">{activeSong.artist || "未知歌手"}</div>
            </div>

            <div className="detail-tabs-container">
              <div 
                className={`detail-tab ${activeTab === "versions" ? "active" : ""}`}
                onClick={() => setActiveTab("versions")}
              >
                音频版本 ({activeSong.versions.length})
              </div>
              <div 
                className={`detail-tab ${activeTab === "tags" ? "active" : ""}`}
                onClick={() => setActiveTab("tags")}
              >
                标签绑定 ({activeSong.tags.length})
              </div>
              <div 
                className={`detail-tab ${activeTab === "lyrics" ? "active" : ""}`}
                onClick={() => setActiveTab("lyrics")}
              >
                歌词与信息
              </div>
            </div>

            <div className="detail-section">
              {/* Tab 1: 音频多版本挂载面板 */}
              {activeTab === "versions" && (
                <div style={{ display: "flex", flexDirection: "column", gap: "12px" }}>
                  {activeSong.versions.map(ver => {
                    const isVerPlaying = playingVersion?.id === ver.id;
                    const formatText = ver.format?.toUpperCase();
                    const sizeMB = (ver.file_size / (1024 * 1024)).toFixed(2) + " MB";
                    const bitrateText = ver.bitrate ? `${ver.bitrate}kbps` : "未知码率";

                    return (
                      <div key={ver.id} className="version-item">
                        <div className="version-row">
                          <div className="version-meta">
                            <span className="version-filename" title={ver.original_name}>{ver.original_name}</span>
                            <span className="version-specs">
                              {formatText} • {bitrateText} • {sizeMB} • {formatTime(ver.duration)}
                            </span>
                          </div>
                          
                          <button 
                            className="ctrl-btn"
                            style={{ color: isVerPlaying && isPlaying ? "#10b981" : "#6366f1" }}
                            onClick={() => playVersion(activeSong, ver)}
                          >
                            {isVerPlaying && isPlaying ? <Pause size={18} /> : <Play size={18} />}
                          </button>
                        </div>

                        <div className="version-row" style={{ marginTop: 4 }}>
                          <label className="checkbox-label">
                            <input 
                              type="checkbox" 
                              checked={ver.is_enabled}
                              onChange={(e) => handleVersionStatusChange(ver.id, e.target.checked, ver.is_primary)}
                            />
                            启用该版本
                          </label>

                          <label className="radio-label">
                            <input 
                              type="radio" 
                              name={`primary-version-${activeSong.id}`}
                              checked={ver.is_primary}
                              onChange={() => handleVersionStatusChange(ver.id, ver.is_enabled, true)}
                            />
                            设为主播放版本
                          </label>
                        </div>

                        <div className="version-actions">
                          <button className="action-btn-sm" onClick={() => handleExportVersion(ver)}>
                            <Download size={12} /> 导出还原音频
                          </button>
                        </div>
                      </div>
                    );
                  })}
                  
                  <div style={{ fontSize: "0.8rem", color: "#64748b", padding: "4px 8px" }}>
                    💡 绑定多个版本时，软件会在您双击歌曲时默认播放标为“主版本”的音频。
                  </div>
                </div>
              )}

              {/* Tab 2: 标签绑定面板 */}
              {activeTab === "tags" && (
                <div className="tag-list-checkboxes">
                  {tags.map(tag => {
                    const isBound = activeSong.tags.some(t => t.id === tag.id);
                    return (
                      <div 
                        key={tag.id} 
                        className="tag-bind-item"
                        style={{ color: tag.color }}
                        onClick={() => toggleSongTag(activeSong.id, tag.id, isBound)}
                      >
                        <span style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
                          <span style={{ display: 'inline-block', width: 8, height: 8, borderRadius: '50%', backgroundColor: tag.color }}></span>
                          {tag.name}
                        </span>
                        {isBound ? <CheckSquare size={16} /> : <Square size={16} />}
                      </div>
                    );
                  })}
                </div>
              )}

              {/* Tab 3: 歌词与信息 */}
              {activeTab === "lyrics" && (
                <div className="lyrics-container">
                  <div style={{ marginBottom: "16px", paddingBottom: "16px", borderBottom: "1px solid rgba(255,255,255,0.04)", fontSize: "0.85rem", color: "#64748b", textAlign: "left" }}>
                    <strong>所属专辑</strong>: {activeSong.album || "未知专辑"}<br />
                    <strong>生成日期</strong>: {new Date(activeSong.created_at).toLocaleDateString()}
                  </div>
                  {activeSong.lyrics ? activeSong.lyrics : "暂无歌词信息，您可以通过导入带有歌词元数据的音频自动识别。"}
                </div>
              )}
            </div>
          </>
        ) : (
          <div className="empty-detail">
            <Music size={48} />
            <div>
              <strong>未选择歌曲</strong>
              <p style={{ margin: "4px 0 0 0", fontSize: "0.85rem" }}>在左侧选择一首歌曲以管理它的多个音频文件和属性。</p>
            </div>
          </div>
        )}
      </div>

      {/* 底部播放条 */}
      <div className="glass-panel playbar">
        {/* 音频波形实时画布 */}
        <canvas ref={canvasRef} className="visualizer-canvas" width={800} height={40} />

        {/* 歌曲基础信息 */}
        <div className="playbar-track-info">
          <div className="playbar-cover">
            <Music size={24} color="rgba(255,255,255,0.6)" />
          </div>
          {playingSong && playingVersion ? (
            <div className="playbar-meta">
              <div className="playbar-title" title={playingSong.title}>{playingSong.title}</div>
              <div className="playbar-artist">
                {playingSong.artist || "未知歌手"} • 
                <span style={{ marginLeft: 6 }} className="format-badge">{playingVersion.format?.toUpperCase()}</span>
              </div>
            </div>
          ) : (
            <div className="playbar-meta">
              <div className="playbar-title">未开始播放</div>
              <div className="playbar-artist">Aetheria 音乐库</div>
            </div>
          )}
        </div>

        {/* 播放控制与进度条 */}
        <div className="playbar-controls">
          <div className="control-buttons">
            <button className="ctrl-btn" onClick={handlePrev} title="上一首">
              <SkipBack size={20} />
            </button>
            <button className="ctrl-btn play-pause" onClick={handlePlayPause}>
              {isPlaying ? <Pause size={20} fill="currentColor" /> : <Play size={20} fill="currentColor" />}
            </button>
            <button className="ctrl-btn" onClick={handleNext} title="下一首">
              <SkipForward size={20} />
            </button>
          </div>

          <div className="progress-bar-container">
            <span className="time-stamp">{formatTime(currentTime)}</span>
            <div className="slider-track" onClick={handleSeek}>
              <div 
                className="slider-fill" 
                style={{ width: `${duration > 0 ? (currentTime / duration) * 100 : 0}%` }}
              ></div>
              <div 
                className="slider-handle" 
                style={{ left: `${duration > 0 ? (currentTime / duration) * 100 : 0}%` }}
              ></div>
            </div>
            <span className="time-stamp">{formatTime(duration)}</span>
          </div>
        </div>

        {/* 音量控制 */}
        <div className="playbar-volume">
          <Volume2 size={16} color="#64748b" />
          <div className="volume-slider" onClick={handleVolumeChange}>
            <div className="slider-fill" style={{ width: `${volume * 100}%` }}></div>
            <div className="slider-handle" style={{ left: `${volume * 100}%` }}></div>
          </div>
        </div>
      </div>

      {/* Modal 1: 新建自定义标签弹框 */}
      {isTagModalOpen && (
        <div className="modal-overlay" onClick={() => setIsTagModalOpen(false)}>
          <div className="modal-content" onClick={e => e.stopPropagation()}>
            <div className="modal-header">
              <span className="modal-title">新建标签</span>
              <button className="ctrl-btn" onClick={() => setIsTagModalOpen(false)}><X size={18} /></button>
            </div>
            
            <div className="form-group">
              <label>标签名称</label>
              <input 
                type="text" 
                className="text-input" 
                placeholder="请输入标签名..." 
                value={newTagName}
                onChange={e => setNewTagName(e.target.value)}
              />
            </div>

            <div className="form-group">
              <label>标签分类</label>
              <select className="text-input" value={newTagCategory} onChange={e => setNewTagCategory(e.target.value)}>
                <option value="语言">语言</option>
                <option value="流派">流派</option>
                <option value="情绪">情绪</option>
                <option value="自定义">自定义</option>
              </select>
            </div>

            <div className="form-group">
              <label>标签背景颜色</label>
              <div className="color-picker-grid">
                {PRESET_COLORS.map(color => (
                  <div 
                    key={color}
                    className={`color-option ${newTagColor === color ? "selected" : ""}`}
                    style={{ backgroundColor: color }}
                    onClick={() => setNewTagColor(color)}
                  ></div>
                ))}
              </div>
            </div>

            <div className="modal-footer">
              <button className="btn-secondary" onClick={() => setIsTagModalOpen(false)}>取消</button>
              <button className="btn-primary" onClick={handleCreateTag}>创建</button>
            </div>
          </div>
        </div>
      )}

      {/* Modal 2: 标签管理器弹框 */}
      {isTagManagerOpen && (
        <div className="modal-overlay" onClick={() => setIsTagManagerOpen(false)}>
          <div className="modal-content" onClick={e => e.stopPropagation()}>
            <div className="modal-header">
              <span className="modal-title">管理已有标签</span>
              <button className="ctrl-btn" onClick={() => setIsTagManagerOpen(false)}><X size={18} /></button>
            </div>
            
            <div className="tag-list-manager">
              {tags.map(tag => (
                <div key={tag.id} className="manager-tag-row">
                  <span style={{ color: tag.color, fontWeight: 600 }}>
                    [{tag.category || "自定义"}] {tag.name}
                  </span>
                  <button className="ctrl-btn" style={{ color: "#ef4444" }} onClick={() => handleDeleteTag(tag.id)}>
                    <Trash2 size={16} />
                  </button>
                </div>
              ))}
              {tags.length === 0 && (
                <div style={{ color: "#64748b", textAlign: "center", padding: "12px" }}>暂无标签</div>
              )}
            </div>

            <div className="modal-footer">
              <button className="btn-secondary" style={{ width: "100%" }} onClick={() => setIsTagManagerOpen(false)}>关闭</button>
            </div>
          </div>
        </div>
      )}

      {/* Modal 3: 系统设置弹框 */}
      {isSettingsOpen && (
        <div className="modal-overlay" onClick={() => setIsSettingsOpen(false)}>
          <div className="modal-content" onClick={e => e.stopPropagation()}>
            <div className="modal-header">
              <span className="modal-title" style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
                <Settings size={20} /> 系统设置
              </span>
              <button className="ctrl-btn" onClick={() => setIsSettingsOpen(false)}><X size={18} /></button>
            </div>
            
            <div className="form-group">
              <label>切换界面主题风格</label>
              <div className="theme-selector-grid">
                <div 
                  className={`theme-card ${theme === "dark" ? "active" : ""}`}
                  onClick={() => setTheme("dark")}
                >
                  <div className="theme-preview dark"></div>
                  <div className="theme-name">深邃暗色</div>
                </div>
                <div 
                  className={`theme-card ${theme === "light" ? "active" : ""}`}
                  onClick={() => setTheme("light")}
                >
                  <div className="theme-preview light"></div>
                  <div className="theme-name">纯净亮色</div>
                </div>
                <div 
                  className={`theme-card ${theme === "pink" ? "active" : ""}`}
                  onClick={() => setTheme("pink")}
                >
                  <div className="theme-preview pink"></div>
                  <div className="theme-name">温润粉樱</div>
                </div>
              </div>
            </div>

            <div className="form-group" style={{ marginTop: '8px' }}>
              <label>本地托管音乐库路径</label>
              <div 
                className="text-input" 
                style={{ fontSize: '0.8rem', wordBreak: 'break-all', opacity: 0.8, background: 'var(--bg-hover)' }}
              >
                {libraryPath}
              </div>
            </div>

            <div className="form-group">
              <label>关于 Aetheria</label>
              <div style={{ fontSize: '0.8rem', opacity: 0.7, lineHeight: 1.5 }}>
                软件版本: v0.1.0 (Portable)<br />
                数据引擎: SQLite 3 & Symphonia/Lofty (Rust)<br />
                界面渲染: React 19 & Tauri 2.0
              </div>
            </div>

            <div className="modal-footer">
              <button className="btn-primary" style={{ width: "100%" }} onClick={() => setIsSettingsOpen(false)}>保存并关闭</button>
            </div>
          </div>
        </div>
      )}

      {/* Loader: 导入音频数据遮罩 */}
      {isImporting && (
        <div className="loader-overlay">
          <div className="spinner"></div>
          <span style={{ fontSize: "1.1rem", fontWeight: 600 }}>{importProgress}</span>
        </div>
      )}
    </div>
  );
}

export default App;
