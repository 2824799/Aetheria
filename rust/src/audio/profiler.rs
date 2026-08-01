use serde::Serialize;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::time::{Instant, SystemTime, UNIX_EPOCH};

pub struct AtomicPerfMetric {
    calls: AtomicU64,
    total_nanos: AtomicU64,
    max_nanos: AtomicU64,
}

impl AtomicPerfMetric {
    pub const fn new() -> Self {
        Self {
            calls: AtomicU64::new(0),
            total_nanos: AtomicU64::new(0),
            max_nanos: AtomicU64::new(0),
        }
    }

    fn record(&self, elapsed_nanos: u64) {
        self.calls.fetch_add(1, Ordering::Relaxed);
        self.total_nanos.fetch_add(elapsed_nanos, Ordering::Relaxed);
        let mut current = self.max_nanos.load(Ordering::Relaxed);
        while elapsed_nanos > current {
            match self.max_nanos.compare_exchange_weak(
                current,
                elapsed_nanos,
                Ordering::Relaxed,
                Ordering::Relaxed,
            ) {
                Ok(_) => break,
                Err(actual) => current = actual,
            }
        }
    }

    fn reset(&self) {
        self.calls.store(0, Ordering::Relaxed);
        self.total_nanos.store(0, Ordering::Relaxed);
        self.max_nanos.store(0, Ordering::Relaxed);
    }

    fn snapshot(&self, id: &'static str, label: &'static str) -> PerfMetricSnapshot {
        let calls = self.calls.load(Ordering::Relaxed);
        let total_nanos = self.total_nanos.load(Ordering::Relaxed);
        let max_nanos = self.max_nanos.load(Ordering::Relaxed);
        PerfMetricSnapshot {
            id,
            label,
            calls,
            total_ms: total_nanos as f64 / 1_000_000.0,
            average_us: if calls == 0 {
                0.0
            } else {
                total_nanos as f64 / calls as f64 / 1_000.0
            },
            max_us: max_nanos as f64 / 1_000.0,
        }
    }
}

pub struct AudioProfiler {
    pub decode_packet: AtomicPerfMetric,
    pub decode_resample_block: AtomicPerfMetric,
    pub sinc_resampler: AtomicPerfMetric,
    pub pitch_shift: AtomicPerfMetric,
    pub post_dsp_protection: AtomicPerfMetric,
    pub buffer_push_wait: AtomicPerfMetric,
    pub output_callback: AtomicPerfMetric,
}

impl AudioProfiler {
    const fn new() -> Self {
        Self {
            decode_packet: AtomicPerfMetric::new(),
            decode_resample_block: AtomicPerfMetric::new(),
            sinc_resampler: AtomicPerfMetric::new(),
            pitch_shift: AtomicPerfMetric::new(),
            post_dsp_protection: AtomicPerfMetric::new(),
            buffer_push_wait: AtomicPerfMetric::new(),
            output_callback: AtomicPerfMetric::new(),
        }
    }

    fn reset(&self) {
        self.decode_packet.reset();
        self.decode_resample_block.reset();
        self.sinc_resampler.reset();
        self.pitch_shift.reset();
        self.post_dsp_protection.reset();
        self.buffer_push_wait.reset();
        self.output_callback.reset();
    }

    fn snapshots(&self) -> Vec<PerfMetricSnapshot> {
        let mut metrics = vec![
            self.decode_packet
                .snapshot("decode_packet", "音频包解码与声道转换"),
            self.decode_resample_block
                .snapshot("decode_resample_block", "解码/重采样块总耗时"),
            self.sinc_resampler
                .snapshot("sinc_resampler", "Sinc 重采样"),
            self.pitch_shift.snapshot("pitch_shift", "变调处理"),
            self.post_dsp_protection
                .snapshot("post_dsp_protection", "峰值保护与输出检查"),
            self.buffer_push_wait
                .snapshot("buffer_push_wait", "队列写入与等待"),
            self.output_callback
                .snapshot("output_callback", "设备输出回调"),
        ];
        metrics.sort_by(|a, b| {
            b.total_ms
                .partial_cmp(&a.total_ms)
                .unwrap_or(std::cmp::Ordering::Equal)
        });
        metrics
    }
}

pub static AUDIO_PROFILER: AudioProfiler = AudioProfiler::new();
static PROFILING_ENABLED: AtomicBool = AtomicBool::new(false);
static SESSION_STARTED_UNIX_MS: AtomicU64 = AtomicU64::new(0);

pub struct PerfScope {
    metric: &'static AtomicPerfMetric,
    started_at: Instant,
}

impl Drop for PerfScope {
    fn drop(&mut self) {
        self.metric
            .record(self.started_at.elapsed().as_nanos().min(u64::MAX as u128) as u64);
    }
}

#[inline]
pub fn scope(metric: &'static AtomicPerfMetric) -> Option<PerfScope> {
    PROFILING_ENABLED
        .load(Ordering::Relaxed)
        .then(|| PerfScope {
            metric,
            started_at: Instant::now(),
        })
}

pub fn set_enabled(enabled: bool) {
    let changed = PROFILING_ENABLED.swap(enabled, Ordering::Relaxed) != enabled;
    if enabled && changed {
        reset();
    }
}

pub fn is_enabled() -> bool {
    PROFILING_ENABLED.load(Ordering::Relaxed)
}

pub fn reset() {
    AUDIO_PROFILER.reset();
    SESSION_STARTED_UNIX_MS.store(unix_time_ms(), Ordering::Relaxed);
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct PerfMetricSnapshot {
    id: &'static str,
    label: &'static str,
    calls: u64,
    total_ms: f64,
    average_us: f64,
    max_us: f64,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct PerformanceReport {
    enabled: bool,
    generated_at_unix_ms: u64,
    session_started_unix_ms: u64,
    note: &'static str,
    metrics: Vec<PerfMetricSnapshot>,
}

pub fn report_json() -> String {
    let report = PerformanceReport {
        enabled: is_enabled(),
        generated_at_unix_ms: unix_time_ms(),
        session_started_unix_ms: SESSION_STARTED_UNIX_MS.load(Ordering::Relaxed),
        note: "指标按音频块采样；嵌套阶段会重叠，不应把各项总耗时直接相加当作进程 CPU 时间。",
        metrics: AUDIO_PROFILER.snapshots(),
    };
    serde_json::to_string_pretty(&report).unwrap_or_else(|_| "{}".to_string())
}

pub fn report_markdown() -> String {
    let mut output = String::from(
        "# Aetheria 音频性能报告\n\n\
         > 指标按音频块采样；嵌套阶段会重叠，不应把各项总耗时直接相加当作进程 CPU 时间。\n\n\
         | 热点 | 调用次数 | 总耗时 (ms) | 平均 (μs) | 最大 (μs) |\n\
         |---|---:|---:|---:|---:|\n",
    );
    for metric in AUDIO_PROFILER.snapshots() {
        output.push_str(&format!(
            "| {} | {} | {:.3} | {:.3} | {:.3} |\n",
            metric.label, metric.calls, metric.total_ms, metric.average_us, metric.max_us
        ));
    }
    output
}

fn unix_time_ms() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis()
        .min(u64::MAX as u128) as u64
}
