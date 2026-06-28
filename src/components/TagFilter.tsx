import { Tag as TagIcon, ChevronDown, ChevronRight } from "lucide-react";

interface Tag {
  id: number;
  name: string;
  color: string;
  category?: string;
  created_at: string;
}

interface TagFilterProps {
  tags: Tag[];
  selectedTags: number[];
  onToggleTag: (id: number) => void;
  filterMode: "AND" | "OR";
  onSetFilterMode: (mode: "AND" | "OR") => void;
  isTagsExpanded: boolean;
  onSetTagsExpanded: (expanded: boolean) => void;
  onOpenTagManager: () => void;
}

export default function TagFilter({
  tags,
  selectedTags,
  onToggleTag,
  filterMode,
  onSetFilterMode,
  isTagsExpanded,
  onSetTagsExpanded,
  onOpenTagManager,
}: TagFilterProps) {
  return (
    <div className="tag-matrix-panel">
      {/* 标签头部重构：左侧交并集，右侧标签管理器，中间折叠标题 */}
      <div className="tag-matrix-header" style={{ display: "flex", justifyContent: "space-between", alignItems: "center", width: "100%" }}>
        <div className="filter-toggle-container" onClick={e => e.stopPropagation()}>
          <div 
            className={`filter-toggle-btn ${filterMode === "AND" ? "active" : ""}`}
            onClick={() => onSetFilterMode("AND")}
          >
            交集 (AND)
          </div>
          <div 
            className={`filter-toggle-btn ${filterMode === "OR" ? "active" : ""}`}
            onClick={() => onSetFilterMode("OR")}
          >
            并集 (OR)
          </div>
        </div>

        <span 
          className="tag-matrix-title-wrapper" 
          onClick={() => onSetTagsExpanded(!isTagsExpanded)}
          style={{ cursor: "pointer", userSelect: "none" }}
        >
          <TagIcon size={16} /> 
          标签多维过滤器
          {isTagsExpanded ? <ChevronDown size={16} /> : <ChevronRight size={16} />}
        </span>

        <button 
          className="import-btn" 
          style={{ margin: 0, padding: "6px 12px", fontSize: "0.8rem", height: "auto" }}
          onClick={onOpenTagManager}
        >
          <TagIcon size={12} /> 标签管理
        </button>
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
                onClick={() => onToggleTag(tag.id)}
              >
                <span style={{ display: 'inline-block', width: 8, height: 8, borderRadius: '50%', backgroundColor: tag.color || "#cbd5e1" }}></span>
                {tag.name}
              </div>
            );
          })}
          {tags.length === 0 && (
            <div style={{ color: "var(--text-sub)", fontSize: "0.85rem" }}>暂无预设标签，可点击右侧标签管理新建</div>
          )}
        </div>
      </div>
    </div>
  );
}
