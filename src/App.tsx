import { useState, useEffect, useRef, useMemo } from "react";
import { invoke } from "@tauri-apps/api/core";
import { convertFileSrc } from "@tauri-apps/api/core";
import { X, Search, FolderPlus, Folder, FileAudio } from "lucide-react";

import Sidebar from "./components/Sidebar";
import TagFilter from "./components/TagFilter";
import SongTable from "./components/SongTable";
import DetailPane from "./components/DetailPane";
import PlayBar from "./components/PlayBar";
import Toast from "./components/Toast";
import TagManagerModal from "./components/TagManagerModal";
import SettingsModal from "./components/SettingsModal";
import ImportPreviewModal from "./components/ImportPreviewModal";
import MobileLayout from "./components/MobileLayout";

import "./App.css";

interface AudioVersion {
  id: string;
  filepath: string;
  original_name: string;
  format: string;
  bitrate?: number;
  duration?: number;
  file_size?: number;
  is_primary: boolean;
  is_enabled: boolean;
  md5?: string;
  bit_depth?: number;
  sample_rate?: number;
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

interface Playlist {
  id: string;
  name: string;
  description?: string;
  created_at: string;
}

interface Clipboard {
  type: "copy" | "cut";
  songIds: string[];
  sourcePlaylistId: string | null;
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
  const [playlists, setPlaylists] = useState<Playlist[]>([]);
  const [libraryPath, setLibraryPath] = useState<string>("");
  const [needsInit, setNeedsInit] = useState(false);
  
  // 当前活动歌单
  const [activePlaylistId, setActivePlaylistId] = useState<string | null>(() => {
    return localStorage.getItem("aetheria-active-playlist-id") || null;
  });
  const [playlistSongIds, setPlaylistSongIds] = useState<string[]>([]);
  
  // 过滤与搜索状态
  const [searchQuery, setSearchQuery] = useState("");
  const [selectedTags, setSelectedTags] = useState<number[]>(() => {
    try {
      return JSON.parse(localStorage.getItem("aetheria-selected-tags") || "[]");
    } catch { return []; }
  });
  const [filterMode, setFilterMode] = useState<"AND" | "OR">(() => {
    return (localStorage.getItem("aetheria-filter-mode") as any) || "AND";
  });
  const [isTagsExpanded, setIsTagsExpanded] = useState(true);
  
  // 当前聚焦歌曲及 Tab 状态
  const [activeSong, setActiveSong] = useState<Song | null>(null);
  const [isDetailOpen, setIsDetailOpen] = useState(false);
  const [activeTab, setActiveTab] = useState<"versions" | "tags" | "lyrics">("versions");
  
  // 选中的歌曲
  const [selectedSongIds, setSelectedSongIds] = useState<string[]>([]);
  // 剪贴板
  const [clipboard, setClipboard] = useState<Clipboard | null>(() => {
    try {
      const saved = localStorage.getItem("aetheria-clipboard");
      return saved ? JSON.parse(saved) : null;
    } catch { return null; }
  });

  // 播放器核心状态
  const [playingSong, setPlayingSong] = useState<Song | null>(null);
  const [playingVersion, setPlayingVersion] = useState<AudioVersion | null>(null);
  const [isPlaying, setIsPlaying] = useState(false);
  const [currentTime, setCurrentTime] = useState(0);
  const [duration, setDuration] = useState(0);
  const [volume, setVolume] = useState<number>(() => {
    const val = localStorage.getItem("aetheria-volume");
    return val ? parseFloat(val) : 0.8;
  });
  const [playMode, setPlayMode] = useState<"list" | "single" | "shuffle">(() => {
    return (localStorage.getItem("aetheria-play-mode") as any) || "list";
  });
  
  // UI 模态框及 Loading 状态
  const [isTagManagerOpen, setIsTagManagerOpen] = useState(false);
  const [isSettingsOpen, setIsSettingsOpen] = useState(false);
  const [isLyricsOverlayOpen, setIsLyricsOverlayOpen] = useState(false);
  const [isImporting, setIsImporting] = useState(false);
  const [importProgress, setImportProgress] = useState("");
  const [showImportDropdown, setShowImportDropdown] = useState(false);

  // 导入预览相关状态
  const [filesToPreview, setFilesToPreview] = useState<string[]>([]);
  const [isPreviewOpen, setIsPreviewOpen] = useState(false);
  
  // 标签新建属性
  const [newTagName, setNewTagName] = useState("");
  const [newTagColor, setNewTagColor] = useState(PRESET_COLORS[0]);
  const [newTagCategory, setNewTagCategory] = useState("自定义");

  // 主题状态切换逻辑
  const [theme, setTheme] = useState<"dark" | "light" | "pink">(() => {
    return (localStorage.getItem("aetheria-theme") as any) || "dark";
  });

  // 移动端/响应式屏幕宽度判定
  const [isMobile, setIsMobile] = useState(window.innerWidth < 768);
  useEffect(() => {
    const handleResize = () => setIsMobile(window.innerWidth < 768);
    window.addEventListener("resize", handleResize);
    return () => window.removeEventListener("resize", handleResize);
  }, []);

  // 播放器 DOM 引用
  const audioRef = useRef<HTMLAudioElement | null>(null);
  const canvasRef = useRef<HTMLCanvasElement | null>(null);
  const animationRef = useRef<number | null>(null);
  const activeLineRef = useRef<HTMLDivElement | null>(null);
  
  // Web Audio API 动效相关
  const audioContextRef = useRef<AudioContext | null>(null);
  const analyserRef = useRef<AnalyserNode | null>(null);
  const sourceRef = useRef<MediaElementAudioSourceNode | null>(null);

  // 缓存正在播放的歌曲与音源 Ref 以解决 React useEffect 监听器的闭包陷阱与同步更新竞赛 Bug
  const playingSongRef = useRef<Song | null>(null);
  const playingVersionRef = useRef<AudioVersion | null>(null);

  const changePlayingSong = (song: Song | null) => {
    setPlayingSong(song);
    playingSongRef.current = song;
  };

  const changePlayingVersion = (version: AudioVersion | null) => {
    setPlayingVersion(version);
    playingVersionRef.current = version;
  };

  // 缓存播放结束的回调，防范 React 闭包旧状态
  const handleEndedRef = useRef<(() => void) | null>(null);

  // 全局精美自定义 Toast 提示框状态
  const [toast, setToast] = useState<{ message: string; type: "success" | "error" | "info" } | null>(null);
  const showToast = (message: string, type: "success" | "error" | "info" = "info") => {
    setToast({ message, type });
  };
  useEffect(() => {
    if (toast) {
      const timer = setTimeout(() => setToast(null), 3000);
      return () => clearTimeout(timer);
    }
  }, [toast]);

  // 初始化加载数据
  const loadLibrary = async () => {
    try {
      const loadedSongs: Song[] = await invoke("get_songs");
      const loadedTags: Tag[] = await invoke("get_tags");
      const libPath: string = await invoke("get_library_path");
      
      setSongs(loadedSongs);
      setTags(loadedTags);
      setLibraryPath(libPath);
      return { loadedSongs, libPath };
    } catch (err) {
      console.error("加载音乐库失败:", err);
      return { loadedSongs: [], libPath: "" };
    }
  };

  const fetchPlaylists = async () => {
    try {
      const list = await invoke<Playlist[]>("get_playlists");
      setPlaylists(list);
    } catch (err) {
      console.error("加载歌单合集失败:", err);
    }
  };

  useEffect(() => {
    const initApp = async () => {
      try {
        const isInit = await invoke<boolean>("is_library_initialized");
        if (!isInit) {
          setNeedsInit(true);
          return;
        }
        
        loadLibrary().then(({ loadedSongs, libPath }) => {
          const savedSongId = localStorage.getItem("aetheria-playing-song-id");
          const savedVersionId = localStorage.getItem("aetheria-playing-version-id");
          const savedTimeStr = localStorage.getItem("aetheria-current-time");
          
          if (savedSongId && savedVersionId && loadedSongs.length > 0) {
            const song = loadedSongs.find(s => s.id === savedSongId);
            if (song) {
              const version = song.versions.find(v => v.id === savedVersionId);
              if (version) {
                changePlayingSong(song);
                changePlayingVersion(version);
                
                if (audioRef.current) {
                  audioRef.current.crossOrigin = "anonymous";
                  const normalizedPath = (libPath + "/" + version.filepath).replace(/\\/g, "/");
                  const assetUrl = convertFileSrc(normalizedPath);
                  audioRef.current.src = assetUrl;
                  audioRef.current.load();
                  
                  if (savedTimeStr) {
                    const savedTime = parseFloat(savedTimeStr);
                    if (!isNaN(savedTime)) {
                      audioRef.current.currentTime = savedTime;
                    }
                  }
                }
              }
            }
          }
        });
        fetchPlaylists();
      } catch (err) {
        console.error("初始化应用失败:", err);
      }
    };
    initApp();

    const handleContextMenu = (e: MouseEvent) => {
      e.preventDefault();
    };
    document.addEventListener("contextmenu", handleContextMenu);

    const handleWindowClick = () => {
      setShowImportDropdown(false);
    };
    window.addEventListener("click", handleWindowClick);

    return () => {
      document.removeEventListener("contextmenu", handleContextMenu);
      window.removeEventListener("click", handleWindowClick);
    };
  }, []);

  const handleTimeUpdate = () => {
    if (audioRef.current) {
      setCurrentTime(audioRef.current.currentTime);
      localStorage.setItem("aetheria-current-time", audioRef.current.currentTime.toString());
    }
  };

  const handleLoadedMetadata = () => {
    if (audioRef.current) {
      if (playingVersionRef.current && playingVersionRef.current.duration) {
        setDuration(playingVersionRef.current.duration);
      } else {
        setDuration(audioRef.current.duration);
      }
    }
  };

  useEffect(() => {
    handleEndedRef.current = handleEnded;
  });

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

  useEffect(() => {
    if (audioRef.current) {
      audioRef.current.volume = volume;
    }
    localStorage.setItem("aetheria-volume", volume.toString());
  }, [volume]);

  useEffect(() => {
    if (activePlaylistId) {
      localStorage.setItem("aetheria-active-playlist-id", activePlaylistId);
      invoke<string[]>("get_playlist_songs", { playlistId: activePlaylistId })
        .then(ids => setPlaylistSongIds(ids))
        .catch(err => console.error("加载歌单歌曲失败:", err));
    } else {
      localStorage.removeItem("aetheria-active-playlist-id");
      setPlaylistSongIds([]);
    }
    setSelectedSongIds([]);
  }, [activePlaylistId]);

  useEffect(() => {
    localStorage.setItem("aetheria-selected-tags", JSON.stringify(selectedTags));
  }, [selectedTags]);

  useEffect(() => {
    localStorage.setItem("aetheria-filter-mode", filterMode);
  }, [filterMode]);

  useEffect(() => {
    localStorage.setItem("aetheria-play-mode", playMode);
  }, [playMode]);

  useEffect(() => {
    if (playingSong) {
      localStorage.setItem("aetheria-playing-song-id", playingSong.id);
    } else {
      localStorage.removeItem("aetheria-playing-song-id");
    }
  }, [playingSong]);

  useEffect(() => {
    if (playingVersion) {
      localStorage.setItem("aetheria-playing-version-id", playingVersion.id);
    } else {
      localStorage.removeItem("aetheria-playing-version-id");
    }
  }, [playingVersion]);

  useEffect(() => {
    if (clipboard) {
      localStorage.setItem("aetheria-clipboard", JSON.stringify(clipboard));
    } else {
      localStorage.removeItem("aetheria-clipboard");
    }
}, [clipboard]);

  useEffect(() => {
    document.documentElement.className = "";
    document.documentElement.classList.add(`theme-${theme}`);
  }, [theme]);

  useEffect(() => {
    localStorage.setItem("aetheria-theme", theme);
  }, [theme]);

  useEffect(() => {
    if (activeSong) {
      localStorage.setItem("aetheria-active-song-id", activeSong.id);
    } else {
      localStorage.removeItem("aetheria-active-song-id");
    }
  }, [activeSong]);

  useEffect(() => {
    localStorage.setItem("aetheria-is-detail-open", isDetailOpen ? "true" : "false");
  }, [isDetailOpen]);

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

  useEffect(() => {
    if (activeLineRef.current) {
      activeLineRef.current.scrollIntoView({
        behavior: "smooth",
        block: "center"
      });
    }
  }, [activeLyricsIndex]);

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

  const handleImportFolder = async () => {
    setIsImporting(true);
    setImportProgress("正在选择文件夹...");
    try {
      const selectedDir = await invoke<string | null>("select_directory");
      if (!selectedDir) {
        setIsImporting(false);
        return;
      }

      setImportProgress("正在扫描文件夹...");
      const scannedFiles = await invoke<string[]>("scan_directory_for_preview", { dirPath: selectedDir });
      if (scannedFiles.length === 0) {
        showToast("该目录下未找到兼容的音频文件", "info");
        setIsImporting(false);
        return;
      }
      setFilesToPreview(scannedFiles);
      setIsPreviewOpen(true);
    } catch (err) {
      console.error(err);
      showToast("扫描失败: " + err, "error");
    } finally {
      setIsImporting(false);
    }
  };

  const handleImportFiles = async () => {
    setIsImporting(true);
    setImportProgress("正在选择音频文件...");
    try {
      const selectedFiles = await invoke<string[]>("select_audio_files");
      if (selectedFiles.length === 0) {
        setIsImporting(false);
        return;
      }
      setFilesToPreview(selectedFiles);
      setIsPreviewOpen(true);
    } catch (err) {
      console.error(err);
      showToast("选择失败: " + err, "error");
    } finally {
      setIsImporting(false);
    }
  };

  const handleConfirmImport = async (songsList: { filepath: string; title: string; artist: string }[]) => {
    setIsPreviewOpen(false);
    setIsImporting(true);
    setImportProgress(`正在导入并解析 ${songsList.length} 首歌曲...`);
    
    let successCount = 0;
    let duplicateCount = 0;
    
    for (const song of songsList) {
      try {
        await invoke("import_song_with_metadata", { 
          filepath: song.filepath, 
          title: song.title, 
          artist: song.artist 
        });
        successCount++;
      } catch (err) {
        console.error(err);
        if (String(err).includes("已存在")) {
          duplicateCount++;
        }
      }
    }
    
    let msg = `成功导入了 ${successCount} 首歌曲！`;
    if (duplicateCount > 0) {
      msg += ` 并跳过了 ${duplicateCount} 首已存在的重复音源。`;
    }
    
    setImportProgress(msg);
    showToast(msg, "success");
    
    setTimeout(() => {
      setIsImporting(false);
      loadLibrary();
    }, 1500);
  };

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
      showToast("标签新建成功", "success");
    } catch (err) {
      console.error("创建标签失败:", err);
    }
  };

  const handleDeleteTag = async (tagId: number) => {
    try {
      await invoke("delete_tag", { tagId });
      loadLibrary();
      showToast("标签已删除", "info");
    } catch (err) {
      console.error("删除标签失败:", err);
    }
  };

  const handleBindTag = async (songId: string, tagId: number) => {
    try {
      await invoke("tag_song", { songId, tagId });
      const { loadedSongs: freshSongs } = await loadLibrary();
      if (activeSong && activeSong.id === songId) {
        const updated = freshSongs.find(s => s.id === songId);
        if (updated) setActiveSong(updated);
      }
    } catch (err) {
      console.error(err);
    }
  };

  const handleUnbindTag = async (songId: string, tagId: number) => {
    try {
      await invoke("untag_song", { songId, tagId });
      const { loadedSongs: freshSongs } = await loadLibrary();
      if (activeSong && activeSong.id === songId) {
        const updated = freshSongs.find(s => s.id === songId);
        if (updated) setActiveSong(updated);
      }
    } catch (err) {
      console.error(err);
    }
  };

  const handleSetPrimaryVersion = async (versionId: string) => {
    if (!activeSong) return;
    const version = activeSong.versions.find(v => v.id === versionId);
    if (!version) return;
    try {
      await invoke("update_version_status", { 
        version_id: versionId, 
        is_enabled: version.is_enabled, 
        is_primary: true 
      });
      const { loadedSongs: freshSongs } = await loadLibrary();
      
      const updated = freshSongs.find(s => s.id === activeSong.id);
      if (updated) {
        setActiveSong(updated);
        if (playingSong && playingSong.id === activeSong.id) {
          const newPrimary = updated.versions.find(v => v.id === versionId);
          if (newPrimary) changePlayingVersion(newPrimary);
        }
      }
      showToast("默认主版本设置成功", "success");
    } catch (err) {
      console.error(err);
      showToast("设置失败: " + err, "error");
    }
  };

  const handleToggleVersionStatus = async (versionId: string, active: boolean) => {
    if (!activeSong) return;
    const version = activeSong.versions.find(v => v.id === versionId);
    if (!version) return;
    try {
      await invoke("update_version_status", { 
        version_id: versionId, 
        is_enabled: active, 
        is_primary: version.is_primary 
      });
      const { loadedSongs: freshSongs } = await loadLibrary();
      const updated = freshSongs.find(s => s.id === activeSong.id);
      if (updated) setActiveSong(updated);
    } catch (err) {
      console.error(err);
    }
  };

  const handleUpdateSongMetadata = async (songId: string, title: string, artist: string) => {
    try {
      await invoke("update_song_metadata", { songId, title, artist });
      showToast("歌曲基本信息已保存", "success");
      
      const { loadedSongs: freshSongs } = await loadLibrary();
      const updated = freshSongs.find(s => s.id === songId);
      if (updated) setActiveSong(updated);
    } catch (err) {
      showToast("保存信息失败: " + err, "error");
    }
  };

  const handleImportVersionForSong = async (songId: string) => {
    setIsImporting(true);
    setImportProgress("正在选择关联音频文件...");
    try {
      const selectedFiles = await invoke<string[]>("select_audio_files");
      if (selectedFiles.length === 0) {
        setIsImporting(false);
        return;
      }

      setImportProgress("正在解析并关联音频...");
      let successCount = 0;
      let errorMsg = "";
      for (const filepath of selectedFiles) {
        try {
          await invoke("import_audio_version_for_song", { songId, filepath });
          successCount++;
        } catch (e) {
          console.error(e);
          errorMsg = String(e);
        }
      }

      if (successCount > 0) {
        showToast(`成功关联了 ${successCount} 个新音频源！`, "success");
      } else if (errorMsg) {
        showToast(errorMsg, "error");
      }

      const { loadedSongs: freshSongs } = await loadLibrary();
      if (activeSong) {
        const updated = freshSongs.find(s => s.id === activeSong.id);
        if (updated) setActiveSong(updated);
      }
    } catch (err) {
      console.error(err);
      showToast("导入关联失败: " + err, "error");
    } finally {
      setIsImporting(false);
    }
  };

  const handleExportVersion = async (versionId: string) => {
    try {
      const destPath = await invoke<string | null>("select_save_file");
      if (!destPath) return;
      await invoke("export_audio_file", { versionId, destPath });
      showToast("音频导出还原成功！", "success");
    } catch (err) {
      showToast("导出失败: " + err, "error");
    }
  };

  const handlePlaySong = (song: Song) => {
    let targetVersion = song.versions.find(v => v.is_primary && v.is_enabled);
    if (!targetVersion) {
      targetVersion = song.versions.find(v => v.is_enabled);
    }
    
    if (!targetVersion) {
      showToast("该歌曲暂无可用的启用音频版本！请先启用至少一个版本。", "error");
      return;
    }
    handlePlayVersion(song, targetVersion);
  };

  const handlePlayVersion = async (song: Song, version: AudioVersion) => {
    const exists = await invoke<boolean>("verify_audio_file", { filepath: version.filepath });
    if (!exists) {
      showToast(`本地音频文件已丢失或被外部删除！`, "error");
      try {
        await invoke("update_version_status", { versionId: version.id, active: false });
        loadLibrary();
      } catch (err) {
        console.error(err);
      }
      return;
    }

    try {
      initAudioAnalyzer();
      
      const normalizedPath = (libraryPath + "/" + version.filepath).replace(/\\/g, "/");
      const assetUrl = convertFileSrc(normalizedPath);
      
      if (audioRef.current) {
        audioRef.current.pause();
        audioRef.current.crossOrigin = "anonymous";
        audioRef.current.src = assetUrl;
        audioRef.current.load();
        
        changePlayingSong(song);
        changePlayingVersion(version);
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

  const handleDeleteVersion = async (versionId: string) => {
    if (!activeSong) return;
    const version = activeSong.versions.find(v => v.id === versionId);
    const versionName = version ? version.original_name : "该音频源";
    const isLastVersion = activeSong.versions.length <= 1;

    const confirmDel = confirm(`确定要永久删除音频源 [${versionName}] 吗？这会从本地磁盘抹除该文件。`);
    if (!confirmDel) return;

    try {
      await invoke("delete_audio_version", { versionId });
      showToast("音源已删除", "success");

      const { loadedSongs } = await loadLibrary();
      const updated = loadedSongs.find(s => s.id === activeSong.id);
      if (updated) {
        setActiveSong(updated);
      } else {
        setActiveSong(null);
        setIsDetailOpen(false);
      }

      if (isLastVersion) {
        showToast("该歌曲目前没有绑定任何音频版本，您可以继续彻底删除该歌曲实体或重新关联新版本。", "info");
      }

      if (playingVersion && playingVersion.id === versionId) {
        if (audioRef.current) audioRef.current.pause();
        changePlayingVersion(null);
        setIsPlaying(false);
        setCurrentTime(0);
        setDuration(0);
        if (updated) {
          const nextAvailable = updated.versions.find(v => v.is_enabled);
          if (nextAvailable) {
            changePlayingVersion(nextAvailable);
          }
        }
      }
    } catch (err) {
      showToast("删除音源失败: " + err, "error");
    }
  };

  const handleDeleteSongs = async (songIds: string[]) => {
    const count = songIds.length;
    const confirmDel = confirm(`确定要永久删除选中的 ${count} 首歌曲及其关联的所有本地文件吗？此操作不可逆！`);
    if (!confirmDel) return;

    let deletedCount = 0;
    for (const songId of songIds) {
      try {
        await invoke("delete_song", { songId });
        deletedCount++;
      } catch (err) {
        console.error(`删除歌曲 ${songId} 失败:`, err);
      }
    }

    showToast(`成功彻底删除了 ${deletedCount} 首歌曲！`, "success");
    await loadLibrary();

    if (playingSong && songIds.includes(playingSong.id)) {
      if (audioRef.current) audioRef.current.pause();
      changePlayingSong(null);
      changePlayingVersion(null);
      setIsPlaying(false);
      setCurrentTime(0);
      setDuration(0);
    }

    if (activeSong && songIds.includes(activeSong.id)) {
      setActiveSong(null);
      setIsDetailOpen(false);
    }

    setSelectedSongIds([]);
  };

  const handleResetLibrary = async () => {
    const confirm1 = confirm("⚠️ 警告：此操作将永久清空本地托管的全部音乐文件、歌单、标签配置及数据库记录！");
    if (!confirm1) return;
    const confirm2 = confirm("❌ 确定真的要执行重置吗？这会清除您的全部播放状态，重置后软件将恢复到初始白板状态。");
    if (!confirm2) return;

    try {
      await invoke("reset_library");
      showToast("整个音乐库已成功清空并重置！", "success");
      
      if (audioRef.current) audioRef.current.pause();
      changePlayingSong(null);
      changePlayingVersion(null);
      setIsPlaying(false);
      setCurrentTime(0);
      setDuration(0);
      setActiveSong(null);
      setIsDetailOpen(false);
      setSelectedSongIds([]);
      
      await loadLibrary();
      await fetchPlaylists();
      setIsSettingsOpen(false);
    } catch (err) {
      showToast("清空重置失败: " + err, "error");
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

  const handleCreatePlaylist = async (name: string) => {
    try {
      await invoke("create_playlist", { name });
      await fetchPlaylists();
      showToast("歌单合集新建成功", "success");
    } catch (err) {
      showToast("创建歌单失败: " + err, "error");
    }
  };

  const handleRenamePlaylist = async (id: string, name: string) => {
    try {
      await invoke("rename_playlist", { id, name });
      await fetchPlaylists();
      showToast("歌单已成功重命名", "success");
    } catch (err) {
      showToast("重命名失败: " + err, "error");
    }
  };

  const handleDeletePlaylist = async (id: string) => {
    const pl = playlists.find(p => p.id === id);
    const plName = pl ? pl.name : "该歌单";

    const confirm1 = confirm(`确定要删除歌单 [${plName}] 吗？`);
    if (!confirm1) return;
    const confirm2 = confirm(`此操作将永久移除歌单 [${plName}]，您确定真的是要删除它吗？`);
    if (!confirm2) return;
    const confirm3 = confirm(`最后一次确认：您将从数据库中永久失去歌单 [${plName}]，真的真的真的要删除吗？`);
    if (!confirm3) return;

    try {
      await invoke("delete_playlist", { id });
      await fetchPlaylists();
      if (activePlaylistId === id) {
        setActivePlaylistId(null);
      }
      showToast("歌单已删除", "info");
    } catch (err) {
      showToast("删除歌单失败: " + err, "error");
    }
  };

  const handleAddSongsToPlaylist = async (playlistId: string, songIds: string[]) => {
    try {
      await invoke("add_songs_to_playlist", { playlistId, songIds });
      if (activePlaylistId === playlistId) {
        const ids = await invoke<string[]>("get_playlist_songs", { playlistId });
        setPlaylistSongIds(ids);
      }
      showToast(`成功添加 ${songIds.length} 首歌曲到歌单`, "success");
    } catch (err) {
      showToast("添加失败: " + err, "error");
    }
  };

  const handleRemoveSongsFromPlaylist = async (playlistId: string, songIds: string[]) => {
    try {
      await invoke("remove_songs_from_playlist", { playlistId, songIds });
      const ids = await invoke<string[]>("get_playlist_songs", { playlistId });
      setPlaylistSongIds(ids);
      showToast("已从该歌单中移除所选歌曲", "info");
    } catch (err) {
      showToast("移除失败: " + err, "error");
    }
  };

  const handlePasteSongs = async (playlistId: string) => {
    if (!clipboard) return;
    try {
      await invoke("add_songs_to_playlist", { playlistId, songIds: clipboard.songIds });
      if (clipboard.type === "cut" && clipboard.sourcePlaylistId) {
        await invoke("remove_songs_from_playlist", { playlistId: clipboard.sourcePlaylistId, songIds: clipboard.songIds });
      }
      const ids = await invoke<string[]>("get_playlist_songs", { playlistId });
      setPlaylistSongIds(ids);
      setClipboard(null);
      showToast("已成功粘贴剪贴板内的歌曲", "success");
    } catch (err) {
      showToast("粘贴失败: " + err, "error");
    }
  };

  const displaySongs = useMemo(() => {
    let list = songs;
    
    if (activePlaylistId) {
      list = playlistSongIds
        .map(id => songs.find(s => s.id === id))
        .filter((s): s is Song => !!s);
    }
    
    return list.filter(song => {
      const matchesSearch = searchQuery === "" || 
        song.title.toLowerCase().includes(searchQuery.toLowerCase()) ||
        (song.artist && song.artist.toLowerCase().includes(searchQuery.toLowerCase())) ||
        (song.album && song.album.toLowerCase().includes(searchQuery.toLowerCase()));
      
      if (!matchesSearch) return false;

      if (selectedTags.length === 0) return true;

      const songTagIds = song.tags.map(t => t.id);
      if (filterMode === "AND") {
        return selectedTags.every(id => songTagIds.includes(id));
      } else {
        return selectedTags.some(id => songTagIds.includes(id));
      }
    });
  }, [songs, activePlaylistId, playlistSongIds, searchQuery, selectedTags, filterMode]);

  const handlePlaybackModeCycle = () => {
    if (playMode === "list") setPlayMode("shuffle");
    else if (playMode === "shuffle") setPlayMode("single");
    else setPlayMode("list");
  };

  const handleNext = () => {
    if (displaySongs.length === 0) return;
    let nextIndex = 0;
    
    if (playMode === "shuffle") {
      nextIndex = Math.floor(Math.random() * displaySongs.length);
    } else {
      const currentIndex = displaySongs.findIndex(s => s.id === playingSong?.id);
      nextIndex = (currentIndex + 1) % displaySongs.length;
    }
    
    handlePlaySong(displaySongs[nextIndex]);
  };

  const handlePrev = () => {
    if (displaySongs.length === 0) return;
    let prevIndex = 0;
    
    if (playMode === "shuffle") {
      prevIndex = Math.floor(Math.random() * displaySongs.length);
    } else {
      const currentIndex = displaySongs.findIndex(s => s.id === playingSong?.id);
      prevIndex = currentIndex <= 0 ? displaySongs.length - 1 : currentIndex - 1;
    }
    
    handlePlaySong(displaySongs[prevIndex]);
  };

  const handleSeek = (seekTime: number) => {
    if (audioRef.current) {
      audioRef.current.currentTime = seekTime;
      setCurrentTime(seekTime);
    }
  };

  const handleToggleTag = (tagId: number) => {
    if (selectedTags.includes(tagId)) {
      setSelectedTags(selectedTags.filter(id => id !== tagId));
    } else {
      setSelectedTags([...selectedTags, tagId]);
    }
  };

  return (
    <div className="app-container">
      <div className="ambient-glow glow-1"></div>
      <div className="ambient-glow glow-2"></div>

      {isMobile ? (
        <MobileLayout 
          songs={displaySongs}
          playlists={playlists}
          activePlaylistId={activePlaylistId}
          onSelectPlaylist={setActivePlaylistId}
          onCreatePlaylist={handleCreatePlaylist}
          onDeletePlaylist={handleDeletePlaylist}
          playingSong={playingSong}
          playingVersion={playingVersion}
          isPlaying={isPlaying}
          onPlaySong={handlePlaySong}
          onPlayPause={handlePlayPause}
          activeSong={activeSong}
          onSelectSong={setActiveSong}
          searchQuery={searchQuery}
          setSearchQuery={setSearchQuery}
          onOpenSettings={() => setIsSettingsOpen(true)}
          onOpenTagManager={() => setIsTagManagerOpen(true)}
          onImportFolder={handleImportFolder}
          onImportFiles={handleImportFiles}
          currentTime={currentTime}
          duration={duration}
          onSeek={handleSeek}
          volume={volume}
          onSetVolume={setVolume}
          playMode={playMode}
          onSetPlayMode={setPlayMode}
          onPrev={handlePrev}
          onNext={handleNext}
          allTags={tags}
          onBindTag={handleBindTag}
          onUnbindTag={handleUnbindTag}
          onSetPrimaryVersion={handleSetPrimaryVersion}
          onToggleVersionStatus={handleToggleVersionStatus}
          onExportVersion={handleExportVersion}
          onDeleteVersion={handleDeleteVersion}
          onImportVersionForSong={handleImportVersionForSong}
          onUpdateMetadata={handleUpdateSongMetadata}
        />
      ) : (
        <>
          <Sidebar 
            playlists={playlists}
            activePlaylistId={activePlaylistId}
            onSelectPlaylist={setActivePlaylistId}
            onCreatePlaylist={handleCreatePlaylist}
            onRenamePlaylist={handleRenamePlaylist}
            onDeletePlaylist={handleDeletePlaylist}
            allSongsCount={songs.length}
            onOpenSettings={() => setIsSettingsOpen(true)}
          />

          <div className="glass-panel main-content">
            <div className="header-row" style={{ marginBottom: '12px' }}>
              <div className="search-container" style={{ width: '450px' }}>
                <Search className="search-icon" size={18} />
                <input 
                  type="text" 
                  placeholder="搜索歌曲、歌手、专辑..." 
                  className="search-input"
                  value={searchQuery}
                  onChange={e => setSearchQuery(e.target.value)}
                />
              </div>
              <div style={{ position: "absolute", right: 0 }}>
                <button 
                  className="import-btn" 
                  onClick={(e) => { e.stopPropagation(); setShowImportDropdown(!showImportDropdown); }} 
                  title="导入本地音乐"
                >
                  <FolderPlus size={16} /> 导入歌曲
                </button>
                {showImportDropdown && (
                  <div 
                    className="context-menu glass-panel" 
                    style={{ 
                      position: "absolute", 
                      right: 0, 
                      top: "100%", 
                      marginTop: "6px", 
                      width: "160px",
                      zIndex: 1002 
                    }}
                    onClick={() => setShowImportDropdown(false)}
                  >
                    <div className="context-menu-item" onClick={handleImportFolder}>
                      <Folder size={14} /> 导入整个文件夹
                    </div>
                    <div className="context-menu-item" onClick={handleImportFiles}>
                      <FileAudio size={14} /> 导入多个音源文件
                    </div>
                  </div>
                )}
              </div>
            </div>

            <TagFilter 
              tags={tags}
              selectedTags={selectedTags}
              onToggleTag={handleToggleTag}
              filterMode={filterMode}
              onSetFilterMode={setFilterMode}
              isTagsExpanded={isTagsExpanded}
              onSetTagsExpanded={setIsTagsExpanded}
              onOpenTagManager={() => setIsTagManagerOpen(true)}
            />

            <SongTable 
              songs={displaySongs}
              activeSong={activeSong}
              onSelectSong={(song) => {
                setActiveSong(song);
                setIsDetailOpen(true);
              }}
              playingSong={playingSong}
              isPlaying={isPlaying}
              onPlaySong={handlePlaySong}
              onPlayPause={handlePlayPause}
              selectedSongIds={selectedSongIds}
              onSetSelectedSongIds={setSelectedSongIds}
              playlists={playlists}
              activePlaylistId={activePlaylistId}
              onAddSongsToPlaylist={handleAddSongsToPlaylist}
              onRemoveSongsFromPlaylist={handleRemoveSongsFromPlaylist}
              onDeleteSongs={handleDeleteSongs}
              clipboard={clipboard}
              onSetClipboard={setClipboard}
              onPasteSongs={handlePasteSongs}
            />

            {isDetailOpen && (
              <div className="drawer-overlay" onClick={() => setIsDetailOpen(false)} />
            )}

            <DetailPane 
              isOpen={isDetailOpen}
              onClose={() => setIsDetailOpen(false)}
              activeSong={activeSong}
              activeTab={activeTab}
              onSetActiveTab={setActiveTab}
              playingVersion={playingVersion}
              isPlaying={isPlaying}
              onPlayVersion={handlePlayVersion}
              allTags={tags}
              onBindTag={handleBindTag}
              onUnbindTag={handleUnbindTag}
              onSetPrimaryVersion={handleSetPrimaryVersion}
              onToggleVersionStatus={handleToggleVersionStatus}
              onExportVersion={handleExportVersion}
              onDeleteVersion={handleDeleteVersion}
              onImportVersionForSong={handleImportVersionForSong}
              onUpdateMetadata={handleUpdateSongMetadata}
            />
            
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

          <PlayBar 
            canvasRef={canvasRef}
            playingSong={playingSong}
            playingVersion={playingVersion}
            isPlaying={isPlaying}
            currentTime={currentTime}
            duration={duration}
            volume={volume}
            playMode={playMode}
            isLyricsOverlayOpen={isLyricsOverlayOpen}
            onSetLyricsOverlayOpen={setIsLyricsOverlayOpen}
            onPlayPause={handlePlayPause}
            onPrev={handlePrev}
            onNext={handleNext}
            onPlaybackModeCycle={handlePlaybackModeCycle}
            onSeek={handleSeek}
            onVolumeChange={setVolume}
          />
        </>
      )}

      <TagManagerModal 
        isOpen={isTagManagerOpen}
        onClose={() => setIsTagManagerOpen(false)}
        tags={tags}
        newTagName={newTagName}
        setNewTagName={setNewTagName}
        newTagColor={newTagColor}
        setNewTagColor={setNewTagColor}
        newTagCategory={newTagCategory}
        setNewTagCategory={setNewTagCategory}
        presetColors={PRESET_COLORS}
        onCreateTag={handleCreateTag}
        onDeleteTag={handleDeleteTag}
      />

      <SettingsModal 
        isOpen={isSettingsOpen}
        onClose={() => setIsSettingsOpen(false)}
        theme={theme}
        setTheme={setTheme}
        libraryPath={libraryPath}
        onResetLibrary={handleResetLibrary}
      />

      {isImporting && (
        <div className="loader-overlay">
          <div className="spinner"></div>
          <span style={{ fontSize: "1.1rem", fontWeight: 600 }}>{importProgress}</span>
        </div>
      )}

      {toast && <Toast message={toast.message} type={toast.type} />}

      <audio
        ref={audioRef}
        crossOrigin="anonymous"
        onTimeUpdate={handleTimeUpdate}
        onLoadedMetadata={handleLoadedMetadata}
        onEnded={handleEnded}
      />

      {needsInit && (
        <div style={{ position: "fixed", top: 0, left: 0, right: 0, bottom: 0, background: "var(--bg-main)", zIndex: 9999, display: "flex", flexDirection: "column", justifyContent: "center", alignItems: "center", padding: "24px" }}>
          <div style={{ maxWidth: "400px", width: "100%", background: "var(--bg-panel)", borderRadius: "16px", padding: "32px 24px", textAlign: "center", border: "1px solid var(--border)", boxShadow: "0 20px 40px rgba(0,0,0,0.4)" }}>
            <div style={{ width: "80px", height: "80px", background: "linear-gradient(135deg, var(--accent), #f59e0b)", borderRadius: "50%", margin: "0 auto 24px auto", display: "flex", justifyContent: "center", alignItems: "center", color: "#fff" }}>
              <FolderPlus size={40} />
            </div>
            <h2 style={{ fontSize: "1.5rem", fontWeight: "bold", marginBottom: "16px", background: "linear-gradient(135deg, var(--accent), #f59e0b)", WebkitBackgroundClip: "text", WebkitTextFillColor: "transparent" }}>
              欢迎使用 Aetheria
            </h2>
            <p style={{ color: "var(--text-muted)", fontSize: "0.95rem", marginBottom: "32px", lineHeight: 1.5 }}>
              在开始之前，请选择一个本地文件夹作为您的音乐库数据库目录。我们将会在此文件夹中保存所有的数据。
            </p>
            <button
              onClick={async () => {
                try {
                  const selectedPath = await invoke<string | null>("select_directory");
                  if (selectedPath) {
                    await invoke("initialize_library_path", { path: selectedPath });
                    setNeedsInit(false);
                    loadLibrary();
                    fetchPlaylists();
                    showToast("数据库初始化成功！");
                  }
                } catch (err) {
                  showToast("初始化失败: " + err, "error");
                }
              }}
              style={{ width: "100%", padding: "14px", background: "var(--accent)", color: "#fff", border: "none", borderRadius: "12px", fontSize: "1rem", fontWeight: "bold", cursor: "pointer", transition: "all 0.2s" }}
              onMouseOver={e => e.currentTarget.style.transform = "scale(1.02)"}
              onMouseOut={e => e.currentTarget.style.transform = "scale(1)"}
            >
              选择文件夹
            </button>
          </div>
        </div>
      )}

      <ImportPreviewModal 
        isOpen={isPreviewOpen}
        onClose={() => setIsPreviewOpen(false)}
        filesToImport={filesToPreview}
        onConfirm={handleConfirmImport}
      />
    </div>
  );
}

export default App;
