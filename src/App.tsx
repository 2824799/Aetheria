import { useState, useEffect, useRef, useMemo } from "react";
import { invoke } from "@tauri-apps/api/core";
import { convertFileSrc } from "@tauri-apps/api/core";
import { 
  Play, Pause, SkipForward, SkipBack, Tag as TagIcon, Plus, Trash2, 
  FolderPlus, Download, Volume2, Search, X, Music, List, CheckSquare, Square, Settings,
  ChevronDown, ChevronRight, Repeat, Repeat1, Shuffle, LayoutList, FileAudio
} from "lucide-react";
import "./App.css";

interface AudioVersion {
  id: string;
  filepath: string;
  filename: string;
  format: string;
  bitrate?: number;
  duration?: number;
  filesize?: number;
  is_primary: boolean;
  is_active: boolean;
}

interface Tag {
  id: number;
  name: string;
  color: string;
  category?: string;
  created_at: string;
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
  const [isTagsExpanded, setIsTagsExpanded] = useState(true);
  
  // 当前聚焦歌曲及 Tab 状态
  const [activeSong, setActiveSong] = useState<Song | null>(null);
  const [isDetailOpen, setIsDetailOpen] = useState(false);
  const [activeTab, setActiveTab] = useState<"versions" | "tags" | "lyrics">("versions");
  
  // 播放器核心状态
  const [playingSong, setPlayingSong] = useState<Song | null>(null);
  const [playingVersion, setPlayingVersion] = useState<AudioVersion | null>(null);
  const [isPlaying, setIsPlaying] = useState(false);
  const [currentTime, setCurrentTime] = useState(0);
  const [duration, setDuration] = useState(0);
  const [volume, setVolume] = useState(0.8);
  const [playMode, setPlayMode] = useState<"list" | "single" | "shuffle">("list");
  
  // UI 模态框及 Loading 状态
  const [isTagManagerOpen, setIsTagManagerOpen] = useState(false);
  const [isSettingsOpen, setIsSettingsOpen] = useState(false);
  const [isLyricsOverlayOpen, setIsLyricsOverlayOpen] = useState(false);
  const [isImporting, setIsImporting] = useState(false);
  const [importProgress, setImportProgress] = useState("");
  
  // 标签新建属性
  const [newTagName, setNewTagName] = useState("");
  const [newTagColor, setNewTagColor] = useState(PRESET_COLORS[0]);
  const newTagCategory = "自定义";

  // 主题状态切换逻辑
  const [theme, setTheme] = useState<"dark" | "light" | "pink">(() => {
    return (localStorage.getItem("aetheria-theme") as any) || "dark";
  });

  // 播放器 DOM 引用
  const audioRef = useRef<HTMLAudioElement | null>(null);
  const canvasRef = useRef<HTMLCanvasElement | null>(null);
  const animationRef = useRef<number | null>(null);
  const activeLineRef = useRef<HTMLDivElement | null>(null);
  
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

  // 音频初始化与事件监听 (仅在挂载时运行一次，保持 Audio 实例唯一性)
  useEffect(() => {
    const audio = new Audio();
    audio.crossOrigin = "anonymous"; // 解决 Web Audio 跨域安全机制导致的静音输出 Bug
    audioRef.current = audio;
    audio.volume = volume;

    const onTimeUpdate = () => setCurrentTime(audio.currentTime);
    const onLoadedMetadata = () => setDuration(audio.duration);
    const onEnded = () => handleEnded();

    audio.addEventListener("timeupdate", onTimeUpdate);
    audio.addEventListener("loadedmetadata", onLoadedMetadata);
    audio.addEventListener("ended", onEnded);

    return () => {
      audio.removeEventListener("timeupdate", onTimeUpdate);
      audio.removeEventListener("loadedmetadata", onLoadedMetadata);
      audio.removeEventListener("ended", onEnded);
      audio.pause();
    };
  }, []);

  // 同步音量状态到播放器 DOM
  useEffect(() => {
    if (audioRef.current) {
      audioRef.current.volume = volume;
    }
  }, [volume]);

  // 全局主题变化
  useEffect(() => {
    document.documentElement.className = "";
    document.documentElement.classList.add(`theme-${theme}`);
    localStorage.setItem("aetheria-theme", theme);
  }, [theme]);

  // 解析并高亮滚动当前播放歌词
  const lyricsLines = useMemo(() => {
    if (playingSong && playingSong.lyrics) {
      return playingSong.lyrics.split("\n").map(l => l.trim()).filter(l => l.length > 0);
    }
    return ["暂无歌词内容"];
  }, [playingSong]);

  const activeLyricsIndex = useMemo(() => {
    if (!playingSong || !playingSong.lyrics || duration === 0) return -1;
    const index = Math.floor((currentTime / duration) * lyricsLines.length);
    return Math.min(index, lyricsLines.length - 1);
  }, [currentTime, duration, lyricsLines]);

  // 歌词行自动滚动进中央
  useEffect(() => {
    if (activeLineRef.current) {
      activeLineRef.current.scrollIntoView({
        behavior: "smooth",
        block: "center"
      });
    }
  }, [activeLyricsIndex]);

  // 音频柱状图绘制逻辑
  useEffect(() => {
    if (!canvasRef.current) return;
    const canvas = canvasRef.current;
    const ctx = canvas.getContext("2d");
    if (!ctx) return;
    
    let bufferLength = 0;
    let dataArray = new Uint8Array(0);
    if (analyserRef.current) {
      bufferLength = analyserRef.current.frequencyBinCount;
      dataArray = new Uint8Array(bufferLength);
    }

    const draw = () => {
      animationRef.current = requestAnimationFrame(draw);
      ctx.clearRect(0, 0, canvas.width, canvas.height);
      
      if (!analyserRef.current || !isPlaying) {
        // 静止时的波纹横线
        ctx.beginPath();
        ctx.strokeStyle = theme === "light" ? "rgba(37, 99, 235, 0.15)" : "rgba(99, 102, 241, 0.18)";
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

      analyserRef.current.getByteFrequencyData(dataArray);
      
      const width = canvas.width;
      const height = canvas.height;
      const barWidth = (width / bufferLength) * 2.5;
      let x = 0;

      for (let i = 0; i < bufferLength; i++) {
        const barHeight = (dataArray[i] / 255) * height * 0.85;
        
        ctx.fillStyle = theme === "pink" 
          ? `rgba(244, 63, 94, ${0.15 + barHeight / height})`
          : theme === "light"
          ? `rgba(37, 99, 235, ${0.15 + barHeight / height})`
          : `rgba(59, 130, 246, ${0.15 + barHeight / height})`;
          
        ctx.fillRect(x, height - barHeight, barWidth - 1, barHeight);
        x += barWidth;
      }
    };

    draw();

    return () => {
      if (animationRef.current) {
        cancelAnimationFrame(animationRef.current);
      }
    };
  }, [isPlaying, theme]);

  // 初始化 Web Audio API 上下文，处理安全策略下的动态激活
  const initAudioAnalyzer = () => {
    if (!audioRef.current || audioContextRef.current) return;

    try {
      const AudioContextClass = window.AudioContext || (window as any).webkitAudioContext;
      const context = new AudioContextClass();
      const analyser = context.createAnalyser();
      analyser.fftSize = 64; 

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

  // 1. 导入音频文件逻辑（调用系统目录选取）
  const handleImportSongs = async () => {
    setIsImporting(true);
    setImportProgress("正在选择文件夹...");
    try {
      const selectedDir = await invoke<string | null>("select_directory");
      if (!selectedDir) {
        setIsImporting(false);
        return;
      }

      setImportProgress("正在扫描并解析音频元数据...");
      // 调用后台分析导入
      const count = await invoke<number>("import_audio_files", { dirPath: selectedDir });
      setImportProgress(`成功导入了 ${count} 首歌曲！`);
      
      setTimeout(() => {
        setIsImporting(false);
        loadLibrary();
      }, 1500);
    } catch (err) {
      console.error(err);
      setImportProgress("导入出错: " + err);
      setTimeout(() => setIsImporting(false), 3000);
    }
  };

  // 2. 标签管理逻辑
  const handleCreateTag = async () => {
    if (!newTagName.trim()) return;
    try {
      await invoke("add_tag", { 
        name: newTagName.trim(), 
        color: newTagColor, 
        category: newTagCategory 
      });
      setNewTagName("");
      loadLibrary();
    } catch (err) {
      console.error("创建标签失败:", err);
    }
  };

  const handleDeleteTag = async (tagId: number) => {
    try {
      await invoke("delete_tag", { tagId });
      loadLibrary();
    } catch (err) {
      console.error("删除标签失败:", err);
    }
  };

  const handleBindTag = async (songId: string, tagId: number) => {
    try {
      await invoke("tag_song", { songId, tagId });
      loadLibrary();
      // 同步更新聚焦状态
      if (activeSong && activeSong.id === songId) {
        const updated = songs.find(s => s.id === songId);
        if (updated) setActiveSong(updated);
      }
    } catch (err) {
      console.error(err);
    }
  };

  const handleUnbindTag = async (songId: string, tagId: number) => {
    try {
      await invoke("untag_song", { songId, tagId });
      loadLibrary();
      // 同步更新聚焦状态
      if (activeSong && activeSong.id === songId) {
        const updated = songs.find(s => s.id === songId);
        if (updated) setActiveSong(updated);
      }
    } catch (err) {
      console.error(err);
    }
  };

  // 3. 版本精细化控制逻辑
  const handleSetPrimaryVersion = async (versionId: string) => {
    if (!activeSong) return;
    try {
      await invoke("set_primary_version", { songId: activeSong.id, versionId });
      await loadLibrary();
      
      const updated = songs.find(s => s.id === activeSong.id);
      if (updated) {
        setActiveSong(updated);
        // 如果当前播放的就是这首歌，更新播放版本
        if (playingSong && playingSong.id === activeSong.id) {
          const newPrimary = updated.versions.find(v => v.id === versionId);
          if (newPrimary) setPlayingVersion(newPrimary);
        }
      }
    } catch (err) {
      console.error(err);
    }
  };

  const handleToggleVersionStatus = async (versionId: string, active: boolean) => {
    if (!activeSong) return;
    try {
      await invoke("update_version_status", { versionId, active });
      await loadLibrary();
      const updated = songs.find(s => s.id === activeSong.id);
      if (updated) setActiveSong(updated);
    } catch (err) {
      console.error(err);
    }
  };

  const handleExportVersion = async (versionId: string) => {
    try {
      const destPath = await invoke<string | null>("select_save_file");
      if (!destPath) return;
      await invoke("export_audio_file", { versionId, destPath });
      alert("音频导出还原成功！");
    } catch (err) {
      alert("导出失败: " + err);
    }
  };

  // 4. 播放器核心触发事件
  const handlePlaySong = (song: Song) => {
    // 寻找主版本，若无则挑选第一个启用的版本
    let targetVersion = song.versions.find(v => v.is_primary && v.is_active);
    if (!targetVersion) {
      targetVersion = song.versions.find(v => v.is_active);
    }
    
    if (!targetVersion) {
      alert("该歌曲暂无可用的启用音频版本！请先启用至少一个版本。");
      return;
    }
    handlePlayVersion(song, targetVersion);
  };

  const handlePlayVersion = async (song: Song, version: AudioVersion) => {
    try {
      initAudioAnalyzer();
      
      // 替换 Windows 下的反斜杠，将其规范化为前端网络路径斜杠，防止 Webview2 解析 CORS 或路径破损
      const normalizedPath = (libraryPath + "/" + version.filepath).replace(/\\/g, "/");
      const assetUrl = convertFileSrc(normalizedPath);
      
      if (audioRef.current) {
        audioRef.current.pause();
        audioRef.current.src = assetUrl;
        audioRef.current.load();
        
        setPlayingSong(song);
        setPlayingVersion(version);
        setIsPlaying(true);
        
        await audioRef.current.play();
        
        if (audioContextRef.current && audioContextRef.current.state === "suspended") {
          await audioContextRef.current.resume();
        }
      }
    } catch (err) {
      console.error("播放音频失败:", err);
    }
  };

  const handlePlayPause = () => {
    if (!audioRef.current || !playingVersion) return;
    if (isPlaying) {
      audioRef.current.pause();
      setIsPlaying(false);
    } else {
      audioRef.current.play().then(() => {
        setIsPlaying(true);
      }).catch(err => {
        console.error("恢复播放失败:", err);
      });
    }
  };

  // 标签多维条件动态过滤引擎
  const filteredSongs = useMemo(() => {
    return songs.filter(song => {
      // 1. 搜索关键词匹配
      const matchesSearch = searchQuery === "" || 
        song.title.toLowerCase().includes(searchQuery.toLowerCase()) ||
        (song.artist && song.artist.toLowerCase().includes(searchQuery.toLowerCase())) ||
        (song.album && song.album.toLowerCase().includes(searchQuery.toLowerCase()));
      
      if (!matchesSearch) return false;

      // 2. 多维标签规则匹配
      if (selectedTags.length === 0) return true;

      const songTagIds = song.tags.map(t => t.id);
      if (filterMode === "AND") {
        return selectedTags.every(id => songTagIds.includes(id));
      } else {
        return selectedTags.some(id => songTagIds.includes(id));
      }
    });
  }, [songs, searchQuery, selectedTags, filterMode]);

  const handlePlaybackModeCycle = () => {
    if (playMode === "list") setPlayMode("shuffle");
    else if (playMode === "shuffle") setPlayMode("single");
    else setPlayMode("list");
  };

  const handleNext = () => {
    if (filteredSongs.length === 0) return;
    let nextIndex = 0;
    
    if (playMode === "shuffle") {
      nextIndex = Math.floor(Math.random() * filteredSongs.length);
    } else {
      const currentIndex = filteredSongs.findIndex(s => s.id === playingSong?.id);
      nextIndex = (currentIndex + 1) % filteredSongs.length;
    }
    
    handlePlaySong(filteredSongs[nextIndex]);
  };

  const handlePrev = () => {
    if (filteredSongs.length === 0) return;
    let prevIndex = 0;
    
    if (playMode === "shuffle") {
      prevIndex = Math.floor(Math.random() * filteredSongs.length);
    } else {
      const currentIndex = filteredSongs.findIndex(s => s.id === playingSong?.id);
      prevIndex = currentIndex <= 0 ? filteredSongs.length - 1 : currentIndex - 1;
    }
    
    handlePlaySong(filteredSongs[prevIndex]);
  };

  const handleEnded = () => {
    if (playMode === "single") {
      if (audioRef.current) {
        audioRef.current.currentTime = 0;
        audioRef.current.play().catch(err => console.log(err));
      }
    } else {
      handleNext();
    }
  };

  const handleSeek = (e: React.MouseEvent<HTMLDivElement>) => {
    if (!audioRef.current || duration === 0) return;
    const rect = e.currentTarget.getBoundingClientRect();
    const clickX = e.clientX - rect.left;
    const pct = clickX / rect.width;
    const seekTime = pct * duration;
    audioRef.current.currentTime = seekTime;
    setCurrentTime(seekTime);
  };

  const handleVolumeChange = (e: React.MouseEvent<HTMLDivElement>) => {
    const rect = e.currentTarget.getBoundingClientRect();
    const clickX = e.clientX - rect.left;
    const pct = Math.max(0, Math.min(1, clickX / rect.width));
    setVolume(pct);
  };

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

      {/* 左侧边栏：Aetheria 极简导航 */}
      <div className="glass-panel sidebar">
        <div>
          <div className="logo-section">
            <div className="logo-icon">
              <Music size={22} color="white" />
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
        </div>

        <div className="sidebar-bottom">
          <div className="menu-item" onClick={() => setIsSettingsOpen(true)}>
            <Settings size={18} />
            系统设置
          </div>
        </div>
      </div>

      {/* 中间主要功能区：歌曲列表与标签过滤池 */}
      <div className="glass-panel main-content">
        <div className="header-row">
          <h2 style={{ margin: 0, fontWeight: 800, fontSize: "1.6rem" }}>曲库大厅</h2>
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

        {/* 可收起的标签过滤器 */}
        <div className="tag-matrix-panel">
          <div className="tag-matrix-header" onClick={() => setIsTagsExpanded(!isTagsExpanded)}>
            <span className="tag-matrix-title-wrapper">
              <TagIcon size={16} /> 
              标签多维过滤器
              {isTagsExpanded ? <ChevronDown size={16} /> : <ChevronRight size={16} />}
            </span>
            <div className="filter-toggle-container" onClick={e => e.stopPropagation()}>
              <div 
                className={`filter-toggle-btn ${filterMode === "AND" ? "active" : ""}`}
                onClick={() => setFilterMode("AND")}
              >
                交集 (AND)
              </div>
              <div 
                className={`filter-toggle-btn ${filterMode === "OR" ? "active" : ""}`}
                onClick={() => setFilterMode("OR")}
              >
                并集 (OR)
              </div>
            </div>
          </div>
          
          <div className={`tag-matrix-content-wrapper ${isTagsExpanded ? "" : "collapsed"}`}>
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
              {tags.length === 0 && (
                <div style={{ color: "var(--text-sub)", fontSize: "0.85rem" }}>暂无预设标签，可点击左侧标签管理器新建</div>
              )}
            </div>
          </div>
        </div>

        {/* 歌曲主列表 - 优化表头和防中文折行 */}
        <div className="song-list-container">
          <table className="song-table">
            <thead>
              <tr>
                <th></th>
                <th>歌曲名称</th>
                <th>歌手</th>
                <th>绑定的自定义标签</th>
                <th style={{ textAlign: "center" }}>版本数</th>
                <th style={{ textAlign: "center" }}>默认音质</th>
              </tr>
            </thead>
            <tbody>
              {filteredSongs.map(song => {
                const isCurrentlyPlaying = playingSong?.id === song.id;
                const primaryVersion = song.versions.find(v => v.is_primary);
                const activeFormat = primaryVersion?.format.toUpperCase() || "未知";
                
                return (
                  <tr 
                    key={song.id} 
                    className={`song-row ${isCurrentlyPlaying ? "playing" : ""} ${activeSong?.id === song.id ? "active" : ""}`}
                    onClick={() => {
                      setActiveSong(song);
                      setIsDetailOpen(true);
                    }}
                    onDoubleClick={() => handlePlaySong(song)}
                  >
                    <td>
                      <div className="play-row-btn">
                        {isCurrentlyPlaying && isPlaying ? <Pause size={14} /> : <Play size={14} />}
                      </div>
                    </td>
                    <td>
                      <div className="song-title-cell">
                        <span className="song-title-text">{song.title}</span>
                      </div>
                    </td>
                    <td>
                      <span className="song-artist-text">{song.artist || "未知歌手"}</span>
                    </td>
                    <td>
                      <div className="badge-container">
                        {song.tags.map(t => (
                          <span 
                            key={t.id} 
                            className="tag-pill" 
                            style={{ borderLeft: `3px solid ${t.color}`, color: t.color }}
                          >
                            {t.name}
                          </span>
                        ))}
                      </div>
                    </td>
                    <td style={{ textAlign: "center", fontWeight: 600 }}>{song.versions.length}</td>
                    <td style={{ textAlign: "center" }}>
                      <span className={`format-badge ${activeFormat.toLowerCase()}`}>
                        {activeFormat}
                      </span>
                    </td>
                  </tr>
                );
              })}
              {filteredSongs.length === 0 && (
                <tr>
                  <td colSpan={6} style={{ textAlign: "center", padding: "40px", color: "var(--text-sub)" }}>
                    没有找到符合条件的歌曲，请导入或调整过滤器
                  </td>
                </tr>
              )}
            </tbody>
          </table>
        </div>

        {/* 侧滑出来的歌曲详情 / 版本控制抽屉 */}
        <div className={`glass-panel detail-pane ${isDetailOpen ? "open" : ""}`}>
          <button className="detail-close-btn" onClick={() => setIsDetailOpen(false)}>
            <X size={20} />
          </button>
          
          {activeSong ? (
            <>
              <div className="detail-header">
                <div className="cover-container">
                  <div className="cover-glow"></div>
                  <Music size={44} />
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
                {/* 1. 音频版本控制 */}
                {activeTab === "versions" && (
                  <div style={{ display: "flex", flexDirection: "column", gap: "10px" }}>
                    {activeSong.versions.map(v => (
                      <div key={v.id} className="version-item">
                        <div className="version-row">
                          <div className="version-meta">
                            <span className="version-filename" title={v.filename}>{v.filename}</span>
                            <span className="version-specs">
                              {v.format.toUpperCase()} · {v.bitrate ? `${Math.round(v.bitrate / 1000)}kbps` : "未知码率"} · {v.filesize ? `${(v.filesize / 1024 / 1024).toFixed(2)} MB` : ""} · {formatTime(v.duration || 0)}
                            </span>
                          </div>
                          <button 
                            className="ctrl-btn" 
                            style={{ color: playingVersion?.id === v.id && isPlaying ? "#10b981" : "var(--accent)" }}
                            onClick={() => handlePlayVersion(activeSong, v)}
                          >
                            {playingVersion?.id === v.id && isPlaying ? <Pause size={18} /> : <Play size={18} />}
                          </button>
                        </div>

                        <div className="version-actions">
                          <label className="checkbox-label">
                            <input 
                              type="checkbox" 
                              checked={v.is_active} 
                              onChange={(e) => handleToggleVersionStatus(v.id, e.target.checked)}
                            />
                            启用该版本
                          </label>

                          <label className="radio-label">
                            <input 
                              type="radio" 
                              name={`primary-${activeSong.id}`} 
                              checked={v.is_primary}
                              disabled={!v.is_active}
                              onChange={() => handleSetPrimaryVersion(v.id)}
                            />
                            设为主播放版本
                          </label>
                        </div>
                        
                        <div style={{ borderTop: "1px dashed var(--border)", paddingTop: "6px", display: "flex", justifyContent: "flex-end" }}>
                          <button className="action-btn-sm" onClick={() => handleExportVersion(v.id)}>
                            <Download size={12} /> 导出还原音频
                          </button>
                        </div>
                      </div>
                    ))}
                    <div style={{ fontSize: "0.78rem", color: "var(--text-sub)", marginTop: "6px" }}>
                      💡 绑定多个版本时，软件会在您双击歌曲时默认播放标为“主版本”的音频。
                    </div>
                  </div>
                )}

                {/* 2. 标签多对多绑定 */}
                {activeTab === "tags" && (
                  <div className="tag-list-checkboxes">
                    {tags.map(t => {
                      const isBound = activeSong.tags.some(tag => tag.id === t.id);
                      return (
                        <div 
                          key={t.id} 
                          className="tag-bind-item"
                          onClick={() => {
                            if (isBound) handleUnbindTag(activeSong.id, t.id);
                            else handleBindTag(activeSong.id, t.id);
                          }}
                        >
                          <span style={{ color: t.color, fontWeight: 600 }}>{t.name}</span>
                          {isBound ? <CheckSquare size={16} color={t.color} /> : <Square size={16} color="var(--text-sub)" />}
                        </div>
                      );
                    })}
                    {tags.length === 0 && (
                      <div style={{ color: "var(--text-sub)", padding: "10px", textAlign: "center" }}>暂无可选标签，请先去管理器添加</div>
                    )}
                  </div>
                )}

                {/* 3. 歌词与信息 */}
                {activeTab === "lyrics" && (
                  <div className="lyrics-container">
                    {activeSong.lyrics ? activeSong.lyrics : "暂无歌词内容"}
                  </div>
                )}
              </div>
            </>
          ) : (
            <div className="empty-detail">
              <Music size={48} style={{ opacity: 0.5 }} />
              <div>未选择歌曲</div>
              <div style={{ fontSize: "0.8rem", maxWidth: "200px" }}>在左侧选择一首歌曲以管理它的多个音频文件和属性。</div>
            </div>
          )}
        </div>
        
        {/* 沉浸式全屏歌词浮层 - 移动至 main-content 内部，避免遮挡侧边栏和播放栏，且支持模糊模糊滤镜 */}
        {isLyricsOverlayOpen && playingSong && (
          <div className="lyrics-overlay">
            <button className="lyrics-overlay-close" onClick={() => setIsLyricsOverlayOpen(false)}>
              <X size={20} />
            </button>
            
            <div className="lyrics-overlay-title">{playingSong.title}</div>
            <div className="lyrics-overlay-artist">{playingSong.artist || "未知歌手"}</div>
            
            <div className="lyrics-scroll-box">
              {lyricsLines.map((line, idx) => {
                const isActive = idx === activeLyricsIndex;
                return (
                  <div 
                    key={idx} 
                    ref={isActive ? activeLineRef : null}
                    className={isActive ? "lyrics-line-active" : "lyrics-line-inactive"}
                  >
                    {line}
                  </div>
                );
              })}
            </div>
          </div>
        )}
      </div>

      {/* 底部播放控制栏 - 全新重构 */}
      <div className="playbar">
        {/* 最上边缘的无感进度条 - 统一进度条与音量条样式 */}
        <div className="playbar-progress-container" onClick={handleSeek}>
          <div 
            className="slider-fill" 
            style={{ width: `${duration > 0 ? (currentTime / duration) * 100 : 0}%` }}
          ></div>
          <div 
            className="slider-handle" 
            style={{ left: `${duration > 0 ? (currentTime / duration) * 100 : 0}%` }}
          ></div>
        </div>

        {/* 1. 当前曲目卡片 */}
        <div className="playbar-track-info">
          <div className="playbar-cover" onClick={() => setIsLyricsOverlayOpen(true)} style={{ cursor: "pointer" }} title="点击打开歌词">
            {playingSong ? <FileAudio size={22} color="var(--accent)" /> : <Music size={22} />}
          </div>
          <div className="playbar-meta">
            <span className="playbar-title" title={playingSong?.title || "未开始播放"}>
              {playingSong?.title || "未开始播放"}
            </span>
            <span className="playbar-artist">
              {playingSong ? `${playingSong.artist || "未知歌手"} · ${playingVersion?.format.toUpperCase() || ""}` : "Aetheria 音乐库"}
            </span>
          </div>
        </div>

        {/* 2. 播放动作控制与循环模式 */}
        <div className="playbar-controls">
          <div className="control-buttons">
            <button 
              className={`ctrl-btn ${playMode === "shuffle" ? "active" : ""}`} 
              onClick={handlePlaybackModeCycle} 
              title="切换到随机播放"
            >
              <Shuffle size={18} />
            </button>
            
            <button className="ctrl-btn" onClick={handlePrev} title="上一首">
              <SkipBack size={20} />
            </button>
            
            <button className="ctrl-btn play-pause" onClick={handlePlayPause}>
              {isPlaying ? <Pause size={20} /> : <Play size={20} style={{ transform: "translateX(1px)" }} />}
            </button>
            
            <button className="ctrl-btn" onClick={handleNext} title="下一首">
              <SkipForward size={20} />
            </button>

            <button 
              className="ctrl-btn" 
              onClick={handlePlaybackModeCycle} 
              title={playMode === "single" ? "单曲循环" : "列表循环"}
            >
              {playMode === "single" ? <Repeat1 size={18} className="active" /> : <Repeat size={18} />}
            </button>
          </div>

          <div style={{ fontSize: "0.75rem", color: "var(--text-sub)", display: "flex", gap: "8px" }}>
            <span>{formatTime(currentTime)}</span>
            <span>/</span>
            <span>{formatTime(duration)}</span>
          </div>
        </div>

        {/* 3. 音量控制器与歌词开关 */}
        <div className="playbar-volume">
          <button 
            className={`ctrl-btn ${isLyricsOverlayOpen ? "active" : ""}`} 
            style={{ marginRight: 10 }}
            onClick={() => setIsLyricsOverlayOpen(!isLyricsOverlayOpen)} 
            title="歌词面板"
          >
            <LayoutList size={18} />
          </button>
          
          <Volume2 size={16} color="var(--text-sub)" />
          <span className="volume-pct-label">{Math.round(volume * 100)}%</span>
          <div className="volume-slider" onClick={handleVolumeChange}>
            <div className="slider-fill" style={{ width: `${volume * 100}%` }}></div>
            <div className="slider-handle" style={{ left: `${volume * 100}%` }}></div>
          </div>
        </div>

        {/* 动画频谱 Canvas */}
        <canvas ref={canvasRef} className="visualizer-canvas" width={1000} height={36} />
      </div>

      {/* Modal 1: 标签管理器弹框 */}
      {isTagManagerOpen && (
        <div className="modal-overlay" onClick={() => setIsTagManagerOpen(false)}>
          <div className="modal-content" onClick={e => e.stopPropagation()}>
            <div className="modal-header">
              <span className="modal-title">管理已有标签</span>
              <button className="ctrl-btn" onClick={() => setIsTagManagerOpen(false)}><X size={18} /></button>
            </div>
            
            {/* 新建标签表单直接移入管理器，释放外部布局压力 */}
            <div className="form-group" style={{ background: "var(--bg-hover)", padding: "12px", borderRadius: "10px" }}>
              <label>新建自定义标签</label>
              <div style={{ display: "flex", gap: "8px", marginBottom: "8px" }}>
                <input 
                  type="text" 
                  placeholder="标签名, 如: 抒情" 
                  className="text-input"
                  style={{ flex: 1 }}
                  value={newTagName}
                  onChange={e => setNewTagName(e.target.value)}
                />
                <button className="btn-primary" onClick={handleCreateTag}>
                  <Plus size={16} /> 创建
                </button>
              </div>
              <div className="color-picker-grid">
                {PRESET_COLORS.map(c => (
                  <div 
                    key={c}
                    className={`color-option ${newTagColor === c ? "selected" : ""}`}
                    style={{ backgroundColor: c }}
                    onClick={() => setNewTagColor(c)}
                  />
                ))}
              </div>
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

      {/* Modal 2: 系统设置弹框 */}
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

            {/* 导入功能收归至设置中 */}
            <div className="form-group" style={{ borderTop: "1px solid var(--border)", paddingTop: "12px" }}>
              <label>导入本地音频数据</label>
              <button className="import-btn" style={{ width: "100%", display: "flex", gap: "8px", justifyContent: "center", alignItems: "center" }} onClick={handleImportSongs}>
                <FolderPlus size={16} /> 扫描导入本地音频文件夹
              </button>
            </div>

            <div className="form-group">
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
