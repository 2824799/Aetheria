import { useState, useEffect } from "react";
import { X, Check, Settings, FileAudio } from "lucide-react";
import { invoke } from "@tauri-apps/api/core";

interface PreviewItem {
  filepath: string;
  filename: string;
  title: string;
  artist: string;
}

interface ImportPreviewModalProps {
  isOpen: boolean;
  onClose: () => void;
  filesToImport: string[];
  onConfirm: (songs: { filepath: string; title: string; artist: string }[]) => void;
}

export default function ImportPreviewModal({
  isOpen,
  onClose,
  filesToImport,
  onConfirm,
}: ImportPreviewModalProps) {
  const [items, setItems] = useState<PreviewItem[]>([]);
  const [mode, setMode] = useState<"embedded" | "filename">("embedded");
  const [delimiter, setDelimiter] = useState(" - ");
  const [rule, setRule] = useState<"title-artist" | "artist-title">("title-artist");
  const [loading, setLoading] = useState(false);

  // 加载并初步解析元数据
  useEffect(() => {
    if (isOpen && filesToImport.length > 0) {
      setLoading(true);
      invoke<PreviewItem[]>("preview_audio_metadata", { filepaths: filesToImport })
        .then(res => {
          setItems(res);
          setLoading(false);
        })
        .catch(err => {
          console.error("预览解析出错:", err);
          setLoading(false);
        });
    }
  }, [isOpen, filesToImport]);

  if (!isOpen) return null;

  // 根据当前配置进行动态渲染预览
  const getProcessedItems = () => {
    return items.map(item => {
      if (mode === "embedded") {
        return {
          ...item,
          displayTitle: item.title || item.filename.replace(/\.[^/.]+$/, ""),
          displayArtist: item.artist || "未知歌手",
        };
      } else {
        // 从文件名解析 (去除扩展名)
        const cleanName = item.filename.replace(/\.[^/.]+$/, "");
        const parts = cleanName.split(delimiter);
        let displayTitle = cleanName;
        let displayArtist = "未知歌手";

        if (parts.length >= 2) {
          if (rule === "title-artist") {
            displayTitle = parts[0].trim();
            displayArtist = parts[1].trim();
          } else {
            displayArtist = parts[0].trim();
            displayTitle = parts[1].trim();
          }
        } else {
          // 无法分割时，整个作为歌名
          displayTitle = cleanName;
        }

        return {
          ...item,
          displayTitle,
          displayArtist,
        };
      }
    });
  };

  const processed = getProcessedItems();

  const handleImportClick = () => {
    const payload = processed.map(p => ({
      filepath: p.filepath,
      title: p.displayTitle,
      artist: p.displayArtist,
    }));
    onConfirm(payload);
  };

  return (
    <div className="modal-overlay" onClick={onClose}>
      <div 
        className="modal-content" 
        onClick={e => e.stopPropagation()} 
        style={{ width: "800px", maxWidth: "90vw", maxHeight: "85vh", display: "flex", flexDirection: "column" }}
      >
        <div className="modal-header">
          <span className="modal-title" style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
            <Settings size={20} /> 导入预览与规则配置
          </span>
          <button className="ctrl-btn" onClick={onClose}><X size={18} /></button>
        </div>

        {/* 顶部规则配置面板 */}
        <div 
          className="glass-panel" 
          style={{ 
            padding: "16px", 
            marginBottom: "16px", 
            display: "grid", 
            gridTemplateColumns: "1fr 1fr", 
            gap: "16px",
            background: "var(--bg-hover)",
            borderRadius: "8px" 
          }}
        >
          <div className="form-group" style={{ margin: 0 }}>
            <label style={{ fontWeight: 600 }}>元数据识别模式</label>
            <div style={{ display: "flex", gap: "12px", marginTop: "8px" }}>
              <label style={{ display: "flex", alignItems: "center", gap: "6px", cursor: "pointer", fontSize: "0.85rem" }}>
                <input 
                  type="radio" 
                  name="import-mode" 
                  checked={mode === "embedded"} 
                  onChange={() => setMode("embedded")} 
                />
                内嵌音频元数据 (ID3/FLAC Tags)
              </label>
              <label style={{ display: "flex", alignItems: "center", gap: "6px", cursor: "pointer", fontSize: "0.85rem" }}>
                <input 
                  type="radio" 
                  name="import-mode" 
                  checked={mode === "filename"} 
                  onChange={() => setMode("filename")} 
                />
                从文件名解析
              </label>
            </div>
          </div>

          {mode === "filename" && (
            <div style={{ display: "flex", gap: "12px" }}>
              <div className="form-group" style={{ margin: 0, flex: 1 }}>
                <label style={{ fontWeight: 600 }}>文件名分隔符</label>
                <input 
                  type="text" 
                  className="text-input-sm" 
                  style={{ width: "100%", marginTop: "6px", padding: "4px 8px" }}
                  value={delimiter}
                  onChange={e => setDelimiter(e.target.value)}
                  placeholder="例如： - "
                />
              </div>
              <div className="form-group" style={{ margin: 0, flex: 1.5 }}>
                <label style={{ fontWeight: 600 }}>匹配规则</label>
                <select 
                  className="text-input-sm"
                  style={{ width: "100%", marginTop: "6px", padding: "4px 8px", background: "var(--bg-panel)", border: "1px solid var(--border)", color: "var(--text)" }}
                  value={rule}
                  onChange={e => setRule(e.target.value as any)}
                >
                  <option value="title-artist">歌名 {delimiter} 歌手</option>
                  <option value="artist-title">歌手 {delimiter} 歌名</option>
                </select>
              </div>
            </div>
          )}
        </div>

        {/* 预览数据列表 */}
        <div style={{ flex: 1, overflowY: "auto", border: "1px solid var(--border)", borderRadius: "8px", background: "var(--bg-panel)" }}>
          {loading ? (
            <div style={{ padding: "40px", textAlign: "center", color: "var(--text-sub)" }}>
              正在解析选中文件的元数据信息...
            </div>
          ) : (
            <table className="song-table" style={{ width: "100%", tableLayout: "fixed" }}>
              <thead>
                <tr>
                  <th style={{ width: "40%" }}>文件名</th>
                  <th style={{ width: "30%" }}>识别出的歌名</th>
                  <th style={{ width: "30%" }}>识别出的歌手</th>
                </tr>
              </thead>
              <tbody>
                {processed.map((item, idx) => (
                  <tr key={idx} style={{ borderBottom: "1px solid var(--border-light)" }}>
                    <td style={{ textOverflow: "ellipsis", overflow: "hidden", whiteSpace: "nowrap", padding: "8px", fontSize: "0.8rem" }}>
                      <span style={{ display: "flex", alignItems: "center", gap: "6px", opacity: 0.8 }}>
                        <FileAudio size={14} /> {item.filename}
                      </span>
                    </td>
                    <td style={{ padding: "8px", fontSize: "0.85rem", fontWeight: 600, color: "var(--accent)" }}>
                      {item.displayTitle}
                    </td>
                    <td style={{ padding: "8px", fontSize: "0.85rem", opacity: 0.9 }}>
                      {item.displayArtist}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </div>

        {/* 底部操作按钮 */}
        <div style={{ display: "flex", justifyContent: "flex-end", gap: "12px", marginTop: "16px" }}>
          <button className="import-btn" style={{ background: "transparent", borderColor: "var(--border)", color: "var(--text)" }} onClick={onClose}>
            取消
          </button>
          <button className="import-btn" onClick={handleImportClick} disabled={loading || processed.length === 0}>
            <Check size={16} /> 确认导入并匹配 ({processed.length} 首)
          </button>
        </div>
      </div>
    </div>
  );
}
