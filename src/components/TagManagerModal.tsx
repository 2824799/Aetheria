import { X, Plus, Trash2 } from "lucide-react";

interface Tag {
  id: number;
  name: string;
  color: string;
  category?: string;
  created_at: string;
}

interface TagManagerModalProps {
  isOpen: boolean;
  onClose: () => void;
  tags: Tag[];
  newTagName: string;
  setNewTagName: (val: string) => void;
  newTagColor: string;
  setNewTagColor: (val: string) => void;
  newTagCategory: string;
  setNewTagCategory: (val: string) => void;
  presetColors: string[];
  onCreateTag: () => void;
  onDeleteTag: (id: number) => void;
}

export default function TagManagerModal({
  isOpen,
  onClose,
  tags,
  newTagName,
  setNewTagName,
  newTagColor,
  setNewTagColor,
  newTagCategory,
  setNewTagCategory,
  presetColors,
  onCreateTag,
  onDeleteTag,
}: TagManagerModalProps) {
  if (!isOpen) return null;

  return (
    <div className="modal-overlay" onClick={onClose}>
      <div className="modal-content" onClick={e => e.stopPropagation()}>
        <div className="modal-header">
          <span className="modal-title">管理已有标签</span>
          <button className="ctrl-btn" onClick={onClose}><X size={18} /></button>
        </div>
        
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
            {/* 新增类别选择下拉菜单，让用户自由定义标签组 */}
            <select
              className="text-input"
              style={{ width: "90px", fontSize: "0.85rem", padding: "4px 8px" }}
              value={newTagCategory}
              onChange={e => setNewTagCategory(e.target.value)}
            >
              <option value="流派">流派</option>
              <option value="语言">语言</option>
              <option value="情绪">情绪</option>
              <option value="场景">场景</option>
              <option value="自定义">自定义</option>
            </select>
            <button className="btn-primary" onClick={onCreateTag}>
              <Plus size={16} /> 创建
            </button>
          </div>
          <div className="color-picker-grid">
            {presetColors.map(c => (
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
              <button className="ctrl-btn" style={{ color: "#ef4444" }} onClick={() => onDeleteTag(tag.id)}>
                <Trash2 size={16} />
              </button>
            </div>
          ))}
          {tags.length === 0 && (
            <div style={{ color: "#64748b", textAlign: "center", padding: "12px" }}>暂无标签</div>
          )}
        </div>

        <div className="modal-footer">
          <button className="btn-secondary" style={{ width: "100%" }} onClick={onClose}>关闭</button>
        </div>
      </div>
    </div>
  );
}
