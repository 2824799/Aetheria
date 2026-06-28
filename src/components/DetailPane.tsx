import { X, Music, Download, CheckSquare, Square, Play, Pause } from "lucide-react";

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

interface DetailPaneProps {
  isOpen: boolean;
  onClose: () => void;
  activeSong: Song | null;
  activeTab: "versions" | "tags" | "lyrics";
  onSetActiveTab: (tab: "versions" | "tags" | "lyrics") => void;
  playingVersion: AudioVersion | null;
  isPlaying: boolean;
  onPlayVersion: (song: Song, version: AudioVersion) => void;
  allTags: Tag[];
  onBindTag: (songId: string, tagId: number) => void;
  onUnbindTag: (songId: string, tagId: number) => void;
  onSetPrimaryVersion: (versionId: string) => void;
  onToggleVersionStatus: (versionId: string, active: boolean) => void;
  onExportVersion: (versionId: string) => void;
}

export default function DetailPane({
  isOpen,
  onClose,
  activeSong,
  activeTab,
  onSetActiveTab,
  playingVersion,
  isPlaying,
  onPlayVersion,
  allTags,
  onBindTag,
  onUnbindTag,
  onSetPrimaryVersion,
  onToggleVersionStatus,
  onExportVersion,
}: DetailPaneProps) {
  const formatTime = (secs: number) => {
    if (isNaN(secs)) return "0:00";
    const m = Math.floor(secs / 60);
    const s = Math.floor(secs % 60);
    return `${m}:${s < 10 ? "0" : ""}${s}`;
  };

  return (
    <div className={`glass-panel detail-pane ${isOpen ? "open" : ""}`}>
      <button className="detail-close-btn" onClick={onClose}>
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
              onClick={() => onSetActiveTab("versions")}
            >
              音频版本 ({activeSong.versions.length})
            </div>
            <div 
              className={`detail-tab ${activeTab === "tags" ? "active" : ""}`}
              onClick={() => onSetActiveTab("tags")}
            >
              标签绑定 ({activeSong.tags.length})
            </div>
            <div 
              className={`detail-tab ${activeTab === "lyrics" ? "active" : ""}`}
              onClick={() => onSetActiveTab("lyrics")}
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
                        <span className="version-filename" title={v.original_name}>{v.original_name}</span>
                        <span className="version-specs">
                          {v.format.toUpperCase()} · {v.bitrate ? `${Math.round(v.bitrate / 1000)}kbps` : "未知码率"} · {v.file_size ? `${(v.file_size / 1024 / 1024).toFixed(2)} MB` : ""} · {formatTime(v.duration || 0)}
                        </span>
                      </div>
                      <button 
                        className="ctrl-btn" 
                        style={{ color: playingVersion?.id === v.id && isPlaying ? "#10b981" : "var(--accent)" }}
                        onClick={() => onPlayVersion(activeSong, v)}
                      >
                        {playingVersion?.id === v.id && isPlaying ? <Pause size={18} /> : <Play size={18} />}
                      </button>
                    </div>

                    <div className="version-actions">
                      <label className="checkbox-label">
                        <input 
                          type="checkbox" 
                          checked={v.is_enabled} 
                          onChange={(e) => onToggleVersionStatus(v.id, e.target.checked)}
                        />
                        启用该版本
                      </label>

                      <label className="radio-label">
                        <input 
                          type="radio" 
                          name={`primary-${activeSong.id}`} 
                          checked={v.is_primary}
                          disabled={!v.is_enabled}
                          onChange={() => onSetPrimaryVersion(v.id)}
                        />
                        设为主播放版本
                      </label>
                    </div>
                    
                    <div style={{ borderTop: "1px dashed var(--border)", paddingTop: "6px", display: "flex", justifyContent: "flex-end" }}>
                      <button className="action-btn-sm" onClick={() => onExportVersion(v.id)}>
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
                {allTags.map(t => {
                  const isBound = activeSong.tags.some(tag => tag.id === t.id);
                  return (
                    <div 
                      key={t.id} 
                      className="tag-bind-item"
                      onClick={() => {
                        if (isBound) onUnbindTag(activeSong.id, t.id);
                        else onBindTag(activeSong.id, t.id);
                      }}
                    >
                      <span style={{ color: t.color, fontWeight: 600 }}>{t.name}</span>
                      {isBound ? <CheckSquare size={16} color={t.color} /> : <Square size={16} color="var(--text-sub)" />}
                    </div>
                  );
                })}
                {allTags.length === 0 && (
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
  );
}
