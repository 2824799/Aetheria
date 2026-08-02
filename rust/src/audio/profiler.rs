//! Low-overhead, opt-in call-tree profiler for the Rust audio engine.
//!
//! The profiler is deliberately disabled by default. When enabled it records
//! inclusive and self time for every instrumented Rust audio function. Each
//! thread owns its aggregation bucket, so the audio thread never contends with
//! other worker threads while recording. The report merges those buckets into
//! a flat hotspot table and also preserves the per-thread call tree.

use serde::Serialize;
use std::cell::RefCell;
use std::collections::HashMap;
use std::marker::PhantomData;
use std::rc::Rc;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{Arc, Mutex, OnceLock};
use std::time::{Instant, SystemTime, UNIX_EPOCH};

const NANOS_PER_MILLISECOND: f64 = 1_000_000.0;
const NANOS_PER_MICROSECOND: f64 = 1_000.0;

#[derive(Default)]
struct MetricTotals {
    calls: u64,
    wall_total_nanos: u128,
    wall_self_nanos: u128,
    cpu_total_nanos: u128,
    cpu_self_nanos: u128,
    max_wall_nanos: u128,
    max_cpu_nanos: u128,
}

impl MetricTotals {
    fn record(
        &mut self,
        wall_total_nanos: u128,
        wall_self_nanos: u128,
        cpu_total_nanos: u128,
        cpu_self_nanos: u128,
    ) {
        self.calls = self.calls.saturating_add(1);
        self.wall_total_nanos = self.wall_total_nanos.saturating_add(wall_total_nanos);
        self.wall_self_nanos = self.wall_self_nanos.saturating_add(wall_self_nanos);
        self.cpu_total_nanos = self.cpu_total_nanos.saturating_add(cpu_total_nanos);
        self.cpu_self_nanos = self.cpu_self_nanos.saturating_add(cpu_self_nanos);
        self.max_wall_nanos = self.max_wall_nanos.max(wall_total_nanos);
        self.max_cpu_nanos = self.max_cpu_nanos.max(cpu_total_nanos);
    }

    fn merge(&mut self, other: &MetricTotals) {
        self.calls = self.calls.saturating_add(other.calls);
        self.wall_total_nanos = self.wall_total_nanos.saturating_add(other.wall_total_nanos);
        self.wall_self_nanos = self.wall_self_nanos.saturating_add(other.wall_self_nanos);
        self.cpu_total_nanos = self.cpu_total_nanos.saturating_add(other.cpu_total_nanos);
        self.cpu_self_nanos = self.cpu_self_nanos.saturating_add(other.cpu_self_nanos);
        self.max_wall_nanos = self.max_wall_nanos.max(other.max_wall_nanos);
        self.max_cpu_nanos = self.max_cpu_nanos.max(other.max_cpu_nanos);
    }
}

struct ProfileNode {
    name: &'static str,
    children: HashMap<&'static str, usize>,
    metrics: MetricTotals,
}

struct ActiveFrame {
    node_index: usize,
    started_wall: Instant,
    started_cpu_nanos: Option<u64>,
    child_wall_nanos: u128,
    child_cpu_nanos: u128,
}

struct ThreadProfile {
    thread_id: String,
    thread_name: String,
    generation: u64,
    roots: HashMap<&'static str, usize>,
    nodes: Vec<ProfileNode>,
    stack: Vec<ActiveFrame>,
}

impl ThreadProfile {
    fn new() -> Self {
        let thread = std::thread::current();
        Self {
            thread_id: format!("{:?}", thread.id()),
            thread_name: thread.name().unwrap_or("unnamed").to_string(),
            generation: 0,
            roots: HashMap::new(),
            nodes: Vec::new(),
            stack: Vec::new(),
        }
    }

    fn prepare_generation(&mut self, generation: u64) {
        if self.generation == generation {
            return;
        }
        self.generation = generation;
        self.roots.clear();
        self.nodes.clear();
        self.stack.clear();
    }

    fn enter(&mut self, name: &'static str, generation: u64) {
        self.prepare_generation(generation);
        let node_index = if let Some(parent) = self.stack.last() {
            if let Some(child) = self.nodes[parent.node_index].children.get(name) {
                *child
            } else {
                let child = self.nodes.len();
                self.nodes.push(ProfileNode {
                    name,
                    children: HashMap::new(),
                    metrics: MetricTotals::default(),
                });
                self.nodes[parent.node_index].children.insert(name, child);
                child
            }
        } else if let Some(root) = self.roots.get(name) {
            *root
        } else {
            let root = self.nodes.len();
            self.nodes.push(ProfileNode {
                name,
                children: HashMap::new(),
                metrics: MetricTotals::default(),
            });
            self.roots.insert(name, root);
            root
        };

        self.stack.push(ActiveFrame {
            node_index,
            started_wall: Instant::now(),
            started_cpu_nanos: thread_cpu_time_nanos(),
            child_wall_nanos: 0,
            child_cpu_nanos: 0,
        });
    }

    fn exit(&mut self, generation: u64) {
        if self.generation != generation {
            return;
        }
        let Some(frame) = self.stack.pop() else {
            return;
        };

        let wall_total_nanos = frame.started_wall.elapsed().as_nanos();
        let wall_self_nanos = wall_total_nanos.saturating_sub(frame.child_wall_nanos);
        let cpu_total_nanos = match (frame.started_cpu_nanos, thread_cpu_time_nanos()) {
            (Some(start), Some(end)) => u128::from(end.saturating_sub(start)),
            _ => 0,
        };
        let cpu_self_nanos = cpu_total_nanos.saturating_sub(frame.child_cpu_nanos);

        self.nodes[frame.node_index].metrics.record(
            wall_total_nanos,
            wall_self_nanos,
            cpu_total_nanos,
            cpu_self_nanos,
        );

        if let Some(parent) = self.stack.last_mut() {
            parent.child_wall_nanos = parent.child_wall_nanos.saturating_add(wall_total_nanos);
            parent.child_cpu_nanos = parent.child_cpu_nanos.saturating_add(cpu_total_nanos);
        }
    }
}

static PROFILING_ENABLED: AtomicBool = AtomicBool::new(false);
static GENERATION: AtomicU64 = AtomicU64::new(1);
static SESSION_STARTED_UNIX_MS: AtomicU64 = AtomicU64::new(0);
static NEXT_THREAD_BUCKET: OnceLock<Mutex<Vec<Arc<Mutex<ThreadProfile>>>>> = OnceLock::new();

thread_local! {
    static THREAD_PROFILE: RefCell<Option<Arc<Mutex<ThreadProfile>>>> = const { RefCell::new(None) };
}

fn thread_buckets() -> &'static Mutex<Vec<Arc<Mutex<ThreadProfile>>>> {
    NEXT_THREAD_BUCKET.get_or_init(|| Mutex::new(Vec::new()))
}

fn current_thread_profile() -> Arc<Mutex<ThreadProfile>> {
    THREAD_PROFILE.with(|slot| {
        if let Some(existing) = slot.borrow().as_ref().cloned() {
            return existing;
        }

        let profile = Arc::new(Mutex::new(ThreadProfile::new()));
        thread_buckets()
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
            .push(profile.clone());
        *slot.borrow_mut() = Some(profile.clone());
        profile
    })
}

/// RAII scope used by instrumented functions.
///
/// `Rc` makes this guard intentionally non-Send: a scope must be exited on the
/// same thread that entered it, which is a useful invariant for the call tree.
pub struct PerfScope {
    generation: u64,
    _not_send: PhantomData<Rc<()>>,
}

impl Drop for PerfScope {
    fn drop(&mut self) {
        THREAD_PROFILE.with(|slot| {
            let Some(profile) = slot.borrow().as_ref().cloned() else {
                return;
            };
            profile
                .lock()
                .unwrap_or_else(|poisoned| poisoned.into_inner())
                .exit(self.generation);
        });
    }
}

/// Starts a named function scope when profiling is enabled.
///
/// This is cheap while disabled: one relaxed atomic load and no allocation.
#[inline]
pub fn scope(name: &'static str) -> Option<PerfScope> {
    if !PROFILING_ENABLED.load(Ordering::Relaxed) {
        return None;
    }

    let generation = GENERATION.load(Ordering::Acquire);
    let profile = current_thread_profile();
    profile
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner())
        .enter(name, generation);
    Some(PerfScope {
        generation,
        _not_send: PhantomData,
    })
}

pub fn set_enabled(enabled: bool) {
    let changed = PROFILING_ENABLED.swap(enabled, Ordering::Release) != enabled;
    if enabled && changed {
        reset();
    }
}

pub fn is_enabled() -> bool {
    PROFILING_ENABLED.load(Ordering::Acquire)
}

pub fn reset() {
    GENERATION.fetch_add(1, Ordering::AcqRel);
    SESSION_STARTED_UNIX_MS.store(unix_time_ms(), Ordering::Release);
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct MetricSnapshot {
    id: &'static str,
    calls: u64,
    cpu_total_ms: f64,
    cpu_self_ms: f64,
    wall_total_ms: f64,
    wall_self_ms: f64,
    average_cpu_us: f64,
    average_wall_us: f64,
    max_cpu_us: f64,
    max_wall_us: f64,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct CallTreeNodeSnapshot {
    name: &'static str,
    metrics: MetricSnapshot,
    children: Vec<CallTreeNodeSnapshot>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct ThreadSnapshot {
    id: String,
    name: String,
    cpu_total_ms: f64,
    wall_total_ms: f64,
    call_tree: Vec<CallTreeNodeSnapshot>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct PerformanceReport {
    schema_version: u32,
    enabled: bool,
    capture_mode: &'static str,
    cpu_clock: &'static str,
    generated_at_unix_ms: u64,
    session_started_unix_ms: u64,
    session_duration_ms: u64,
    note: &'static str,
    metrics: Vec<MetricSnapshot>,
    threads: Vec<ThreadSnapshot>,
}

fn metric_snapshot(id: &'static str, metrics: &MetricTotals) -> MetricSnapshot {
    let calls = metrics.calls.max(1) as f64;
    MetricSnapshot {
        id,
        calls: metrics.calls,
        cpu_total_ms: metrics.cpu_total_nanos as f64 / NANOS_PER_MILLISECOND,
        cpu_self_ms: metrics.cpu_self_nanos as f64 / NANOS_PER_MILLISECOND,
        wall_total_ms: metrics.wall_total_nanos as f64 / NANOS_PER_MILLISECOND,
        wall_self_ms: metrics.wall_self_nanos as f64 / NANOS_PER_MILLISECOND,
        average_cpu_us: metrics.cpu_total_nanos as f64 / calls / NANOS_PER_MICROSECOND,
        average_wall_us: metrics.wall_total_nanos as f64 / calls / NANOS_PER_MICROSECOND,
        max_cpu_us: metrics.max_cpu_nanos as f64 / NANOS_PER_MICROSECOND,
        max_wall_us: metrics.max_wall_nanos as f64 / NANOS_PER_MICROSECOND,
    }
}

fn snapshot_node(profile: &ThreadProfile, node_index: usize) -> CallTreeNodeSnapshot {
    let node = &profile.nodes[node_index];
    let mut children: Vec<usize> = node.children.values().copied().collect();
    children.sort_by(|left, right| {
        profile.nodes[*right]
            .metrics
            .cpu_self_nanos
            .cmp(&profile.nodes[*left].metrics.cpu_self_nanos)
    });

    CallTreeNodeSnapshot {
        name: node.name,
        metrics: metric_snapshot(node.name, &node.metrics),
        children: children
            .into_iter()
            .map(|child| snapshot_node(profile, child))
            .collect(),
    }
}

fn snapshot_thread(profile: &ThreadProfile) -> ThreadSnapshot {
    let mut roots: Vec<usize> = profile.roots.values().copied().collect();
    roots.sort_by(|left, right| {
        profile.nodes[*right]
            .metrics
            .cpu_self_nanos
            .cmp(&profile.nodes[*left].metrics.cpu_self_nanos)
    });

    let mut cpu_total_nanos = 0u128;
    let mut wall_total_nanos = 0u128;
    for root in &roots {
        cpu_total_nanos =
            cpu_total_nanos.saturating_add(profile.nodes[*root].metrics.cpu_total_nanos);
        wall_total_nanos =
            wall_total_nanos.saturating_add(profile.nodes[*root].metrics.wall_total_nanos);
    }

    ThreadSnapshot {
        id: profile.thread_id.clone(),
        name: profile.thread_name.clone(),
        cpu_total_ms: cpu_total_nanos as f64 / NANOS_PER_MILLISECOND,
        wall_total_ms: wall_total_nanos as f64 / NANOS_PER_MILLISECOND,
        call_tree: roots
            .into_iter()
            .map(|root| snapshot_node(profile, root))
            .collect(),
    }
}

fn collect_snapshots() -> (Vec<MetricSnapshot>, Vec<ThreadSnapshot>) {
    let generation = GENERATION.load(Ordering::Acquire);
    let buckets = thread_buckets()
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner())
        .clone();
    let mut flat: HashMap<&'static str, MetricTotals> = HashMap::new();
    let mut threads = Vec::new();

    for bucket in buckets {
        let profile = bucket
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        if profile.generation != generation {
            continue;
        }

        for node in &profile.nodes {
            flat.entry(node.name).or_default().merge(&node.metrics);
        }
        threads.push(snapshot_thread(&profile));
    }

    let mut metrics: Vec<MetricSnapshot> = flat
        .into_iter()
        .map(|(name, totals)| metric_snapshot(name, &totals))
        .collect();
    metrics.sort_by(|left, right| {
        right
            .cpu_self_ms
            .partial_cmp(&left.cpu_self_ms)
            .unwrap_or(std::cmp::Ordering::Equal)
    });
    threads.sort_by(|left, right| {
        right
            .cpu_total_ms
            .partial_cmp(&left.cpu_total_ms)
            .unwrap_or(std::cmp::Ordering::Equal)
    });
    (metrics, threads)
}

pub fn report_json() -> String {
    let now = unix_time_ms();
    let started = SESSION_STARTED_UNIX_MS.load(Ordering::Acquire);
    let (metrics, threads) = collect_snapshots();
    let report = PerformanceReport {
        schema_version: 2,
        enabled: is_enabled(),
        capture_mode: "instrumented-call-tree",
        cpu_clock: if thread_cpu_time_nanos().is_some() {
            "per-thread CPU time"
        } else {
            "wall time fallback"
        },
        generated_at_unix_ms: now,
        session_started_unix_ms: started,
        session_duration_ms: now.saturating_sub(started),
        note: "这是 Aetheria Rust 音频引擎的调用树统计：CPU 总耗时包含子调用，CPU 自耗时扣除了已记录的子调用。未埋点的第三方解码器、操作系统和 Dart/Flutter VM 代码会归入最近的 Aetheria 父函数；关闭开发者模式时不产生统计开销。",
        metrics,
        threads,
    };
    serde_json::to_string_pretty(&report).unwrap_or_else(|_| "{}".to_string())
}

fn append_markdown_node(
    output: &mut String,
    node: &CallTreeNodeSnapshot,
    thread_name: &str,
    path: &mut Vec<&'static str>,
) {
    path.push(node.name);
    output.push_str(&format!(
        "| {} | {} | {} | {:.3} | {:.3} | {:.3} | {:.3} |\n",
        thread_name,
        path.join(" → "),
        node.metrics.calls,
        node.metrics.cpu_total_ms,
        node.metrics.cpu_self_ms,
        node.metrics.wall_total_ms,
        node.metrics.wall_self_ms,
    ));
    for child in &node.children {
        append_markdown_node(output, child, thread_name, path);
    }
    path.pop();
}

pub fn report_markdown() -> String {
    let now = unix_time_ms();
    let started = SESSION_STARTED_UNIX_MS.load(Ordering::Acquire);
    let (metrics, threads) = collect_snapshots();
    let mut output = String::from(
        "# Aetheria 性能报告\n\n\
         - 采集模式：instrumented-call-tree（调用树）\n\
         - CPU 时间：优先使用线程 CPU 时钟；不支持的平台回退到墙上时钟\n\
         - CPU 总耗时包含子调用；CPU 自耗时扣除已记录的子调用\n\
         - 第三方解码器、操作系统和 Dart/Flutter VM 代码会归入最近的 Aetheria 父函数\n\n",
    );
    output.push_str(&format!(
        "- 统计会话：{} → {}\n- 会话时长：{} ms\n- 线程数：{}\n\n",
        started,
        now,
        now.saturating_sub(started),
        threads.len()
    ));

    output.push_str(
        "## 函数热点（按 CPU 自耗时排序）\n\n\
         | 函数 | 调用次数 | CPU 总耗时 (ms) | CPU 自耗时 (ms) | 墙上总耗时 (ms) | 墙上自耗时 (ms) |\n\
         |---|---:|---:|---:|---:|---:|\n",
    );
    for metric in &metrics {
        output.push_str(&format!(
            "| `{}` | {} | {:.3} | {:.3} | {:.3} | {:.3} |\n",
            metric.id,
            metric.calls,
            metric.cpu_total_ms,
            metric.cpu_self_ms,
            metric.wall_total_ms,
            metric.wall_self_ms
        ));
    }

    output.push_str(
        "\n## 完整调用路径\n\n\
         | 线程 | 调用路径 | 调用次数 | CPU 总耗时 (ms) | CPU 自耗时 (ms) | 墙上总耗时 (ms) | 墙上自耗时 (ms) |\n\
         |---|---|---:|---:|---:|---:|---:|\n",
    );
    for thread in &threads {
        let mut path = Vec::new();
        for root in &thread.call_tree {
            append_markdown_node(&mut output, root, &thread.name, &mut path);
        }
    }
    output.push_str(
        "\n## 线程汇总\n\n| 线程 | CPU 总耗时 (ms) | 墙上总耗时 (ms) |\n|---|---:|---:|\n",
    );
    for thread in &threads {
        output.push_str(&format!(
            "| {} ({}) | {:.3} | {:.3} |\n",
            thread.name, thread.id, thread.cpu_total_ms, thread.wall_total_ms
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

#[cfg(any(target_os = "android", target_os = "linux"))]
fn thread_cpu_time_nanos() -> Option<u64> {
    #[repr(C)]
    struct Timespec {
        tv_sec: i64,
        tv_nsec: i64,
    }

    unsafe extern "C" {
        fn clock_gettime(clock_id: i32, timespec: *mut Timespec) -> i32;
    }

    const CLOCK_THREAD_CPUTIME_ID: i32 = 3;
    let mut timespec = Timespec {
        tv_sec: 0,
        tv_nsec: 0,
    };
    let result = unsafe { clock_gettime(CLOCK_THREAD_CPUTIME_ID, &mut timespec) };
    if result == 0 && timespec.tv_sec >= 0 && timespec.tv_nsec >= 0 {
        Some(
            (timespec.tv_sec as u128)
                .saturating_mul(1_000_000_000)
                .saturating_add(timespec.tv_nsec as u128)
                .min(u64::MAX as u128) as u64,
        )
    } else {
        None
    }
}

#[cfg(target_os = "windows")]
fn thread_cpu_time_nanos() -> Option<u64> {
    #[repr(C)]
    struct FileTime {
        low: u32,
        high: u32,
    }

    #[link(name = "kernel32")]
    unsafe extern "system" {
        fn GetCurrentThread() -> *mut std::ffi::c_void;
        fn GetThreadTimes(
            thread: *mut std::ffi::c_void,
            creation: *mut FileTime,
            exit: *mut FileTime,
            kernel: *mut FileTime,
            user: *mut FileTime,
        ) -> i32;
    }

    let mut creation = FileTime { low: 0, high: 0 };
    let mut exit = FileTime { low: 0, high: 0 };
    let mut kernel = FileTime { low: 0, high: 0 };
    let mut user = FileTime { low: 0, high: 0 };
    let success = unsafe {
        GetThreadTimes(
            GetCurrentThread(),
            &mut creation,
            &mut exit,
            &mut kernel,
            &mut user,
        )
    };
    if success == 0 {
        return None;
    }

    let ticks = |time: FileTime| (u64::from(time.high) << 32) | u64::from(time.low);
    Some(
        ticks(kernel)
            .saturating_add(ticks(user))
            .saturating_mul(100),
    )
}

#[cfg(not(any(target_os = "android", target_os = "linux", target_os = "windows")))]
fn thread_cpu_time_nanos() -> Option<u64> {
    None
}
