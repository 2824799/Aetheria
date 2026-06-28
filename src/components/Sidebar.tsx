import { useState } from "react";
import { List, Settings, Music, Plus, Trash2, Edit3, Check } from "lucide-react";

interface Playlist {
  id: string;
  name: string;
  description?: string;
  created_at: string;
}

interface SidebarProps {
  playlists: Playlist[];
  activePlaylistId: string | null;
  onSelectPlaylist: (id: string | null) => void;
  onCreatePlaylist: (name: string) => void;
  onRenamePlaylist: (id: string, name: string) => void;
  onDeletePlaylist: (id: string) => void;
  allSongsCount: number;
  onOpenSettings: () => void;
}

export default function Sidebar({
  playlists,
  activePlaylistId,
  onSelectPlaylist,
  onCreatePlaylist,
  onRenamePlaylist,
  onDeletePlaylist,
  allSongsCount,
  onOpenSettings,
}: SidebarProps) {
  // 新建歌单状态
  const [isCreating, setIsCreating] = useState(false);
  const [newPlaylistName, setNewPlaylistName] = useState("");

  // 重命名状态
  const [renamingId, setRenamingId] = useState<string | null>(null);
  const [renamingName, setRenamingName] = useState("");

  const handleCreateSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    if (newPlaylistName.trim()) {
      onCreatePlaylist(newPlaylistName.trim());
      setNewPlaylistName("");
      setIsCreating(false);
    }
  };

  const handleRenameSubmit = (id: string) => {
    if (renamingName.trim()) {
      onRenamePlaylist(id, renamingName.trim());
      setRenamingId(null);
      setRenamingName("");
    }
  };

  return (
    <div className="glass-panel sidebar">
      <div className="sidebar-top-scroll">
        <div className="logo-section">
          <div className="logo-icon">
            <Music size={22} color="white" />
          </div>
          <span className="logo-text">AETHERIA</span>
        </div>

        <div className="menu-group">
          <div className="menu-title">导航中心</div>
          <div 
            className={`menu-item ${activePlaylistId === null ? "active" : ""}`}
            onClick={() => onSelectPlaylist(null)}
          >
            <List size={18} />
            全部歌曲 ({allSongsCount})
          </div>

          {/* 歌单列表：直接放置在“全部歌曲”下方，去掉“歌单合集”小标题和加号 */}
          <div className="sidebar-playlist-list" style={{ marginTop: "8px", maxHeight: "400px" }}>
            {playlists.map(pl => {
              const isActive = activePlaylistId === pl.id;
              const isRenaming = renamingId === pl.id;

              return (
                <div 
                  key={pl.id}
                  className={`menu-item playlist-item ${isActive ? "active" : ""}`}
                  onClick={() => !isRenaming && onSelectPlaylist(pl.id)}
                >
                  <List size={16} />
                  
                  {isRenaming ? (
                    <div style={{ display: "flex", gap: "4px", width: "100%", alignItems: "center" }} onClick={e => e.stopPropagation()}>
                      <input 
                        type="text" 
                        className="text-input-sm"
                        style={{ padding: "2px 4px", fontSize: "0.8rem", width: "80%" }}
                        autoFocus
                        value={renamingName}
                        onChange={e => setRenamingName(e.target.value)}
                        onKeyDown={e => {
                          if (e.key === "Enter") handleRenameSubmit(pl.id);
                          if (e.key === "Escape") setRenamingId(null);
                        }}
                        onBlur={() => handleRenameSubmit(pl.id)}
                      />
                      <button className="ctrl-btn-xs" onClick={() => handleRenameSubmit(pl.id)}>
                        <Check size={12} />
                      </button>
                    </div>
                  ) : (
                    <>
                      <span className="playlist-name-text" title={pl.name}>{pl.name}</span>
                      
                      <div className="playlist-item-actions" onClick={e => e.stopPropagation()}>
                        <button 
                          className="action-icon-btn" 
                          title="重命名"
                          onClick={() => {
                            setRenamingId(pl.id);
                            setRenamingName(pl.name);
                          }}
                        >
                          <Edit3 size={12} />
                        </button>
                        <button 
                          className="action-icon-btn delete" 
                          title="删除歌单"
                          onClick={() => onDeletePlaylist(pl.id)}
                        >
                          <Trash2 size={12} />
                        </button>
                      </div>
                    </>
                  )}
                </div>
              );
            })}
          </div>

          {/* 新建歌单输入表单 */}
          {isCreating ? (
            <form onSubmit={handleCreateSubmit} className="sidebar-new-playlist-form" style={{ marginTop: "8px" }}>
              <input 
                type="text" 
                placeholder="歌单名称..." 
                autoFocus
                className="text-input-sm"
                value={newPlaylistName}
                onChange={e => setNewPlaylistName(e.target.value)}
                onBlur={() => {
                  if (!newPlaylistName.trim()) setIsCreating(false);
                }}
              />
            </form>
          ) : (
            <button className="sidebar-add-playlist-btn" onClick={() => setIsCreating(true)}>
              <Plus size={14} /> 新建歌单
            </button>
          )}
        </div>
      </div>

      <div className="sidebar-bottom">
        <div className="menu-item" onClick={onOpenSettings}>
          <Settings size={18} />
          系统设置
        </div>
      </div>
    </div>
  );
}
