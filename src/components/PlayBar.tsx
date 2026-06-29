import { Play, Pause, SkipForward, SkipBack, Volume2, Shuffle, Repeat, Repeat1, LayoutList, FileAudio, Music } from "lucide-react";

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
  tags: any[];
}

interface PlayBarProps {
  canvasRef: React.RefObject<HTMLCanvasElement | null>;
  playingSong: Song | null;
  playingVersion: AudioVersion | null;
  isPlaying: boolean;
  currentTime: number;
  duration: number;
  volume: number;
  playMode: "list" | "single" | "shuffle";
  isLyricsOverlayOpen: boolean;
  onSetLyricsOverlayOpen: (open: boolean) => void;
  onPlayPause: () => void;
  onPrev: () => void;
  onNext: () => void;
  onPlaybackModeCycle: () => void;
  onSeek: (seekTime: number) => void;
  onVolumeChange: (volumePct: number) => void;
}

export default function PlayBar({
  canvasRef,
  playingSong,
  playingVersion,
  isPlaying,
  currentTime,
  duration,
  volume,
  playMode,
  isLyricsOverlayOpen,
  onSetLyricsOverlayOpen,
  onPlayPause,
  onPrev,
  onNext,
  onPlaybackModeCycle,
  onSeek,
  onVolumeChange,
}: PlayBarProps) {

  // 播放进度拖拽控制
  const handleProgressMouseDown = (e: React.MouseEvent<HTMLDivElement>) => {
    updateProgressFromEvent(e);
    
    const handleMouseMove = (moveEvent: MouseEvent) => {
      updateProgressFromEvent(moveEvent);
    };
    
    const handleMouseUp = () => {
      window.removeEventListener("mousemove", handleMouseMove);
      window.removeEventListener("mouseup", handleMouseUp);
    };
    
    window.addEventListener("mousemove", handleMouseMove);
    window.addEventListener("mouseup", handleMouseUp);
  };

  const updateProgressFromEvent = (e: React.MouseEvent<HTMLDivElement> | MouseEvent) => {
    const track = document.querySelector(".playbar-progress-container");
    if (!track || duration === 0) return;
    const rect = track.getBoundingClientRect();
    const clickX = e.clientX - rect.left;
    const pct = Math.max(0, Math.min(1, clickX / rect.width));
    onSeek(pct * duration);
  };

  // 音量进度条拖拽事件控制
  const handleVolumeMouseDown = (e: React.MouseEvent<HTMLDivElement>) => {
    updateVolumeFromEvent(e);
    
    const handleMouseMove = (moveEvent: MouseEvent) => {
      updateVolumeFromEvent(moveEvent);
    };
    
    const handleMouseUp = () => {
      window.removeEventListener("mousemove", handleMouseMove);
      window.removeEventListener("mouseup", handleMouseUp);
    };
    
    window.addEventListener("mousemove", handleMouseMove);
    window.addEventListener("mouseup", handleMouseUp);
  };

  const updateVolumeFromEvent = (e: React.MouseEvent<HTMLDivElement> | MouseEvent) => {
    const slider = document.querySelector(".volume-slider");
    if (!slider) return;
    const rect = slider.getBoundingClientRect();
    const clickX = e.clientX - rect.left;
    const pct = Math.max(0, Math.min(1, clickX / rect.width));
    onVolumeChange(pct);
  };

  const formatTime = (secs: number) => {
    if (isNaN(secs)) return "0:00";
    const m = Math.floor(secs / 60);
    const s = Math.floor(secs % 60);
    return `${m}:${s < 10 ? "0" : ""}${s}`;
  };

  return (
    <div className="playbar">
      {/* 最上边缘的无感进度条 */}
      <div className="playbar-progress-container" onMouseDown={handleProgressMouseDown}>
        <div 
          className="slider-fill" 
          style={{ width: `${duration > 0 ? (currentTime / duration) * 100 : 0}%` }}
        ></div>
        <div 
          className="slider-handle" 
          style={{ left: `${duration > 0 ? (currentTime / duration) * 100 : 0}%` }}
        ></div>
      </div>

      {/* 1. 当前曲目卡片 */}
      <div className="playbar-track-info">
        <div className="playbar-cover" onClick={() => onSetLyricsOverlayOpen(true)} style={{ cursor: "pointer" }} title="点击打开歌词">
          {playingSong ? <FileAudio size={22} color="var(--accent)" /> : <Music size={22} />}
        </div>
        <div className="playbar-meta">
          <span className="playbar-title" title={playingSong?.title || "未开始播放"}>
            {playingSong?.title || "未开始播放"}
          </span>
          <span className="playbar-artist">
            {playingSong ? `${playingSong.artist || "未知歌手"} · ${playingVersion?.format.toUpperCase() || ""}` : "Aetheria 音乐库"}
          </span>
        </div>
      </div>

      {/* 2. 播放动作控制与循环模式 */}
      <div className="playbar-controls">
        <div className="control-buttons">
          <button 
            className={`ctrl-btn ${playMode === "shuffle" ? "active" : ""}`} 
            onClick={onPlaybackModeCycle} 
            title="切换到随机播放"
          >
            <Shuffle size={18} />
          </button>
          
          <button className="ctrl-btn" onClick={onPrev} title="上一首">
            <SkipBack size={20} />
          </button>
          
          <button className="ctrl-btn play-pause" onClick={onPlayPause}>
            {isPlaying ? <Pause size={20} /> : <Play size={20} style={{ transform: "translateX(1px)" }} />}
          </button>
          
          <button className="ctrl-btn" onClick={onNext} title="下一首">
            <SkipForward size={20} />
          </button>

          <button 
            className="ctrl-btn" 
            onClick={onPlaybackModeCycle} 
            title={playMode === "single" ? "单曲循环" : "列表循环"}
          >
            {playMode === "single" ? <Repeat1 size={18} className="active" /> : <Repeat size={18} />}
          </button>
        </div>

        <div style={{ fontSize: "0.75rem", color: "var(--text-sub)", display: "flex", gap: "8px" }}>
          <span>{formatTime(currentTime)}</span>
          <span>/</span>
          <span>{formatTime(duration)}</span>
        </div>
      </div>

      {/* 3. 音量控制器与歌词开关 */}
      <div className="playbar-volume">
        <button 
          className={`ctrl-btn ${isLyricsOverlayOpen ? "active" : ""}`} 
          style={{ marginRight: 10 }}
          onClick={() => onSetLyricsOverlayOpen(!isLyricsOverlayOpen)} 
          title="歌词面板"
        >
          <LayoutList size={18} />
        </button>
        
        <Volume2 size={16} color="var(--text-sub)" />
        <span className="volume-pct-label">{Math.round(volume * 100)}%</span>
        <div className="volume-slider" onMouseDown={handleVolumeMouseDown}>
          <div className="slider-fill" style={{ width: `${volume * 100}%` }}></div>
          <div className="slider-handle" style={{ left: `${volume * 100}%` }}></div>
        </div>
      </div>

      {/* 动画频谱 Canvas */}
      <canvas ref={canvasRef} className="visualizer-canvas" width={1000} height={36} />
    </div>
  );
}
