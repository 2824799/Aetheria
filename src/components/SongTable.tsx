import { useState, useEffect, useRef } from "react";
import { Play, Pause, Copy, Scissors, ClipboardPaste, Plus, Trash2, ArrowRight } from "lucide-react";

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

interface SongTableProps {
  songs: Song[];
  activeSong: Song | null;
  onSelectSong: (song: Song) => void;
  playingSong: Song | null;
  isPlaying: boolean;
  onPlaySong: (song: Song) => void;
  onPlayPause: () => void;
  selectedSongIds: string[];
  onSetSelectedSongIds: (ids: string[]) => void;
  playlists: Playlist[];
  activePlaylistId: string | null;
  onAddSongsToPlaylist: (playlistId: string, songIds: string[]) => void;
  onRemoveSongsFromPlaylist: (playlistId: string, songIds: string[]) => void;
  clipboard: Clipboard | null;
  onSetClipboard: (clip: Clipboard | null) => void;
  onPasteSongs: (playlistId: string) => void;
}

interface ContextMenu {
  visible: boolean;
  x: number;
  y: number;
  targetSongIds: string[];
}

export default function SongTable({
  songs,
  activeSong,
  onSelectSong,
  playingSong,
  isPlaying,
  onPlaySong,
  onPlayPause,
  selectedSongIds,
  onSetSelectedSongIds,
  playlists,
  activePlaylistId,
  onAddSongsToPlaylist,
  onRemoveSongsFromPlaylist,
  clipboard,
  onSetClipboard,
  onPasteSongs,
}: SongTableProps) {
  // 框选相关的鼠标状态
  const [isSelecting, setIsSelecting] = useState(false);
  const [boxStart, setBoxStart] = useState({ x: 0, y: 0 });
  const [boxCurrent, setBoxCurrent] = useState({ x: 0, y: 0 });
  
  // 自定义右键菜单状态
  const [contextMenu, setContextMenu] = useState<ContextMenu | null>(null);

  const containerRef = useRef<HTMLDivElement | null>(null);
  const selectionBoxRef = useRef<HTMLDivElement | null>(null);
  const lastSelectedIndexRef = useRef<number>(-1);

  // 监听全局点击事件，用于关闭右键菜单
  useEffect(() => {
    const closeMenu = () => setContextMenu(null);
    window.addEventListener("click", closeMenu);
    return () => window.removeEventListener("click", closeMenu);
  }, []);

  // 1. 鼠标点击歌曲行（处理 Shift/Ctrl 选择与阻止侧滑抽屉弹出冲突）
  const handleRowClick = (e: React.MouseEvent, song: Song, index: number) => {
    // 只有在没有摁住 Ctrl/Shift 键的情况下，才触发展开详情抽屉
    const isModifierPressed = e.ctrlKey || e.metaKey || e.shiftKey;
    if (!isModifierPressed) {
      onSelectSong(song);
    }

    let newSelected = [...selectedSongIds];

    if (e.ctrlKey || e.metaKey) {
      // Ctrl 键：多选切换
      if (newSelected.includes(song.id)) {
        newSelected = newSelected.filter(id => id !== song.id);
      } else {
        newSelected.push(song.id);
      }
      lastSelectedIndexRef.current = index;
    } else if (e.shiftKey && lastSelectedIndexRef.current !== -1) {
      // Shift 键：范围选择
      const start = Math.min(lastSelectedIndexRef.current, index);
      const end = Math.max(lastSelectedIndexRef.current, index);
      const rangeIds = songs.slice(start, end + 1).map(s => s.id);
      
      // 合并目前选中的和范围选中的（去重）
      const set = new Set([...newSelected, ...rangeIds]);
      newSelected = Array.from(set);
    } else {
      // 普通单选
      newSelected = [song.id];
      lastSelectedIndexRef.current = index;
    }

    onSetSelectedSongIds(newSelected);
  };

  // 2. 框选拖拽鼠标按下，注册全局事件监听解决拖动出容器松开卡死 bug
  const handleTableMouseDown = (e: React.MouseEvent<HTMLDivElement>) => {
    const target = e.target as HTMLElement;
    if (target.closest(".play-row-btn") || target.closest(".ctrl-btn") || target.closest(".action-btn-sm") || target.closest(".tag-pill") || target.closest(".context-menu")) {
      return;
    }
    
    if (e.button === 2) return;

    if (!containerRef.current) return;
    const rect = containerRef.current.getBoundingClientRect();
    
    const startX = e.clientX - rect.left + containerRef.current.scrollLeft;
    const startY = e.clientY - rect.top + containerRef.current.scrollTop;
    
    setIsSelecting(true);
    setBoxStart({ x: startX, y: startY });
    setBoxCurrent({ x: startX, y: startY });

    if (!e.ctrlKey && !e.shiftKey) {
      onSetSelectedSongIds([]);
    }

    // 绑定至 window 的移动和弹起事件，实现全局松手结算
    const handleWindowMouseMove = (moveEvent: MouseEvent) => {
      if (!containerRef.current) return;
      const cRect = containerRef.current.getBoundingClientRect();
      const currentX = moveEvent.clientX - cRect.left + containerRef.current.scrollLeft;
      const currentY = moveEvent.clientY - cRect.top + containerRef.current.scrollTop;
      
      setBoxCurrent({ x: currentX, y: currentY });

      // 局部延迟以防检测过于高频卡顿
      setTimeout(() => {
        if (!selectionBoxRef.current || !containerRef.current) return;
        const boxBounds = selectionBoxRef.current.getBoundingClientRect();
        const rows = containerRef.current.querySelectorAll(".song-row");
        
        const intersectedIds: string[] = [];
        rows.forEach(row => {
          const rowBounds = row.getBoundingClientRect();
          const intersect = !(
            rowBounds.right < boxBounds.left ||
            rowBounds.left > boxBounds.right ||
            rowBounds.bottom < boxBounds.top ||
            rowBounds.top > boxBounds.bottom
          );
          if (intersect) {
            const id = row.getAttribute("data-song-id");
            if (id) intersectedIds.push(id);
          }
        });

        if (moveEvent.ctrlKey) {
          const merged = Array.from(new Set([...selectedSongIds, ...intersectedIds]));
          onSetSelectedSongIds(merged);
        } else {
          onSetSelectedSongIds(intersectedIds);
        }
      }, 10);
    };

    const handleWindowMouseUp = () => {
      setIsSelecting(false);
      window.removeEventListener("mousemove", handleWindowMouseMove);
      window.removeEventListener("mouseup", handleWindowMouseUp);
    };

    window.addEventListener("mousemove", handleWindowMouseMove);
    window.addEventListener("mouseup", handleWindowMouseUp);
  };

  // 5. 行右键菜单触发（改为相对于容器定位，修复菜单位置随侧栏平移偏差 Bug）
  const handleRowContextMenu = (e: React.MouseEvent, songId: string) => {
    e.preventDefault();
    e.stopPropagation();

    let targetIds = [...selectedSongIds];
    if (!targetIds.includes(songId)) {
      targetIds = [songId];
      onSetSelectedSongIds(targetIds);
      const song = songs.find(s => s.id === songId);
      if (song) onSelectSong(song);
    }

    if (!containerRef.current) return;
    const rect = containerRef.current.getBoundingClientRect();
    const x = e.clientX - rect.left + containerRef.current.scrollLeft;
    const y = e.clientY - rect.top + containerRef.current.scrollTop;

    setContextMenu({
      visible: true,
      x,
      y,
      targetSongIds: targetIds,
    });
  };

  // 6. 空白处右键菜单触发
  const handleTableContextMenu = (e: React.MouseEvent) => {
    e.preventDefault();
    if (!clipboard) return;

    if (!containerRef.current) return;
    const rect = containerRef.current.getBoundingClientRect();
    const x = e.clientX - rect.left + containerRef.current.scrollLeft;
    const y = e.clientY - rect.top + containerRef.current.scrollTop;

    setContextMenu({
      visible: true,
      x,
      y,
      targetSongIds: [],
    });
  };

  // 7. 上下文功能命令执行
  const handleCommand = (cmd: "copy" | "cut" | "remove" | "paste" | string) => {
    setContextMenu(null);

    if (cmd === "copy" || cmd === "cut") {
      onSetClipboard({
        type: cmd,
        songIds: contextMenu?.targetSongIds || [],
        sourcePlaylistId: activePlaylistId,
      });
    } else if (cmd === "remove") {
      if (activePlaylistId && contextMenu?.targetSongIds.length) {
        onRemoveSongsFromPlaylist(activePlaylistId, contextMenu.targetSongIds);
      }
    } else if (cmd === "paste") {
      if (activePlaylistId) {
        onPasteSongs(activePlaylistId);
      }
    } else if (cmd.startsWith("add-to-")) {
      const playlistId = cmd.replace("add-to-", "");
      if (contextMenu?.targetSongIds.length) {
        onAddSongsToPlaylist(playlistId, contextMenu.targetSongIds);
      }
    }
  };

  return (
    <div 
      ref={containerRef}
      className="song-list-container"
      onMouseDown={handleTableMouseDown}
      onContextMenu={handleTableContextMenu}
      style={{ position: "relative" }}
    >
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
          {songs.map((song, index) => {
            const isCurrentlyPlaying = playingSong?.id === song.id;
            const isSelected = selectedSongIds.includes(song.id);
            const primaryVersion = song.versions.find(v => v.is_primary);
            const activeFormat = primaryVersion?.format.toUpperCase() || "未知";
            
            return (
              <tr 
                key={song.id} 
                data-song-id={song.id}
                className={`song-row ${isCurrentlyPlaying ? "playing" : ""} ${activeSong?.id === song.id ? "active" : ""} ${isSelected ? "selected" : ""}`}
                onClick={(e) => handleRowClick(e, song, index)}
                onDoubleClick={() => onPlaySong(song)}
                onContextMenu={(e) => handleRowContextMenu(e, song.id)}
              >
                {/* 拦截点击事件以提升直接播放反馈 */}
                <td onClick={(e) => {
                  e.stopPropagation();
                  if (isCurrentlyPlaying) {
                    onPlayPause();
                  } else {
                    onPlaySong(song);
                  }
                }}>
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
          {songs.length === 0 && (
            <tr>
              <td colSpan={6} style={{ textAlign: "center", padding: "40px", color: "var(--text-sub)" }}>
                没有找到符合条件的歌曲，请导入或调整过滤器
              </td>
            </tr>
          )}
        </tbody>
      </table>

      {/* 动态框选框组件 */}
      {isSelecting && (
        <div 
          ref={selectionBoxRef}
          className="selection-box"
          style={{
            left: Math.min(boxStart.x, boxCurrent.x),
            top: Math.min(boxStart.y, boxCurrent.y),
            width: Math.abs(boxStart.x - boxCurrent.x),
            height: Math.abs(boxStart.y - boxCurrent.y)
          }}
        />
      )}

      {/* 自定义毛玻璃右键级联菜单 - 定位修改为 absolute 相对于容器，解决坐标漂移问题 */}
      {contextMenu?.visible && (
        <div 
          className="context-menu glass-panel"
          style={{ 
            left: contextMenu.x, 
            top: contextMenu.y,
            position: "absolute",
            zIndex: 1000
          }}
          onClick={e => e.stopPropagation()}
        >
          {contextMenu.targetSongIds.length > 0 ? (
            <>
              <div className="context-menu-item" onClick={() => handleCommand("copy")}>
                <Copy size={14} /> 复制所选歌曲
              </div>
              <div className="context-menu-item" onClick={() => handleCommand("cut")}>
                <Scissors size={14} /> 剪切所选歌曲
              </div>
              {activePlaylistId && (
                <div className="context-menu-item" onClick={() => handleCommand("remove")}>
                  <Trash2 size={14} style={{ color: "#ef4444" }} /> 从当前歌单移除
                </div>
              )}
              
              {/* 二级联动子菜单：添加到歌单 */}
              {playlists.length > 0 && (
                <div className="context-menu-item cascade-trigger">
                  <Plus size={14} /> 添加到歌单 <ArrowRight size={12} style={{ marginLeft: "auto" }} />
                  <div className="cascade-menu glass-panel">
                    {playlists.map(pl => (
                      <div 
                        key={pl.id} 
                        className="context-menu-item"
                        onClick={() => handleCommand(`add-to-${pl.id}`)}
                      >
                        {pl.name}
                      </div>
                    ))}
                  </div>
                </div>
              )}
            </>
          ) : (
            // 空白区域右键菜单：粘贴
            clipboard && (
              <div className="context-menu-item" onClick={() => handleCommand("paste")}>
                <ClipboardPaste size={14} /> 粘贴歌曲 ({clipboard.songIds.length} 首)
              </div>
            )
          )}
        </div>
      )}
    </div>
  );
}
