import { useState, useEffect } from "react";
import { 
  Play, Pause, SkipBack, SkipForward, Music, Settings, Tags, FolderPlus, 
  ChevronDown, Volume2, Repeat, Shuffle, Plus, Trash2, Download, Menu, MoreHorizontal,
  CheckSquare, Square
} from "lucide-react";
import TagFilter from "./TagFilter";

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

interface MobileLayoutProps {
  songs: Song[];
  playlists: Playlist[];
  activePlaylistId: string | null;
  onSelectPlaylist: (id: string | null) => void;
  onCreatePlaylist: (name: string) => void;
  onDeletePlaylist: (id: string) => void;
  
  playingSong: Song | null;
  playingVersion: AudioVersion | null;
  isPlaying: boolean;
  onPlaySong: (song: Song) => void;
  onPlayPause: () => void;
  
  activeSong: Song | null;
  onSelectSong: (song: Song) => void;
  
  searchQuery: string;
  setSearchQuery: (query: string) => void;
  
  onOpenSettings: () => void;
  onOpenTagManager: () => void;
  onImportFolder: () => void;
  onImportFiles: () => void;
  
  currentTime: number;
  duration: number;
  onSeek: (time: number) => void;
  volume: number;
  onSetVolume: (vol: number) => void;
  playMode: "list" | "single" | "shuffle";
  onSetPlayMode: (mode: "list" | "single" | "shuffle") => void;
  onPrev: () => void;
  onNext: () => void;

  allTags: Tag[];
  onBindTag: (songId: string, tagId: number) => void;
  onUnbindTag: (songId: string, tagId: number) => void;
  onSetPrimaryVersion: (versionId: string) => void;
  onToggleVersionStatus: (versionId: string, active: boolean) => void;
  onExportVersion: (versionId: string) => void;
  onDeleteVersion: (versionId: string) => void;
  onImportVersionForSong: (songId: string) => void;
  onUpdateMetadata: (songId: string, title: string, artist: string) => void;
  onAddSongsToPlaylist: (playlistId: string, songIds: string[]) => void;
  onRemoveSongsFromPlaylist: (playlistId: string, songIds: string[]) => void;
  onDeleteSongs: (songIds: string[]) => void;
  
  selectedTags: number[];
  onToggleTag: (id: number) => void;
  filterMode: "AND" | "OR";
  onSetFilterMode: (mode: "AND" | "OR") => void;
  isTagsExpanded: boolean;
  onSetTagsExpanded: (expanded: boolean) => void;
}

export default function MobileLayout({
  songs,
  playlists,
  activePlaylistId,
  onSelectPlaylist,
  playingSong,
  isPlaying,
  onPlaySong,
  onPlayPause,
  activeSong,
  onSelectSong,
  searchQuery,
  setSearchQuery,
  onOpenSettings,
  onOpenTagManager,
  onImportFolder,
  onImportFiles,
  currentTime,
  duration,
  onSeek,
  volume,
  onSetVolume,
  playMode,
  onSetPlayMode,
  onPrev,
  onNext,
  allTags,
  onBindTag,
  onUnbindTag,
  onSetPrimaryVersion,
  onToggleVersionStatus,
  onExportVersion,
  onDeleteVersion,
  onImportVersionForSong,
  onUpdateMetadata,
  onAddSongsToPlaylist,
  onRemoveSongsFromPlaylist,
  onDeleteSongs,
  selectedTags,
  onToggleTag,
  filterMode,
  onSetFilterMode,
  isTagsExpanded,
  onSetTagsExpanded,
}: MobileLayoutProps) {
  const [isPlayerExpanded, setIsPlayerExpanded] = useState(false);
  const [isSongDetailOpen, setIsSongDetailOpen] = useState(false);
  const [isPlaylistDrawerOpen, setIsPlaylistDrawerOpen] = useState(false);
  const [mobileTab, setMobileTab] = useState<"versions" | "tags" | "lyrics">("versions");
  const [contextMenuSong, setContextMenuSong] = useState<Song | null>(null);
  
  // 详情面板的可编辑状态
  const [editTitle, setEditTitle] = useState("");
  const [editArtist, setEditArtist] = useState("");

  useEffect(() => {
    if (activeSong) {
      setEditTitle(activeSong.title);
      setEditArtist(activeSong.artist || "未知歌手");
    }
  }, [activeSong]);

  const handleSaveMetadata = () => {
    if (activeSong) {
      const titleToSave = editTitle.trim();
      const artistToSave = editArtist.trim() === "未知歌手" ? "" : editArtist.trim();
      if (titleToSave && (titleToSave !== activeSong.title || artistToSave !== (activeSong.artist || ""))) {
        onUpdateMetadata(activeSong.id, titleToSave, artistToSave);
      }
    }
  };

  const formatTime = (secs: number) => {
    if (isNaN(secs)) return "0:00";
    const m = Math.floor(secs / 60);
    const s = Math.floor(secs % 60);
    return `${m}:${s < 10 ? "0" : ""}${s}`;
  };

  // 计算播放进度条百分比
  const progressPercent = duration > 0 ? (currentTime / duration) * 100 : 0;

  return (
    <div className="mobile-layout" style={{ display: "flex", flexDirection: "column", height: "100vh", overflow: "hidden", background: "var(--bg-app)", color: "var(--text-main)" }}>
      
      {/* 顶部标题与快速控制 */}
      <div style={{ padding: "16px 16px 8px 16px", display: "flex", justifyContent: "space-between", alignItems: "center", borderBottom: "1px solid var(--border-light)", position: "relative" }}>
        <div style={{ display: "flex", alignItems: "center", gap: "12px" }}>
          <button className="ctrl-btn" onClick={() => setIsPlaylistDrawerOpen(true)} title="歌单"><Menu size={22} /></button>
          <h1 style={{ fontSize: "1.3rem", fontWeight: "bold", background: "linear-gradient(135deg, var(--accent), #f59e0b)", WebkitBackgroundClip: "text", WebkitTextFillColor: "transparent" }}>
            Aetheria
          </h1>
        </div>
        <div style={{ display: "flex", gap: "10px" }}>
          <button className="ctrl-btn" onClick={onOpenTagManager} title="标签管理"><Tags size={20} /></button>
          <button className="ctrl-btn" onClick={onOpenSettings} title="设置"><Settings size={20} /></button>
        </div>
      </div>

      {/* 搜索栏 */}
      <div style={{ padding: "8px 16px" }}>
        <input 
          type="text" 
          placeholder="搜索歌名、歌手或格式..." 
          value={searchQuery}
          onChange={e => setSearchQuery(e.target.value)}
          style={{ width: "100%", padding: "10px 14px", borderRadius: "20px", border: "1px solid var(--border)", background: "var(--bg-panel)", color: "var(--text-main)", outline: "none", fontSize: "0.9rem" }}
        />
      </div>

      {/* 音频导入操作按钮组 */}
      <div style={{ display: "flex", gap: "8px", padding: "4px 16px" }}>
        <button className="import-btn" style={{ flex: 1, padding: "8px", fontSize: "0.8rem", display: "flex", gap: "6px", justifyContent: "center", alignItems: "center" }} onClick={onImportFiles}>
          <FolderPlus size={14} /> 导入单歌
        </button>
        <button className="import-btn" style={{ flex: 1, padding: "8px", fontSize: "0.8rem", display: "flex", gap: "6px", justifyContent: "center", alignItems: "center" }} onClick={onImportFolder}>
          <FolderPlus size={14} /> 导入目录
        </button>
      </div>

      {/* 标签折叠多维筛选面板 */}
      <div style={{ padding: "8px 16px", margin: "4px 16px", background: "var(--bg-panel)", borderRadius: "12px", border: "1px solid var(--accent-glow)" }}>
        <TagFilter 
          tags={allTags}
          selectedTags={selectedTags}
          onToggleTag={onToggleTag}
          filterMode={filterMode}
          onSetFilterMode={onSetFilterMode}
          isTagsExpanded={isTagsExpanded}
          onSetTagsExpanded={onSetTagsExpanded}
          onOpenTagManager={onOpenTagManager}
        />
      </div>

      {/* 歌曲列表区域 */}
      <div style={{ flex: 1, overflowY: "auto", padding: "10px 16px", display: "flex", flexDirection: "column", gap: "6px" }}>
        {songs.map(song => {
          const isCurrentlyPlaying = playingSong?.id === song.id;
          const isActive = activeSong?.id === song.id;
          const primary = song.versions.find(v => v.is_primary);
          const formatText = primary ? primary.format.toUpperCase() : "无源";
          
          return (
            <div 
              key={song.id}
              onClick={() => { onSelectSong(song); onPlaySong(song); }}
              style={{
                display: "flex",
                alignItems: "center",
                justifyContent: "space-between",
                padding: "10px 12px",
                borderRadius: "8px",
                background: isActive ? "var(--bg-hover)" : "var(--bg-panel)",
                borderLeft: isCurrentlyPlaying ? "4px solid var(--accent)" : "4px solid transparent",
                transition: "all 0.15s",
                cursor: "pointer"
              }}
            >
              <div style={{ display: "flex", flexDirection: "column", gap: "2px", flex: 1, overflow: "hidden" }}>
                <span style={{ fontWeight: 600, fontSize: "0.95rem", color: isCurrentlyPlaying ? "var(--accent)" : "var(--text-main)", textOverflow: "ellipsis", overflow: "hidden", whiteSpace: "nowrap" }}>
                  {song.title}
                </span>
                <div style={{ display: "flex", alignItems: "center", gap: "6px", textOverflow: "ellipsis", overflow: "hidden", whiteSpace: "nowrap" }}>
                  <span style={{ fontSize: "0.78rem", color: "var(--text-sub)" }}>
                    {song.artist || "未知歌手"}
                  </span>
                  <span style={{ fontSize: "0.68rem", padding: "1px 4px", background: "var(--border)", borderRadius: "4px", color: "var(--text-main)" }}>
                    {formatText}
                  </span>
                  {primary && (
                    <>
                      {primary.bit_depth && (
                        <span style={{ fontSize: "0.68rem", padding: "1px 4px", background: "var(--border)", borderRadius: "4px", color: "var(--text-main)" }}>
                          {primary.bit_depth}bit
                        </span>
                      )}
                      {primary.sample_rate && (
                        <span style={{ fontSize: "0.68rem", padding: "1px 4px", background: "var(--border)", borderRadius: "4px", color: "var(--text-main)" }}>
                          {(primary.sample_rate / 1000).toFixed(primary.sample_rate % 1000 === 0 ? 0 : 1)}kHz
                        </span>
                      )}
                      {primary.bitrate && (
                        <span style={{ fontSize: "0.68rem", padding: "1px 4px", background: "var(--border)", borderRadius: "4px", color: "var(--text-main)" }}>
                          {Math.round(primary.bitrate / 1000)}kbps
                        </span>
                      )}
                    </>
                  )}
                  {song.tags.slice(0, 2).map(t => (
                    <span key={t.id} style={{ fontSize: "0.68rem", color: t.color }}>#{t.name}</span>
                  ))}
                </div>
              </div>

              <div style={{ display: "flex", alignItems: "center", gap: "10px" }}>
                <button 
                  className="ctrl-btn" 
                  onClick={(e) => {
                    e.stopPropagation();
                    setContextMenuSong(song);
                  }}
                  style={{ color: "var(--text-muted)" }}
                >
                  <MoreHorizontal size={20} />
                </button>
              </div>
            </div>
          );
        })}
        {songs.length === 0 && (
          <div style={{ textAlign: "center", padding: "40px 10px", color: "var(--text-sub)", fontSize: "0.85rem" }}>
            暂无歌曲，请点击上方按钮导入音源
          </div>
        )}
      </div>

      {/* 底部悬浮迷你播放栏 (Spotify/Apple Music 风格) */}
      {playingSong && (
        <div 
          onClick={() => setIsPlayerExpanded(true)}
          style={{
            margin: "8px 12px 12px 12px",
            padding: "10px 14px",
            borderRadius: "12px",
            background: "var(--bg-panel)",
            border: "1px solid var(--border)",
            boxShadow: "0 8px 32px var(--shadow)",
            backdropFilter: "blur(20px)",
            display: "flex",
            alignItems: "center",
            justifyContent: "space-between",
            cursor: "pointer",
            position: "relative"
          }}
        >
          {/* 进度条底线反馈 */}
          <div style={{ position: "absolute", bottom: 0, left: "12px", right: "12px", height: "2px", background: "var(--border-light)" }}>
            <div style={{ height: "100%", width: `${progressPercent}%`, background: "var(--accent)", transition: "width 0.1s linear" }} />
          </div>

          <div style={{ display: "flex", alignItems: "center", gap: "10px", overflow: "hidden", flex: 1 }}>
            <div style={{ width: "36px", height: "36px", borderRadius: "6px", background: "var(--accent-glow)", display: "flex", alignItems: "center", justifyContent: "center", color: "var(--accent)" }}>
              <Music size={18} />
            </div>
            <div style={{ display: "flex", flexDirection: "column", overflow: "hidden" }}>
              <span style={{ fontSize: "0.88rem", fontWeight: 600, color: "var(--text-main)", textOverflow: "ellipsis", overflow: "hidden", whiteSpace: "nowrap" }}>
                {playingSong.title}
              </span>
              <span style={{ fontSize: "0.75rem", color: "var(--text-sub)", textOverflow: "ellipsis", overflow: "hidden", whiteSpace: "nowrap" }}>
                {playingSong.artist || "未知歌手"}
              </span>
            </div>
          </div>

          <div style={{ display: "flex", alignItems: "center", gap: "8px" }} onClick={e => e.stopPropagation()}>
            <button className="ctrl-btn" onClick={onPlayPause} style={{ color: "var(--accent)" }}>
              {isPlaying ? <Pause size={22} /> : <Play size={22} />}
            </button>
            <button className="ctrl-btn" onClick={onNext}>
              <SkipForward size={20} />
            </button>
          </div>
        </div>
      )}

      {/* 侧滑歌单抽屉 (Playlist Drawer) - 从左边滑出，且带背景模糊 */}
      {isPlaylistDrawerOpen && (
        <div style={{ position: "fixed", top: 0, left: 0, right: 0, bottom: 0, zIndex: 110, display: "flex" }}>
          <div style={{ width: "260px", background: "var(--bg-panel)", height: "100%", boxShadow: "4px 0 20px rgba(0,0,0,0.2)", display: "flex", flexDirection: "column", padding: "16px", animation: "slideLeft 0.3s cubic-bezier(0.2, 0.8, 0.2, 1)" }}>
            <h2 style={{ fontSize: "1.2rem", fontWeight: "bold", marginBottom: "20px" }}>我的歌单</h2>
            <div style={{ display: "flex", flexDirection: "column", gap: "10px", flex: 1, overflowY: "auto" }}>
              <div 
                onClick={() => { onSelectPlaylist(null); setIsPlaylistDrawerOpen(false); }}
                style={{ padding: "12px", borderRadius: "8px", background: activePlaylistId === null ? "var(--bg-hover)" : "transparent", color: activePlaylistId === null ? "var(--accent)" : "var(--text-main)", fontWeight: activePlaylistId === null ? 600 : 400, cursor: "pointer", display: "flex", justifyContent: "space-between" }}
              >
                <span>全部音乐</span>
                <span style={{ color: "var(--text-muted)" }}>{songs.length}</span>
              </div>
              {playlists.map(pl => (
                <div 
                  key={pl.id}
                  onClick={() => { onSelectPlaylist(pl.id); setIsPlaylistDrawerOpen(false); }}
                  style={{ padding: "12px", borderRadius: "8px", background: activePlaylistId === pl.id ? "var(--bg-hover)" : "transparent", color: activePlaylistId === pl.id ? "var(--accent)" : "var(--text-main)", fontWeight: activePlaylistId === pl.id ? 600 : 400, cursor: "pointer" }}
                >
                  {pl.name}
                </div>
              ))}
            </div>
          </div>
          <div style={{ flex: 1, background: "rgba(0,0,0,0.4)", backdropFilter: "blur(8px)" }} onClick={() => setIsPlaylistDrawerOpen(false)} />
        </div>
      )}

      {/* 歌曲详情抽屉 (Song Detail Overlay) */}
      {isSongDetailOpen && activeSong && (
        <div style={{ position: "fixed", top: 0, left: 0, right: 0, bottom: 0, background: "var(--bg-app)", zIndex: 100, display: "flex", flexDirection: "column", animation: "slideUp 0.35s cubic-bezier(0.2, 0.8, 0.2, 1)" }}>
          
          <div style={{ display: "flex", justifyContent: "space-between", padding: "16px", alignItems: "center", borderBottom: "1px solid var(--border-light)" }}>
            <button className="ctrl-btn" onClick={() => setIsSongDetailOpen(false)}><ChevronDown size={28} /></button>
            <span style={{ fontSize: "0.95rem", fontWeight: 600, color: "var(--text-sub)" }}>歌曲详情</span>
            <div style={{ width: 28 }} />
          </div>

          {/* 动态封面发光组件 */}
          <div style={{ flex: 1.2, display: "flex", flexDirection: "column", alignItems: "center", justifyContent: "center", padding: "10px 24px" }}>
            <div 
              style={{
                width: "200px",
                height: "200px",
                borderRadius: "20px",
                background: "var(--accent-glow)",
                display: "flex",
                alignItems: "center",
                justifyContent: "center",
                color: "var(--accent)",
                position: "relative",
                boxShadow: "0 20px 50px var(--shadow)"
              }}
            >
              <div 
                style={{
                  position: "absolute",
                  top: 0, right: 0, bottom: 0, left: 0,
                  borderRadius: "20px",
                  background: "radial-gradient(circle, var(--accent) 0%, transparent 70%)",
                  opacity: 0.15,
                  filter: "blur(20px)"
                }}
              />
              <Music size={80} style={{ opacity: 0.8 }} />
            </div>

            {/* 可编辑歌曲与歌手标题 */}
            <input 
              type="text" 
              value={editTitle}
              onChange={e => setEditTitle(e.target.value)}
              onBlur={handleSaveMetadata}
              onKeyDown={e => { if (e.key === "Enter") handleSaveMetadata(); }}
              style={{ width: "85%", textAlign: "center", fontSize: "1.2rem", fontWeight: "bold", background: "transparent", border: "none", borderBottom: "1px dashed transparent", outline: "none", color: "var(--text-main)", marginTop: "24px" }}
            />
            <input 
              type="text" 
              value={editArtist}
              onChange={e => setEditArtist(e.target.value)}
              onBlur={handleSaveMetadata}
              onKeyDown={e => { if (e.key === "Enter") handleSaveMetadata(); }}
              style={{ width: "85%", textAlign: "center", fontSize: "0.85rem", background: "transparent", border: "none", borderBottom: "1px dashed transparent", outline: "none", color: "var(--text-sub)", marginTop: "6px" }}
            />
          </div>

          {/* 三格详情面板选项卡 */}
          <div style={{ display: "flex", borderBottom: "1px solid var(--border-light)", margin: "0 16px 8px 16px" }}>
            <button 
              onClick={() => setMobileTab("versions")} 
              style={{ flex: 1, padding: "8px", background: "transparent", border: "none", borderBottom: mobileTab === "versions" ? "2px solid var(--accent)" : "none", color: mobileTab === "versions" ? "var(--accent)" : "var(--text-sub)", fontWeight: 600, fontSize: "0.8rem" }}
            >
              音频源 ({activeSong.versions.length})
            </button>
            <button 
              onClick={() => setMobileTab("tags")} 
              style={{ flex: 1, padding: "8px", background: "transparent", border: "none", borderBottom: mobileTab === "tags" ? "2px solid var(--accent)" : "none", color: mobileTab === "tags" ? "var(--accent)" : "var(--text-sub)", fontWeight: 600, fontSize: "0.8rem" }}
            >
              关联标签 ({activeSong.tags.length})
            </button>
            <button 
              onClick={() => setMobileTab("lyrics")} 
              style={{ flex: 1, padding: "8px", background: "transparent", border: "none", borderBottom: mobileTab === "lyrics" ? "2px solid var(--accent)" : "none", color: mobileTab === "lyrics" ? "var(--accent)" : "var(--text-sub)", fontWeight: 600, fontSize: "0.8rem" }}
            >
              滚动歌词
            </button>
          </div>

          {/* 中间自适应面板切换区域 */}
          <div style={{ flex: 1, overflowY: "auto", padding: "4px 16px" }}>
            {mobileTab === "versions" && (
              <div style={{ display: "flex", flexDirection: "column", gap: "8px" }}>
                <button 
                  className="import-btn" 
                  style={{ width: "100%", padding: "8px", display: "flex", gap: "6px", justifyContent: "center", alignItems: "center", fontSize: "0.85rem" }} 
                  onClick={() => onImportVersionForSong(activeSong.id)}
                >
                  <Plus size={16} /> 绑定其他音轨文件
                </button>
                {activeSong.versions.map(v => (
                  <div key={v.id} style={{ padding: "8px", background: "var(--bg-panel)", border: "1px solid var(--border)", borderRadius: "8px", display: "flex", flexDirection: "column", gap: "4px" }}>
                    <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
                      <span style={{ fontSize: "0.75rem", fontWeight: 600, textOverflow: "ellipsis", overflow: "hidden", whiteSpace: "nowrap", width: "70%" }}>
                        {v.original_name}
                      </span>
                      <div style={{ display: "flex", gap: "6px" }}>
                        <button className="ctrl-btn-xs" style={{ color: "#ef4444" }} onClick={() => onDeleteVersion(v.id)}><Trash2 size={12} /></button>
                        <button className="ctrl-btn-xs" onClick={() => onExportVersion(v.id)}><Download size={12} /></button>
                      </div>
                    </div>
                    <div style={{ display: "flex", gap: "10px", alignItems: "center", marginTop: "2px" }}>
                      <label style={{ display: "flex", alignItems: "center", gap: "4px", fontSize: "0.7rem", color: "var(--text-sub)" }}>
                        <input type="checkbox" checked={v.is_enabled} onChange={(e) => onToggleVersionStatus(v.id, e.target.checked)} />
                        启用
                      </label>
                      <label style={{ display: "flex", alignItems: "center", gap: "4px", fontSize: "0.7rem", color: "var(--text-sub)" }}>
                        <input type="radio" name="mobile-primary" checked={v.is_primary} disabled={!v.is_enabled} onChange={() => onSetPrimaryVersion(v.id)} />
                        设为主音源
                      </label>
                    </div>
                  </div>
                ))}
              </div>
            )}

            {mobileTab === "tags" && (
              <div style={{ display: "grid", gridTemplateColumns: "1fr", gap: "8px" }}>
                {allTags.map(tag => {
                  const isBound = activeSong.tags.some(t => t.id === tag.id);
                  return (
                    <div
                      key={tag.id}
                      onClick={() => isBound ? onUnbindTag(activeSong.id, tag.id) : onBindTag(activeSong.id, tag.id)}
                      style={{
                        padding: "10px", borderRadius: "8px", border: `1px solid ${isBound ? tag.color : "var(--border)"}`,
                        display: "flex", justifyContent: "space-between", alignItems: "center",
                        background: isBound ? `${tag.color}15` : "var(--bg-panel)",
                        cursor: "pointer"
                      }}
                    >
                      <span style={{ color: tag.color || "var(--text-main)", fontWeight: 600 }}>{tag.name}</span>
                      {isBound ? <CheckSquare size={20} color={tag.color || "var(--accent)"} /> : <Square size={20} color="var(--text-sub)" />}
                    </div>
                  );
                })}
                {allTags.length === 0 && <div style={{ color: "var(--text-sub)", textAlign: "center", marginTop: "10px" }}>暂无标签，请先添加</div>}
              </div>
            )}

            {mobileTab === "lyrics" && (
              <div style={{ textAlign: "center", padding: "10px", color: "var(--text-sub)", fontSize: "0.85rem" }}>
                {activeSong.lyrics ? (
                  <pre style={{ fontFamily: "inherit", whiteSpace: "pre-wrap", lineHeight: 1.8 }}>
                    {activeSong.lyrics}
                  </pre>
                ) : "暂无歌词"}
              </div>
            )}
          </div>
        </div>
      )}

      {/* 全屏播放控制与详情面板 (Slide Up) */}
      {isPlayerExpanded && playingSong && (
        <div 
          style={{
            position: "fixed",
            top: 0,
            left: 0,
            right: 0,
            bottom: 0,
            zIndex: 9999,
            background: "var(--bg-app)",
            display: "flex",
            flexDirection: "column",
            animation: "slideUp 0.3s cubic-bezier(0.16, 1, 0.3, 1)"
          }}
        >
          {/* 顶栏控制 */}
          <div style={{ padding: "16px", display: "flex", justifyContent: "space-between", alignItems: "center" }}>
            <button className="ctrl-btn" onClick={() => setIsPlayerExpanded(false)}>
              <ChevronDown size={28} />
            </button>
            <span style={{ fontSize: "0.85rem", fontWeight: 600, color: "var(--text-sub)", letterSpacing: "1px" }}>正在播放</span>
            <div style={{ width: "28px" }} />
          </div>

          {/* 动态封面发光组件 */}
          <div style={{ flex: 1.2, display: "flex", flexDirection: "column", alignItems: "center", justifyContent: "center", padding: "10px 24px" }}>
            <div 
              style={{
                width: "200px",
                height: "200px",
                borderRadius: "20px",
                background: "var(--accent-glow)",
                display: "flex",
                alignItems: "center",
                justifyContent: "center",
                color: "var(--accent)",
                position: "relative",
                boxShadow: "0 20px 50px var(--shadow)"
              }}
            >
              <div 
                style={{
                  position: "absolute",
                  top: 0, right: 0, bottom: 0, left: 0,
                  borderRadius: "20px",
                  background: "radial-gradient(circle, var(--accent) 0%, transparent 70%)",
                  opacity: 0.15,
                  filter: "blur(20px)"
                }}
              />
              <Music size={80} style={{ opacity: 0.8 }} />
            </div>

            {/* 可编辑歌曲与歌手标题 */}
            <input 
              type="text" 
              value={editTitle}
              onChange={e => setEditTitle(e.target.value)}
              onBlur={handleSaveMetadata}
              onKeyDown={e => { if (e.key === "Enter") handleSaveMetadata(); }}
              style={{ width: "85%", textAlign: "center", fontSize: "1.2rem", fontWeight: "bold", background: "transparent", border: "none", borderBottom: "1px dashed transparent", outline: "none", color: "var(--text-main)", marginTop: "24px" }}
            />
            <input 
              type="text" 
              value={editArtist}
              onChange={e => setEditArtist(e.target.value)}
              onBlur={handleSaveMetadata}
              onKeyDown={e => { if (e.key === "Enter") handleSaveMetadata(); }}
              style={{ width: "85%", textAlign: "center", fontSize: "0.85rem", background: "transparent", border: "none", borderBottom: "1px dashed transparent", outline: "none", color: "var(--text-sub)", marginTop: "6px" }}
            />
          </div>

          {/* 三格详情面板选项卡 */}
          <div style={{ display: "flex", borderBottom: "1px solid var(--border-light)", margin: "0 16px 8px 16px" }}>
            <button 
              onClick={() => setMobileTab("versions")} 
              style={{ flex: 1, padding: "8px", background: "transparent", border: "none", borderBottom: mobileTab === "versions" ? "2px solid var(--accent)" : "none", color: mobileTab === "versions" ? "var(--accent)" : "var(--text-sub)", fontWeight: 600, fontSize: "0.8rem" }}
            >
              音频源 ({playingSong.versions.length})
            </button>
            <button 
              onClick={() => setMobileTab("tags")} 
              style={{ flex: 1, padding: "8px", background: "transparent", border: "none", borderBottom: mobileTab === "tags" ? "2px solid var(--accent)" : "none", color: mobileTab === "tags" ? "var(--accent)" : "var(--text-sub)", fontWeight: 600, fontSize: "0.8rem" }}
            >
              关联标签 ({playingSong.tags.length})
            </button>
            <button 
              onClick={() => setMobileTab("lyrics")} 
              style={{ flex: 1, padding: "8px", background: "transparent", border: "none", borderBottom: mobileTab === "lyrics" ? "2px solid var(--accent)" : "none", color: mobileTab === "lyrics" ? "var(--accent)" : "var(--text-sub)", fontWeight: 600, fontSize: "0.8rem" }}
            >
              滚动歌词
            </button>
          </div>

          {/* 中间自适应面板切换区域 */}
          <div style={{ flex: 1, overflowY: "auto", padding: "4px 16px" }}>
            {mobileTab === "versions" && (
              <div style={{ display: "flex", flexDirection: "column", gap: "8px" }}>
                <button 
                  className="import-btn" 
                  style={{ width: "100%", padding: "8px", display: "flex", gap: "6px", justifyContent: "center", alignItems: "center", fontSize: "0.85rem" }} 
                  onClick={() => onImportVersionForSong(playingSong.id)}
                >
                  <Plus size={16} /> 绑定其他音轨文件
                </button>
                {playingSong.versions.map(v => (
                  <div key={v.id} style={{ padding: "8px", background: "var(--bg-panel)", border: "1px solid var(--border)", borderRadius: "8px", display: "flex", flexDirection: "column", gap: "4px" }}>
                    <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
                      <span style={{ fontSize: "0.75rem", fontWeight: 600, textOverflow: "ellipsis", overflow: "hidden", whiteSpace: "nowrap", width: "70%" }}>
                        {v.original_name}
                      </span>
                      <div style={{ display: "flex", gap: "6px" }}>
                        <button className="ctrl-btn-xs" style={{ color: "#ef4444" }} onClick={() => onDeleteVersion(v.id)}><Trash2 size={12} /></button>
                        <button className="ctrl-btn-xs" onClick={() => onExportVersion(v.id)}><Download size={12} /></button>
                      </div>
                    </div>
                    <div style={{ display: "flex", gap: "10px", alignItems: "center", marginTop: "2px" }}>
                      <label style={{ display: "flex", alignItems: "center", gap: "4px", fontSize: "0.7rem", color: "var(--text-sub)" }}>
                        <input type="checkbox" checked={v.is_enabled} onChange={(e) => onToggleVersionStatus(v.id, e.target.checked)} />
                        启用
                      </label>
                      <label style={{ display: "flex", alignItems: "center", gap: "4px", fontSize: "0.7rem", color: "var(--text-sub)" }}>
                        <input type="radio" name="mobile-primary" checked={v.is_primary} disabled={!v.is_enabled} onChange={() => onSetPrimaryVersion(v.id)} />
                        设为主音源
                      </label>
                    </div>
                  </div>
                ))}
              </div>
            )}

            {mobileTab === "tags" && (
              <div style={{ display: "grid", gridTemplateColumns: "1fr", gap: "8px" }}>
                {allTags.map(t => {
                  const isBound = playingSong.tags.some(tag => tag.id === t.id);
                  return (
                    <div 
                      key={t.id} 
                      onClick={() => isBound ? onUnbindTag(playingSong.id, t.id) : onBindTag(playingSong.id, t.id)}
                      style={{ padding: "10px", borderRadius: "8px", background: isBound ? `${t.color}15` : "var(--bg-panel)", border: `1px solid ${isBound ? t.color : "var(--border)"}`, display: "flex", justifyContent: "space-between", alignItems: "center", cursor: "pointer", fontSize: "0.85rem" }}
                    >
                      <span style={{ color: t.color, fontWeight: 600 }}>{t.name}</span>
                      {isBound ? <CheckSquare size={20} color={t.color || "var(--accent)"} /> : <Square size={20} color="var(--text-sub)" />}
                    </div>
                  );
                })}
              </div>
            )}

            {mobileTab === "lyrics" && (
              <div style={{ textAlign: "center", padding: "10px", color: "var(--text-sub)", fontSize: "0.82rem", lineHeight: "1.6", height: "100%", display: "flex", alignItems: "center", justifyContent: "center" }}>
                {playingSong.lyrics ? playingSong.lyrics : "暂无歌词内容"}
              </div>
            )}
          </div>

          {/* 进度条滑块控制器 */}
          <div style={{ padding: "10px 24px" }}>
            <div style={{ display: "flex", justifyContent: "space-between", fontSize: "0.75rem", color: "var(--text-sub)", marginBottom: "4px" }}>
              <span>{formatTime(currentTime)}</span>
              <span>{formatTime(duration)}</span>
            </div>
            <input 
              type="range" 
              min={0}
              max={duration || 100}
              value={currentTime}
              onChange={e => onSeek(parseFloat(e.target.value))}
              style={{ width: "100%", accentColor: "var(--accent)" }}
            />
          </div>

          {/* 播放控制按钮栏 */}
          <div style={{ padding: "10px 24px 24px 24px", display: "flex", justifyContent: "space-around", alignItems: "center" }}>
            {/* 播放模式切换 */}
            <button 
              className="ctrl-btn" 
              onClick={() => {
                if (playMode === "list") onSetPlayMode("single");
                else if (playMode === "single") onSetPlayMode("shuffle");
                else onSetPlayMode("list");
              }}
              style={{ color: playMode !== "list" ? "var(--accent)" : "var(--text-sub)" }}
            >
              {playMode === "list" && <Repeat size={20} />}
              {playMode === "single" && <Repeat size={20} style={{ borderBottom: "2px solid var(--accent)" }} />}
              {playMode === "shuffle" && <Shuffle size={20} />}
            </button>

            <button className="ctrl-btn" onClick={onPrev}>
              <SkipBack size={26} />
            </button>

            <button 
              className="ctrl-btn" 
              onClick={onPlayPause}
              style={{ width: "64px", height: "64px", borderRadius: "50%", background: "var(--accent)", color: "#fff", display: "flex", alignItems: "center", justifyContent: "center", boxShadow: "0 10px 30px var(--accent-glow)" }}
            >
              {isPlaying ? <Pause size={28} /> : <Play size={28} style={{ transform: "translateX(2px)" }} />}
            </button>

            <button className="ctrl-btn" onClick={onNext}>
              <SkipForward size={26} />
            </button>

            {/* 音量滑块静音控制 */}
            <button 
              className="ctrl-btn"
              onClick={() => onSetVolume(volume === 0 ? 0.8 : 0)}
              style={{ color: volume === 0 ? "var(--text-sub)" : "var(--accent)" }}
            >
              <Volume2 size={20} />
            </button>
          </div>
        </div>
      )}

      {/* 移动端歌曲操作上下文菜单 (Bottom Sheet / Modal) */}
      {contextMenuSong && (
        <div 
          style={{ position: "fixed", top: 0, left: 0, right: 0, bottom: 0, zIndex: 120, display: "flex", flexDirection: "column", justifyContent: "flex-end" }}
          onClick={() => setContextMenuSong(null)}
        >
          <div style={{ position: "absolute", top: 0, left: 0, right: 0, bottom: 0, background: "rgba(0,0,0,0.5)", backdropFilter: "blur(6px)" }} />
          
          <div 
            onClick={e => e.stopPropagation()}
            style={{ 
              position: "relative",
              background: "var(--bg-app)", 
              borderTop: "1px solid var(--border)", 
              borderTopLeftRadius: "24px", 
              borderTopRightRadius: "24px", 
              padding: "20px 16px 32px 16px",
              boxShadow: "0 -10px 40px rgba(0,0,0,0.3)",
              display: "flex",
              flexDirection: "column",
              gap: "10px",
              animation: "slideUp 0.25s cubic-bezier(0.2, 0.8, 0.2, 1)"
            }}
          >
            <div style={{ textAlign: "center", marginBottom: "8px" }}>
              <div style={{ width: "36px", height: "4px", background: "var(--border)", borderRadius: "2px", margin: "0 auto 12px auto" }} />
              <h3 style={{ fontSize: "1.05rem", fontWeight: "bold", margin: 0, color: "var(--text-main)", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>
                {contextMenuSong.title}
              </h3>
              <p style={{ fontSize: "0.8rem", color: "var(--text-sub)", margin: "4px 0 0 0" }}>
                {contextMenuSong.artist || "未知歌手"}
              </p>
            </div>

            <button 
              className="menu-item-mobile" 
              onClick={() => {
                onPlaySong(contextMenuSong);
                setContextMenuSong(null);
              }}
              style={{ display: "flex", alignItems: "center", gap: "12px", width: "100%", padding: "14px 18px", borderRadius: "12px", background: "var(--bg-hover)", border: "none", color: "var(--text-main)", fontSize: "0.95rem", fontWeight: 600, textAlign: "left", cursor: "pointer" }}
            >
              <Play size={18} color="var(--accent)" /> 播放歌曲
            </button>

            <button 
              className="menu-item-mobile" 
              onClick={() => {
                onSelectSong(contextMenuSong);
                setIsSongDetailOpen(true);
                setContextMenuSong(null);
              }}
              style={{ display: "flex", alignItems: "center", gap: "12px", width: "100%", padding: "14px 18px", borderRadius: "12px", background: "var(--bg-hover)", border: "none", color: "var(--text-main)", fontSize: "0.95rem", fontWeight: 600, textAlign: "left", cursor: "pointer" }}
            >
              <Settings size={18} /> 打开详细信息
            </button>

            {/* 添加到歌单 */}
            {playlists.length > 0 && (
              <div style={{ display: "flex", flexDirection: "column", gap: "4px", padding: "10px 12px", background: "var(--bg-hover)", borderRadius: "12px", border: "1px solid var(--border)" }}>
                <span style={{ fontSize: "0.78rem", color: "var(--text-sub)", fontWeight: 600, marginBottom: "6px" }}>添加到歌单</span>
                <div style={{ display: "flex", gap: "8px", overflowX: "auto" }} className="no-scrollbar">
                  {playlists.map(pl => (
                    <button
                      key={pl.id}
                      onClick={() => {
                        onAddSongsToPlaylist(pl.id, [contextMenuSong.id]);
                        setContextMenuSong(null);
                      }}
                      style={{ padding: "6px 12px", borderRadius: "20px", background: "var(--bg-hover)", border: "1px solid var(--border)", color: "var(--text-main)", fontSize: "0.80rem", whiteSpace: "nowrap", cursor: "pointer" }}
                    >
                      {pl.name}
                    </button>
                  ))}
                </div>
              </div>
            )}

            {activePlaylistId && (
              <button 
                className="menu-item-mobile" 
                onClick={() => {
                  onRemoveSongsFromPlaylist(activePlaylistId, [contextMenuSong.id]);
                  setContextMenuSong(null);
                }}
                style={{ display: "flex", alignItems: "center", gap: "12px", width: "100%", padding: "14px 18px", borderRadius: "12px", background: "var(--bg-hover)", border: "none", color: "#f59e0b", fontSize: "0.95rem", fontWeight: 600, textAlign: "left", cursor: "pointer" }}
              >
                <Trash2 size={18} /> 从当前歌单移除
              </button>
            )}

            <button 
              className="menu-item-mobile" 
              onClick={() => {
                if (confirm(`确定要彻底删除歌曲《${contextMenuSong.title}》吗？这会同时删除本地音乐文件！`)) {
                  onDeleteSongs([contextMenuSong.id]);
                }
                setContextMenuSong(null);
              }}
              style={{ display: "flex", alignItems: "center", gap: "12px", width: "100%", padding: "14px 18px", borderRadius: "12px", background: "var(--bg-hover)", border: "none", color: "#ef4444", fontSize: "0.95rem", fontWeight: 600, textAlign: "left", cursor: "pointer" }}
            >
              <Trash2 size={18} /> 彻底删除歌曲
            </button>
          </div>
        </div>
      )}
    </div>
  );
}
