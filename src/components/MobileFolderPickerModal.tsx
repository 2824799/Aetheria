import { useState, useEffect } from "react";
import { invoke } from "@tauri-apps/api/core";
import { Folder, ChevronRight, X, ArrowLeft, FileAudio } from "lucide-react";

interface DirEntry {
  name: string;
  path: string;
  is_dir: boolean;
}

interface MobileFolderPickerModalProps {
  isOpen: boolean;
  onClose: () => void;
  onSelect: (paths: string | string[]) => void;
  mode?: "folder" | "file";
  multiple?: boolean;
}

export default function MobileFolderPickerModal({
  isOpen,
  onClose,
  onSelect,
  mode = "folder",
  multiple = false,
}: MobileFolderPickerModalProps) {
  const [currentPath, setCurrentPath] = useState<string>("/storage/emulated/0");
  const [directories, setDirectories] = useState<DirEntry[]>([]);
  const [loading, setLoading] = useState(false);
  const [errorMsg, setErrorMsg] = useState("");
  const [selectedFiles, setSelectedFiles] = useState<Set<string>>(new Set());

  useEffect(() => {
    if (isOpen) {
      loadDirectory(currentPath);
      setSelectedFiles(new Set()); // Reset selections on open
    }
  }, [isOpen, currentPath, mode]);

  const loadDirectory = async (path: string) => {
    setLoading(true);
    setErrorMsg("");
    try {
      const command = mode === "folder" ? "list_directories" : "list_contents";
      const dirs: DirEntry[] = await invoke(command, { path });
      setDirectories(dirs);
    } catch (err) {
      console.error("Failed to load directory:", err);
      setErrorMsg(String(err));
      if (path !== "/storage/emulated/0") {
        setCurrentPath("/storage/emulated/0");
      }
    } finally {
      setLoading(false);
    }
  };

  const handleGoBack = () => {
    if (currentPath === "/storage/emulated/0" || currentPath === "/") return;
    const parts = currentPath.split("/").filter(Boolean);
    parts.pop();
    const parentPath = "/" + parts.join("/");
    setCurrentPath(parentPath || "/");
  };

  const toggleFileSelection = (path: string) => {
    setSelectedFiles((prev) => {
      const next = new Set(prev);
      if (next.has(path)) {
        next.delete(path);
      } else {
        if (!multiple) next.clear();
        next.add(path);
      }
      return next;
    });
  };

  if (!isOpen) return null;

  return (
    <div className="modal-overlay" onClick={onClose} style={{ zIndex: 10000 }}>
      <div 
        className="modal-content" 
        onClick={(e) => e.stopPropagation()} 
        style={{ width: '90%', height: '80vh', display: 'flex', flexDirection: 'column' }}
      >
        <div className="modal-header">
          <button className="ctrl-btn" onClick={handleGoBack} disabled={currentPath === "/storage/emulated/0"}>
            <ArrowLeft size={20} />
          </button>
          <span className="modal-title" style={{ flex: 1, fontSize: '1.1rem', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap', marginLeft: '12px' }}>
            选择{mode === "folder" ? "目录" : "文件"}
          </span>
          <button className="ctrl-btn" onClick={onClose}>
            <X size={20} />
          </button>
        </div>

        <div style={{ padding: "8px 16px", background: "var(--bg-hover)", fontSize: "0.85rem", wordBreak: "break-all", borderBottom: "1px solid var(--border)" }}>
          当前: {currentPath}
        </div>

        <div style={{ flex: 1, overflowY: 'auto', padding: '8px 0' }}>
          {loading ? (
            <div style={{ padding: '20px', textAlign: 'center', color: 'var(--text-sub)' }}>正在加载...</div>
          ) : errorMsg ? (
            <div style={{ padding: '20px', textAlign: 'center', color: '#ef4444' }}>无法访问该目录: {errorMsg}</div>
          ) : directories.length === 0 ? (
            <div style={{ padding: '20px', textAlign: 'center', color: 'var(--text-sub)' }}>该目录下没有内容</div>
          ) : (
            directories.map((dir) => (
              <div 
                key={dir.path}
                onClick={() => {
                  if (dir.is_dir) {
                    setCurrentPath(dir.path);
                  } else if (mode === "file") {
                    toggleFileSelection(dir.path);
                  }
                }}
                style={{ 
                  display: 'flex', 
                  alignItems: 'center', 
                  padding: '16px', 
                  borderBottom: '1px solid var(--border)',
                  cursor: 'pointer',
                  background: !dir.is_dir && selectedFiles.has(dir.path) ? 'var(--bg-hover)' : 'transparent'
                }}
              >
                {dir.is_dir ? (
                  <Folder size={24} color="var(--accent)" style={{ marginRight: '16px' }} />
                ) : (
                  <FileAudio size={24} color="var(--text-sub)" style={{ marginRight: '16px' }} />
                )}
                
                <span style={{ 
                  flex: 1, 
                  fontSize: '1rem',
                  color: !dir.is_dir && selectedFiles.has(dir.path) ? 'var(--accent)' : 'inherit',
                  fontWeight: !dir.is_dir && selectedFiles.has(dir.path) ? 'bold' : 'normal'
                }}>
                  {dir.name}
                </span>
                
                {dir.is_dir ? (
                  <ChevronRight size={18} color="var(--text-sub)" />
                ) : (
                  <div style={{ 
                    width: '20px', 
                    height: '20px', 
                    border: '2px solid var(--accent)', 
                    borderRadius: '50%',
                    background: selectedFiles.has(dir.path) ? 'var(--accent)' : 'transparent'
                  }} />
                )}
              </div>
            ))
          )}
        </div>

        <div className="modal-footer" style={{ padding: '16px', borderTop: '1px solid var(--border)' }}>
          <button 
            className="import-btn" 
            style={{ 
              width: '100%', 
              padding: '14px', 
              fontSize: '1.1rem', 
              borderRadius: '12px', 
              background: mode === 'file' && selectedFiles.size === 0 ? 'var(--bg-hover)' : 'var(--accent)', 
              color: mode === 'file' && selectedFiles.size === 0 ? 'var(--text-sub)' : '#fff', 
              border: 'none', 
              fontWeight: 'bold',
              cursor: mode === 'file' && selectedFiles.size === 0 ? 'not-allowed' : 'pointer'
            }}
            disabled={mode === 'file' && selectedFiles.size === 0}
            onClick={() => {
              if (mode === "folder") {
                onSelect(currentPath);
              } else {
                onSelect(Array.from(selectedFiles));
              }
            }}
          >
            {mode === "folder" ? "使用此文件夹" : `确认选择 (${selectedFiles.size}项)`}
          </button>
        </div>
      </div>
    </div>
  );
}
