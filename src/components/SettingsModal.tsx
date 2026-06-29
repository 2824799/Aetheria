import { X, Settings, Trash2 } from "lucide-react";

interface SettingsModalProps {
  isOpen: boolean;
  onClose: () => void;
  theme: "dark" | "light" | "pink";
  setTheme: (val: "dark" | "light" | "pink") => void;
  libraryPath: string;
  onResetLibrary: () => void;
}

export default function SettingsModal({
  isOpen,
  onClose,
  theme,
  setTheme,
  libraryPath,
  onResetLibrary,
}: SettingsModalProps) {
  if (!isOpen) return null;

  return (
    <div className="modal-overlay" onClick={onClose}>
      <div className="modal-content" onClick={e => e.stopPropagation()}>
        <div className="modal-header">
          <span className="modal-title" style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
            <Settings size={20} /> 系统设置
          </span>
          <button className="ctrl-btn" onClick={onClose}><X size={18} /></button>
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

        <div className="form-group">
          <label>本地托管音乐库路径</label>
          <div 
            className="text-input" 
            style={{ fontSize: '0.8rem', wordBreak: 'break-all', opacity: 0.8, background: 'var(--bg-hover)' }}
          >
            {libraryPath}
          </div>
        </div>

        <div className="form-group" style={{ borderTop: "1px solid var(--border)", paddingTop: "12px" }}>
          <label style={{ color: "#ef4444" }}>危险操作区域</label>
          <button 
            className="import-btn" 
            style={{ 
              width: "100%", 
              display: "flex", 
              gap: "8px", 
              justifyContent: "center", 
              alignItems: "center", 
              borderColor: "rgba(239, 68, 68, 0.4)", 
              color: "#ef4444" 
            }} 
            onClick={onResetLibrary}
          >
            <Trash2 size={16} /> 一键重置数据库并清空全部数据
          </button>
        </div>

        <div className="form-group" style={{ borderTop: "1px solid var(--border)", paddingTop: "12px" }}>
          <label>关于 Aetheria</label>
          <div style={{ fontSize: '0.8rem', opacity: 0.7, lineHeight: 1.5 }}>
            软件版本: v0.1.0 (Portable)<br />
            数据引擎: SQLite 3 & Symphonia/Lofty (Rust)<br />
            开源许可: GNU AGPL v3 License<br />
            界面渲染: React 19 & Tauri 2.0
          </div>
        </div>
      </div>
    </div>
  );
}
