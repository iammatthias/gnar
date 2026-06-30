// GNAR — gnar-board: the full-screen kiosk dashboard.
//
// A single ratatui TUI owning the whole display — host monitoring up
// top, container charts and stack status below. Replaces the previous
// btop + clear-and-reprint shell-board tmux split, which flickered:
// `clear` blanked each pane, docker-stats took ~2s to answer, then
// output painted progressively. Ratatui double-buffers and writes only
// cell diffs, so updates are seamless.
//
//   ┌ CPU 12% · 54°C ──────────────┐┌ MEM 2.6G/27G ────────────────┐
//   │ ▂▃▂▁▂▆▂▁… (history graph)    ││ ▆▆▆▆▆▆▆… (history graph)     │
//   │ cores ▁▃▂▁▅▁▁▂▁▁▁▁▁▁▁▁       ││ swap 137M/4.0G               │
//   └──────────────────────────────┘└──────────────────────────────┘
//   ┌ NET enp3s0 ──────────────────┐┌ DISK / 19% ──────────────────┐
//   │ ↓ 1.2M/s ▁▂▃…  ↑ 300K/s ▁▁▂… ││ ▓▓░░░░ 175G/931G · io r/w    │
//   └──────────────────────────────┘└──────────────────────────────┘
//   ┌ CONTAINERS ──────────────────┐┌ STATUS ──────────────────────┐
//   │ name CPU ▁▂▁ 0.4% MEM ▆▆ NET ││ services · sites · top procs │
//   │ …                            ││ hermes · backup age          │
//   └──────────────────────────────┘└──────────────────────────────┘
//
// Host metrics come straight from /proc + /sys (no subprocesses):
// /proc/stat (total + per-core CPU), /proc/meminfo, /proc/net/dev
// (default-route interface only, so bridge/veth traffic isn't double
// counted), /proc/diskstats (whole-disk sectors), hwmon temperatures.
// Container metrics read the Docker Engine API off the unix socket —
// one-shot /stats per container every 2s; CPU% is computed from
// consecutive samples the same way the CLI does. Containers sharing
// another service's netns (network_mode: service:…) report no network
// stats; their NET column shows "-" — the netns owner carries the
// aggregate. Slow-moving status (systemd units, Caddy sites, top
// processes, Hermes kanban/cron, backup age) refreshes every 30/60s.
//
// Keys: q / Esc / Ctrl-C to quit.

use std::{
    collections::{BTreeMap, HashMap, VecDeque},
    fs,
    io::{Read, Seek, SeekFrom, Write},
    os::unix::net::UnixStream,
    process::Command,
    sync::{Arc, Mutex},
    thread,
    time::{Duration, Instant, SystemTime, UNIX_EPOCH},
};

use ratatui::{
    crossterm::{
        event::{
            self, DisableMouseCapture, EnableMouseCapture, Event, KeyCode, KeyEventKind,
            KeyModifiers, MouseEventKind,
        },
        execute,
    },
    prelude::*,
    widgets::{Block, Paragraph},
};
use serde_json::Value;

const DOCKER_SOCK: &str = "/var/run/docker.sock";
const KEEP: usize = 240; // samples per series (~8 min at 2s cadence)
const STATS_EVERY: Duration = Duration::from_secs(2);
const STATUS_EVERY: Duration = Duration::from_secs(30);
const SERVICES: [&str; 6] = ["docker", "postgresql", "valkey", "fail2ban", "ufw", "gnar-stack"];
const STACK: &str = "/srv/stack";
const TICKS: [char; 8] = ['▁', '▂', '▃', '▄', '▅', '▆', '▇', '█'];

/// What this process renders. `Full` is the whole composite board (the
/// tmux / ssh view); the rest are single panels — one per Mango tile,
/// so the compositor does the layout and each tile only runs the
/// samplers it needs.
#[derive(Clone, Copy, PartialEq)]
enum Mode {
    Full,
    Cpu,
    Mem,
    Net,
    Disk,
    Containers,
    Status,
}

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

#[derive(Default)]
struct Series {
    cpu: VecDeque<f64>, // percent
    mem: VecDeque<f64>, // MiB
    cpu_cur: f64,
    mem_cur: f64,
    net_rate: Option<f64>, // bytes/sec; None = unknown or shared netns
    flag: Option<String>,  // "restarting" / "unhealthy"
    prev: Option<Prev>,
}

/// A Caddy vhost plus its live probe result. `ok: None` = not probed
/// yet; `code: 0` = TCP/TLS-connect check only (preview sites).
#[derive(Clone)]
struct Site {
    host: String,
    kind: String,
    ok: Option<bool>,
    code: u16,
    ms: u64,
}

/// 5-minute traffic for one Caddy host: request total, error buckets, and
/// a request-rate sparkline across the window. The shape makes a bot scan
/// or a sudden spike visible where a lone "N/5m" can't.
#[derive(Default, Clone)]
struct Traffic {
    reqs: u32,
    e404: u32,
    e4xx: u32, // 4xx that isn't 404 — the actionable ones
    e5xx: u32,
    spark: Vec<f64>, // per-bin request counts, oldest→newest
}

/// Host alerts with actionable detail: which units, which crashed procs,
/// and a sample of the actual error messages — not bare counts.
#[derive(Default)]
struct Alerts {
    failed_units: Vec<String>, // unit names
    crashes: Vec<String>,      // "process ×N" per coredumped process this hour
    journal_errs: usize,
    err_sample: Vec<String>, // a couple of recent error messages, clipped
    banned_ips: usize,
    ssh_fails: usize,
}

struct Prev {
    at: Instant,
    cpu_total: u64,
    sys_total: u64,
    net_total: Option<u64>,
}

#[derive(Default)]
struct Host {
    cpu: VecDeque<f64>, // total %
    cpu_cur: f64,
    cores: Vec<f64>,                // per-core %, latest sample
    cores_hist: Vec<VecDeque<f64>>, // per-core history (tile mode)
    temp_c: Option<f64>,
    temp_hist: VecDeque<f64>, // package temp trend (°C)
    mem_used: VecDeque<f64>, // MiB
    mem_cur: f64,
    mem_total: f64,
    mem_avail: f64,
    mem_cache: f64,
    swap_used: f64,
    swap_total: f64,
    iface: String,
    wifi: VecDeque<f64>, // link quality %, only when iface is wireless
    wifi_dbm: f64,
    rx: VecDeque<f64>, // bytes/sec
    tx: VecDeque<f64>,
    rx_cur: f64,
    tx_cur: f64,
    rx_total: u64, // bytes since boot
    tx_total: u64,
    tcp_inuse: u64,
    tcp_tw: u64,
    tcp_hist: VecDeque<f64>, // established+timewait sockets trend
    io_r: VecDeque<f64>, // bytes/sec
    io_w: VecDeque<f64>,
    io_r_cur: f64,
    io_w_cur: f64,
    io_r_total: u64, // bytes since boot
    io_w_total: u64,
    uptime: u64,
    hostname: String,
    load: f64,
    load_hist: VecDeque<f64>,
    ncpu: usize,
    watts: Option<f64>,       // CPU package draw via RAPL (None if unreadable)
    watts_hist: VecDeque<f64>, // package draw trend (W)
    prev_cpu: Option<(Vec<(u64, u64)>, (u64, u64))>, // per-core + total (busy, total)
    prev_net: Option<(Instant, u64, u64)>,
    prev_io: Option<(Instant, u64, u64)>,
    prev_energy: Option<(Instant, u64)>,
}

#[derive(Default)]
struct App {
    host: Host,
    containers: BTreeMap<String, Series>,
    containers_total: usize,
    services: Vec<(String, String)>,
    sites: Vec<Site>,
    procs_cpu: Vec<String>,
    procs_mem: Vec<String>,
    disk_pct: u8,
    disk_detail: String,
    images: usize,
    prune_next: String,
    updates: Option<usize>,
    sec_updates: Option<usize>, // packages with a known CVE fix available (arch-audit); None = unknown
    kanban_lines: Vec<String>,
    cron_lines: Vec<(bool, String, String)>,
    claude_runs: usize,
    claude_24h: usize,
    claude_total: usize,
    backup_age_h: Option<u64>,
    backup_size_mb: u64,
    backup_sizes: Vec<f64>, // archive sizes by age, oldest first (MB)
    traffic: HashMap<String, Traffic>, // per-host 5-minute traffic + sparkline
    failed_units: Vec<String>,
    journal_errs: usize,
    crashes: Vec<String>,
    err_sample: Vec<String>,
    banned_ips: usize,
    ssh_fails: usize,
    reboot_pending: Option<String>,
    last_update_days: Option<u64>,
    ts_ip: String,
    ts_online: usize,
    ts_total: usize,
    nvme_wear: Option<u64>,
    nvme_temp: Option<u64>,
    snapshots: usize,
    docker_err: Option<String>,
    clock: String,
    render_secs: f64, // seconds since the process started — drives list cycling
}

// ---------------------------------------------------------------------------
// Docker Engine API over the unix socket
// ---------------------------------------------------------------------------

fn docker_get(path: &str) -> Result<Value, String> {
    let mut s = UnixStream::connect(DOCKER_SOCK).map_err(|e| format!("docker.sock: {e}"))?;
    s.set_read_timeout(Some(Duration::from_secs(5))).ok();
    s.set_write_timeout(Some(Duration::from_secs(5))).ok();
    write!(
        s,
        "GET {path} HTTP/1.1\r\nHost: docker\r\nAccept: application/json\r\nConnection: close\r\n\r\n"
    )
    .map_err(|e| e.to_string())?;
    let mut buf = Vec::new();
    s.read_to_end(&mut buf).map_err(|e| e.to_string())?;
    let pos = buf
        .windows(4)
        .position(|w| w == b"\r\n\r\n")
        .ok_or("malformed HTTP response")?;
    let headers = String::from_utf8_lossy(&buf[..pos]).to_ascii_lowercase();
    let body = &buf[pos + 4..];
    let body = if headers.contains("transfer-encoding: chunked") {
        dechunk(body)?
    } else {
        body.to_vec()
    };
    serde_json::from_slice(&body).map_err(|e| e.to_string())
}

fn dechunk(data: &[u8]) -> Result<Vec<u8>, String> {
    let mut out = Vec::new();
    let mut i = 0;
    loop {
        let nl = data[i..]
            .windows(2)
            .position(|w| w == b"\r\n")
            .ok_or("bad chunk header")?
            + i;
        let hex: String = String::from_utf8_lossy(&data[i..nl])
            .chars()
            .take_while(|c| c.is_ascii_hexdigit())
            .collect();
        let size = usize::from_str_radix(&hex, 16).map_err(|e| e.to_string())?;
        if size == 0 {
            return Ok(out);
        }
        let start = nl + 2;
        out.extend_from_slice(data.get(start..start + size).ok_or("short chunk")?);
        i = start + size + 2;
    }
}

// ---------------------------------------------------------------------------
// Host sampling (/proc + /sys, no subprocesses)
// ---------------------------------------------------------------------------

fn push(series: &mut VecDeque<f64>, v: f64) {
    series.push_back(v);
    while series.len() > KEEP {
        series.pop_front();
    }
}

/// (busy, total) jiffies per core, plus the aggregate "cpu " line.
fn read_cpu_stat() -> Option<(Vec<(u64, u64)>, (u64, u64))> {
    let s = fs::read_to_string("/proc/stat").ok()?;
    let mut cores = Vec::new();
    let mut agg = None;
    for l in s.lines() {
        if !l.starts_with("cpu") {
            break;
        }
        let f: Vec<u64> = l.split_whitespace().skip(1).filter_map(|v| v.parse().ok()).collect();
        if f.len() < 5 {
            continue;
        }
        let idle = f[3] + f.get(4).copied().unwrap_or(0); // idle + iowait
        let total: u64 = f.iter().sum();
        let entry = (total - idle, total);
        if l.starts_with("cpu ") {
            agg = Some(entry);
        } else {
            cores.push(entry);
        }
    }
    Some((cores, agg?))
}

/// (used, total, available, buff+cache, swap_used, swap_total) in MiB.
fn meminfo() -> Option<(f64, f64, f64, f64, f64, f64)> {
    let s = fs::read_to_string("/proc/meminfo").ok()?;
    let get = |k: &str| {
        s.lines()
            .find(|l| l.starts_with(k))
            .and_then(|l| l.split_whitespace().nth(1))
            .and_then(|v| v.parse::<f64>().ok())
            .map(|kb| kb / 1024.0) // MiB
    };
    let total = get("MemTotal:")?;
    let avail = get("MemAvailable:")?;
    let cache = get("Buffers:").unwrap_or(0.0) + get("Cached:").unwrap_or(0.0);
    let st = get("SwapTotal:").unwrap_or(0.0);
    let sf = get("SwapFree:").unwrap_or(0.0);
    Some((total - avail, total, avail, cache, st - sf, st))
}

/// Interface holding the default route — bridge/veth traffic would
/// double-count container bytes already shown per container.
fn default_iface() -> Option<String> {
    let s = fs::read_to_string("/proc/net/route").ok()?;
    s.lines().skip(1).find_map(|l| {
        let f: Vec<&str> = l.split_whitespace().collect();
        if f.get(1) == Some(&"00000000") {
            f.first().map(|v| v.to_string())
        } else {
            None
        }
    })
}

fn iface_bytes(iface: &str) -> Option<(u64, u64)> {
    let s = fs::read_to_string("/proc/net/dev").ok()?;
    s.lines().find_map(|l| {
        let l = l.trim();
        let rest = l.strip_prefix(&format!("{iface}:"))?;
        let f: Vec<u64> = rest.split_whitespace().filter_map(|v| v.parse().ok()).collect();
        Some((*f.first()?, *f.get(8)?))
    })
}

/// Whole-disk read/written bytes summed across physical disks.
fn disk_io_bytes() -> Option<(u64, u64)> {
    let s = fs::read_to_string("/proc/diskstats").ok()?;
    let mut r = 0u64;
    let mut w = 0u64;
    let mut any = false;
    for l in s.lines() {
        let f: Vec<&str> = l.split_whitespace().collect();
        let name = *f.get(2)?;
        let whole_disk = (name.starts_with("nvme") && !name.contains('p'))
            || (name.starts_with("sd") && name.len() == 3);
        if !whole_disk {
            continue;
        }
        r += f.get(5)?.parse::<u64>().ok()? * 512;
        w += f.get(9)?.parse::<u64>().ok()? * 512;
        any = true;
    }
    any.then_some((r, w))
}

fn cpu_temp() -> Option<f64> {
    let mut best: Option<f64> = None;
    for hw in fs::read_dir("/sys/class/hwmon").ok()?.flatten() {
        if let Ok(entries) = fs::read_dir(hw.path()) {
            for e in entries.flatten() {
                let n = e.file_name();
                let n = n.to_string_lossy().to_string();
                if n.starts_with("temp") && n.ends_with("_input") {
                    if let Some(c) = fs::read_to_string(e.path())
                        .ok()
                        .and_then(|v| v.trim().parse::<f64>().ok())
                        .map(|v| v / 1000.0)
                        .filter(|v| (1.0..150.0).contains(v))
                    {
                        best = Some(best.map_or(c, |b: f64| b.max(c)));
                    }
                }
            }
        }
    }
    best
}

fn sample_host(h: &mut Host) {
    if let Some((cores, agg)) = read_cpu_stat() {
        if let Some((pcores, pagg)) = &h.prev_cpu {
            let pct = |cur: (u64, u64), prev: (u64, u64)| {
                let dt = cur.1.saturating_sub(prev.1);
                if dt == 0 {
                    0.0
                } else {
                    cur.0.saturating_sub(prev.0) as f64 / dt as f64 * 100.0
                }
            };
            h.cpu_cur = pct(agg, *pagg);
            push(&mut h.cpu, h.cpu_cur);
            h.cores = cores
                .iter()
                .zip(pcores.iter())
                .map(|(c, p)| pct(*c, *p))
                .collect();
            if h.cores_hist.len() != h.cores.len() {
                h.cores_hist = vec![VecDeque::new(); h.cores.len()];
            }
            for (i, p) in h.cores.iter().enumerate() {
                push(&mut h.cores_hist[i], *p);
            }
        }
        h.ncpu = cores.len().max(1);
        h.prev_cpu = Some((cores, agg));
    }
    if let Some((used, total, avail, cache, sused, stotal)) = meminfo() {
        h.mem_cur = used;
        h.mem_total = total;
        h.mem_avail = avail;
        h.mem_cache = cache;
        h.swap_used = sused;
        h.swap_total = stotal;
        push(&mut h.mem_used, used);
    }
    let now = Instant::now();
    if h.iface.is_empty() {
        h.iface = default_iface().unwrap_or_else(|| "eth0".into());
    }
    if let Some((rx, tx)) = iface_bytes(&h.iface) {
        if let Some((at, prx, ptx)) = h.prev_net {
            let dt = now.duration_since(at).as_secs_f64();
            if dt > 0.0 {
                h.rx_cur = rx.saturating_sub(prx) as f64 / dt;
                h.tx_cur = tx.saturating_sub(ptx) as f64 / dt;
                push(&mut h.rx, h.rx_cur);
                push(&mut h.tx, h.tx_cur);
            }
        }
        h.rx_total = rx;
        h.tx_total = tx;
        h.prev_net = Some((now, rx, tx));
    }
    if let Ok(s) = fs::read_to_string("/proc/net/sockstat") {
        if let Some(l) = s.lines().find(|l| l.starts_with("TCP:")) {
            let f: Vec<&str> = l.split_whitespace().collect();
            h.tcp_inuse = f.get(2).and_then(|v| v.parse().ok()).unwrap_or(0);
            h.tcp_tw = f.get(6).and_then(|v| v.parse().ok()).unwrap_or(0);
            push(&mut h.tcp_hist, (h.tcp_inuse + h.tcp_tw) as f64);
        }
    }
    // Wireless link quality — this box's uplink is wifi, so the radio
    // is load-bearing telemetry. /proc/net/wireless: link is x/70.
    if h.iface.starts_with("wl") {
        if let Ok(s) = fs::read_to_string("/proc/net/wireless") {
            let prefix = format!("{}:", h.iface);
            if let Some(l) = s.lines().find(|l| l.trim_start().starts_with(&prefix)) {
                let f: Vec<&str> = l.split_whitespace().collect();
                let q = f.get(2).and_then(|v| v.trim_end_matches('.').parse::<f64>().ok()).unwrap_or(0.0);
                h.wifi_dbm = f.get(3).and_then(|v| v.trim_end_matches('.').parse::<f64>().ok()).unwrap_or(0.0);
                push(&mut h.wifi, (q / 70.0 * 100.0).clamp(0.0, 100.0));
            }
        }
    }
    if let Some((r, w)) = disk_io_bytes() {
        if let Some((at, pr, pw)) = h.prev_io {
            let dt = now.duration_since(at).as_secs_f64();
            if dt > 0.0 {
                h.io_r_cur = r.saturating_sub(pr) as f64 / dt;
                h.io_w_cur = w.saturating_sub(pw) as f64 / dt;
                push(&mut h.io_r, h.io_r_cur);
                push(&mut h.io_w, h.io_w_cur);
            }
        }
        h.io_r_total = r;
        h.io_w_total = w;
        h.prev_io = Some((now, r, w));
    }
    if let Ok(s) = fs::read_to_string("/proc/uptime") {
        h.uptime = s.split('.').next().and_then(|v| v.parse().ok()).unwrap_or(0);
    }
    if let Ok(s) = fs::read_to_string("/proc/loadavg") {
        h.load = s.split_whitespace().next().and_then(|v| v.parse().ok()).unwrap_or(0.0);
        push(&mut h.load_hist, h.load);
    }
    if h.hostname.is_empty() {
        h.hostname = fs::read_to_string("/etc/hostname").map(|s| s.trim().to_string()).unwrap_or_default();
    }
    h.temp_c = cpu_temp();
    if let Some(t) = h.temp_c {
        push(&mut h.temp_hist, t);
    }
    // CPU package power via RAPL. Root-only by default; gnar ships a
    // tmpfiles.d rule opening it to 0444 — degrade silently without it.
    if let Some(e) = fs::read_to_string("/sys/class/powercap/intel-rapl:0/energy_uj")
        .ok()
        .and_then(|s| s.trim().parse::<u64>().ok())
    {
        if let Some((at, pe)) = h.prev_energy {
            let dt = now.duration_since(at).as_secs_f64();
            if dt > 0.0 && e > pe {
                // skip wrap-around samples (e < pe)
                let w = (e - pe) as f64 / 1e6 / dt;
                h.watts = Some(w);
                push(&mut h.watts_hist, w);
            }
        }
        h.prev_energy = Some((now, e));
    }
}

// ---------------------------------------------------------------------------
// Container + status sampling
// ---------------------------------------------------------------------------

fn host_loop(app: Arc<Mutex<App>>) {
    loop {
        let started = Instant::now();
        sample_host(&mut app.lock().unwrap().host);
        thread::sleep(STATS_EVERY.saturating_sub(started.elapsed()));
    }
}

fn docker_loop(app: Arc<Mutex<App>>) {
    loop {
        let started = Instant::now();
        match sample_containers(&app) {
            Ok(()) => app.lock().unwrap().docker_err = None,
            Err(e) => app.lock().unwrap().docker_err = Some(e),
        }
        thread::sleep(STATS_EVERY.saturating_sub(started.elapsed()));
    }
}

fn sample_containers(app: &Arc<Mutex<App>>) -> Result<(), String> {
    let list = docker_get("/containers/json")?;
    let list = list.as_array().ok_or("unexpected /containers/json shape")?;
    let mut seen = Vec::with_capacity(list.len());

    for c in list {
        let id = c["Id"].as_str().unwrap_or_default();
        let name = c["Names"][0]
            .as_str()
            .unwrap_or("?")
            .trim_start_matches('/')
            .to_string();
        let state = c["State"].as_str().unwrap_or("");
        let status = c["Status"].as_str().unwrap_or("");
        let flag = if state == "restarting" {
            Some("restarting".to_string())
        } else if status.contains("unhealthy") {
            Some("unhealthy".to_string())
        } else {
            None
        };
        let stats = match docker_get(&format!("/containers/{id}/stats?stream=false&one-shot=true")) {
            Ok(v) => v,
            Err(_) => continue, // container racing us to exit
        };

        let cpu_total = stats["cpu_stats"]["cpu_usage"]["total_usage"].as_u64().unwrap_or(0);
        let sys_total = stats["cpu_stats"]["system_cpu_usage"].as_u64().unwrap_or(0);
        let online = stats["cpu_stats"]["online_cpus"].as_u64().unwrap_or(0).max(1) as f64;
        let usage = stats["memory_stats"]["usage"].as_u64().unwrap_or(0);
        // The CLI subtracts page cache; the key differs across cgroup v1/v2.
        let cache = stats["memory_stats"]["stats"]["inactive_file"]
            .as_u64()
            .or_else(|| stats["memory_stats"]["stats"]["total_inactive_file"].as_u64())
            .unwrap_or(0);
        let mem_mib = usage.saturating_sub(cache) as f64 / 1048576.0;
        let net_total = stats["networks"].as_object().map(|nets| {
            nets.values()
                .map(|n| n["rx_bytes"].as_u64().unwrap_or(0) + n["tx_bytes"].as_u64().unwrap_or(0))
                .sum::<u64>()
        });

        let now = Instant::now();
        let mut a = app.lock().unwrap();
        let s = a.containers.entry(name.clone()).or_default();
        if let Some(p) = &s.prev {
            let dsys = sys_total.saturating_sub(p.sys_total);
            if dsys > 0 {
                let dcpu = cpu_total.saturating_sub(p.cpu_total);
                s.cpu_cur = dcpu as f64 / dsys as f64 * online * 100.0;
                push(&mut s.cpu, s.cpu_cur);
            }
            let dt = now.duration_since(p.at).as_secs_f64();
            s.net_rate = match (net_total, p.net_total) {
                (Some(cur), Some(prev)) if dt > 0.0 => Some(cur.saturating_sub(prev) as f64 / dt),
                _ => None,
            };
        }
        s.mem_cur = mem_mib;
        push(&mut s.mem, mem_mib);
        s.flag = flag;
        s.prev = Some(Prev { at: now, cpu_total, sys_total, net_total });
        drop(a);
        seen.push(name);
    }

    app.lock().unwrap().containers.retain(|k, _| seen.contains(k));
    Ok(())
}

fn status_loop(app: Arc<Mutex<App>>, mode: Mode) {
    let with_hermes = matches!(mode, Mode::Full | Mode::Status);
    // Which hourly samples this panel actually renders. Each kiosk tile is
    // its own process, so an ungated sampler runs once per tile — six
    // concurrent `checkupdates` racing the temp sync DB is what produced a
    // false "up to date". Gate each heavy sampler to the panel that shows it.
    // updates/security/last-update render in the OPS (Status) tile's
    // SECURITY section, so only it runs checkupdates — keeping the one
    // network sync off the critical path and out of a multi-tile race.
    let shows_updates = matches!(mode, Mode::Full | Mode::Status);
    let shows_disk = matches!(mode, Mode::Full | Mode::Disk);
    let shows_claude = matches!(mode, Mode::Full | Mode::Status);
    let mut tick: u64 = 0;
    let mut log_offset: u64 = 0;
    let mut traffic_window: VecDeque<(f64, String, u16)> = VecDeque::new();
    loop {
        let started = Instant::now();

        let services: Vec<(String, String)> = SERVICES
            .iter()
            .map(|s| {
                let state = Command::new("systemctl")
                    .args(["is-active", s])
                    .output()
                    .ok()
                    .map(|o| String::from_utf8_lossy(&o.stdout).trim().to_string())
                    .filter(|v| !v.is_empty())
                    .unwrap_or_else(|| "unknown".into());
                (s.to_string(), state)
            })
            .collect();

        let mut sites = caddy_sites();
        probe_sites(&mut sites);
        let backup = backup_info();
        let (disk_pct, disk_detail) = disk_usage();
        let procs_cpu = top_procs("-pcpu", 10);
        let procs_mem = top_procs("-pmem", 8);
        let prune_next = prune_timer_next();
        let images = docker_get("/images/json")
            .ok()
            .and_then(|v| v.as_array().map(|a| a.len()))
            .unwrap_or(0);
        let containers_total = docker_get("/containers/json?all=1")
            .ok()
            .and_then(|v| v.as_array().map(|a| a.len()))
            .unwrap_or(0);

        let traffic = sample_traffic(&mut log_offset, &mut traffic_window);
        let alerts = sample_alerts();
        let tailscale = sample_tailscale();
        let reboot_pending = reboot_pending();

        // Slow-moving / heavier samples — hourly. checkupdates does a
        // network sync, smartctl wakes the drive, pacman.log is big.
        let hourly = if tick % 120 == 0 {
            Some((
                if shows_updates { pending_updates() } else { None },
                if shows_updates { security_updates() } else { None },
                if shows_disk { nvme_health() } else { (None, None) },
                if shows_disk { snapshot_count() } else { 0 },
                if shows_updates { last_update_days() } else { None },
                if shows_claude { claude_usage() } else { (0, 0) },
            ))
        } else {
            None
        };

        // Hermes detail is docker-exec subprocesses — every other cycle,
        // and only for the panels that display it.
        let hermes = if with_hermes && tick % 2 == 0 {
            Some((
                kanban_tasks(&hermes_raw("kanban")),
                cron_jobs(&hermes_raw("cron")),
                claude_runs(),
            ))
        } else {
            None
        };

        {
            let mut a = app.lock().unwrap();
            a.services = services;
            a.sites = sites;
            a.procs_cpu = procs_cpu;
            a.procs_mem = procs_mem;
            if let Some((age, size, sizes)) = &backup {
                a.backup_age_h = Some(*age);
                a.backup_size_mb = *size;
                a.backup_sizes = sizes.clone();
            } else {
                a.backup_age_h = None;
            }
            a.disk_pct = disk_pct;
            a.disk_detail = disk_detail;
            a.images = images;
            a.containers_total = containers_total;
            a.prune_next = prune_next;
            a.traffic = traffic;
            a.failed_units = alerts.failed_units;
            a.journal_errs = alerts.journal_errs;
            a.crashes = alerts.crashes;
            a.err_sample = alerts.err_sample;
            a.banned_ips = alerts.banned_ips;
            a.ssh_fails = alerts.ssh_fails;
            a.reboot_pending = reboot_pending;
            if let Some((ip, online, total)) = tailscale {
                a.ts_ip = ip;
                a.ts_online = online;
                a.ts_total = total;
            }
            if let Some((updates, sec_updates, (wear, temp), snaps, upd_days, (c24, ctotal))) = hourly {
                a.updates = updates;
                a.sec_updates = sec_updates;
                a.nvme_wear = wear;
                a.nvme_temp = temp;
                a.snapshots = snaps;
                a.last_update_days = upd_days;
                a.claude_24h = c24;
                a.claude_total = ctotal;
            }
            if let Some((k, c, r)) = hermes {
                a.kanban_lines = k;
                a.cron_lines = c;
                a.claude_runs = r;
            }
        }
        tick += 1;
        thread::sleep(STATUS_EVERY.saturating_sub(started.elapsed()));
    }
}

/// Wall-clock for the header — cheap thread, minute resolution.
fn clock_loop(app: Arc<Mutex<App>>) {
    loop {
        let out = Command::new("date")
            .arg("+%a %b %d  %H:%M")
            .output()
            .ok()
            .map(|o| String::from_utf8_lossy(&o.stdout).trim().to_string())
            .unwrap_or_default();
        app.lock().unwrap().clock = out;
        thread::sleep(Duration::from_secs(10));
    }
}

/// Live-probe each Caddy vhost through the tailscale container's bridge
/// IP (caddy shares that netns, so its listeners are reachable there
/// from the host). private → :80, public → :8080, previews are
/// TLS-only so they get a TCP-connect check on :443.
fn probe_sites(sites: &mut [Site]) {
    let ip = match docker_get("/containers/gnar-tailscale/json").ok().and_then(|v| {
        let ns = &v["NetworkSettings"];
        ns["IPAddress"]
            .as_str()
            .filter(|s| !s.is_empty())
            .map(String::from)
            .or_else(|| {
                ns["Networks"]
                    .as_object()
                    .and_then(|o| o.values().next())
                    .and_then(|n| n["IPAddress"].as_str())
                    .filter(|s| !s.is_empty())
                    .map(String::from)
            })
    }) {
        Some(ip) => ip,
        None => return,
    };
    for site in sites.iter_mut() {
        let res = match site.kind.as_str() {
            "private" => http_probe(&ip, 80, &site.host),
            "public" => http_probe(&ip, 8080, &site.host),
            _ => tcp_probe(&ip, 443).map(|ms| (0u16, ms)),
        };
        match res {
            Some((code, ms)) => {
                site.code = code;
                site.ms = ms;
                site.ok = Some(code == 0 || (200..400).contains(&code));
            }
            None => site.ok = Some(false),
        }
    }
}

fn http_probe(ip: &str, port: u16, host: &str) -> Option<(u16, u64)> {
    use std::net::{SocketAddr, TcpStream};
    let addr: SocketAddr = format!("{ip}:{port}").parse().ok()?;
    let start = Instant::now();
    let mut s = TcpStream::connect_timeout(&addr, Duration::from_secs(3)).ok()?;
    s.set_read_timeout(Some(Duration::from_secs(3))).ok();
    s.set_write_timeout(Some(Duration::from_secs(3))).ok();
    write!(
        s,
        "GET / HTTP/1.1\r\nHost: {host}\r\nUser-Agent: gnar-board\r\nConnection: close\r\n\r\n"
    )
    .ok()?;
    let mut buf = [0u8; 32];
    let n = s.read(&mut buf).ok()?;
    let code = String::from_utf8_lossy(&buf[..n]).split_whitespace().nth(1)?.parse().ok()?;
    Some((code, start.elapsed().as_millis() as u64))
}

fn tcp_probe(ip: &str, port: u16) -> Option<u64> {
    use std::net::{SocketAddr, TcpStream};
    let addr: SocketAddr = format!("{ip}:{port}").parse().ok()?;
    let start = Instant::now();
    TcpStream::connect_timeout(&addr, Duration::from_secs(3)).ok()?;
    Some(start.elapsed().as_millis() as u64)
}

/// Pending pacman updates (pacman-contrib's checkupdates; syncs to a
/// temp DB, never touches the real one). On a rolling release this is
/// routinely dozens — informational, not an alarm; the security count
/// below is the signal that actually warrants attention.
///
/// `None` means "couldn't tell", not "zero": checkupdates exits 0 with a
/// list, 2 for none-pending, and 1 on failure (network, or a temp-db
/// lock when several callers sync at once). Treating a failed run as 0
/// would paint a false "up to date", so only 0/2 yield a count.
fn pending_updates() -> Option<usize> {
    let out = Command::new("checkupdates").output().ok()?;
    match out.status.code() {
        Some(0) | Some(2) => Some(
            String::from_utf8_lossy(&out.stdout)
                .lines()
                .filter(|l| !l.trim().is_empty())
                .count(),
        ),
        _ => None,
    }
}

/// Installed packages with a known security advisory whose fix is
/// already available to install (Arch Security Tracker, via arch-audit
/// `-u`). `None` when arch-audit isn't installed — absence of signal,
/// not a clean bill of health, so the UI shows nothing rather than "0".
/// This is what separates "stay current for security" from the much
/// noisier "stay current for everything".
fn security_updates() -> Option<usize> {
    let out = Command::new("arch-audit").args(["-uq"]).output().ok()?;
    Some(
        String::from_utf8_lossy(&out.stdout)
            .lines()
            .filter(|l| !l.trim().is_empty())
            .count(),
    )
}

fn strip_ansi(s: &str) -> String {
    let mut out = String::new();
    let mut chars = s.chars();
    while let Some(c) = chars.next() {
        if c == '\x1b' {
            for d in chars.by_ref() {
                if d.is_ascii_alphabetic() {
                    break;
                }
            }
        } else {
            out.push(c);
        }
    }
    out
}

fn hermes_raw(what: &str) -> Vec<String> {
    Command::new("timeout")
        .args(["10", "docker", "exec", "gnar-hermes-gateway", "hermes", what, "list"])
        .output()
        .ok()
        .map(|o| {
            String::from_utf8_lossy(&o.stdout)
                .lines()
                .map(|l| strip_ansi(l).trim_end().to_string())
                .collect()
        })
        .unwrap_or_default()
}

/// Task rows out of `hermes kanban list`, minus box-drawing and
/// "(no matching tasks)" placeholders.
fn kanban_tasks(raw: &[String]) -> Vec<String> {
    raw.iter()
        .map(|l| l.trim())
        .filter(|l| {
            !l.is_empty() && !l.starts_with('(') && !l.chars().next().is_some_and(|c| "─┌└│┐┘├┤═╔╚║".contains(c))
        })
        .map(String::from)
        .take(8)
        .collect()
}

/// (active, name, schedule) per job from `hermes cron list`'s
/// multi-line output (id [active] / Name: / Schedule: / …).
fn cron_jobs(raw: &[String]) -> Vec<(bool, String, String)> {
    let mut jobs = Vec::new();
    let mut active = false;
    let mut name = String::new();
    for l in raw {
        let t = l.trim();
        if t.contains("[active]") {
            active = true;
        } else if t.contains("[paused]") || t.contains("[inactive]") {
            active = false;
        }
        if let Some(v) = t.strip_prefix("Name:") {
            name = v.trim().to_string();
        } else if let Some(v) = t.strip_prefix("Schedule:") {
            jobs.push((active, name.clone(), v.trim().to_string()));
            active = false;
        }
    }
    jobs
}

/// Count claude processes inside the gateway container — a live
/// delegated coding run shows up here.
fn claude_runs() -> usize {
    docker_get("/containers/gnar-hermes-gateway/top")
        .ok()
        .and_then(|v| {
            v["Processes"].as_array().map(|ps| {
                ps.iter()
                    .filter(|p| {
                        p.as_array().is_some_and(|f| {
                            f.iter().any(|x| x.as_str().is_some_and(|s| s.contains("claude")))
                        })
                    })
                    .count()
            })
        })
        .unwrap_or(0)
}

fn top_procs(sort: &str, n: usize) -> Vec<String> {
    Command::new("ps")
        .args(["-eo", "pcpu,pmem,comm", &format!("--sort={sort}"), "--no-headers"])
        .output()
        .ok()
        .map(|o| {
            String::from_utf8_lossy(&o.stdout)
                .lines()
                .take(n)
                .map(|l| l.trim().to_string())
                .collect()
        })
        .unwrap_or_default()
}

const ACCESS_LOG: &str = "/srv/stack/data/caddy/data/access/access.log";

const TRAFFIC_BINS: usize = 8; // sparkline columns across the 5-min window

/// Incrementally tail caddy's shared JSON access log and aggregate a
/// 5-minute window of per-host request counts, 404 / other-4xx / 5xx
/// tallies, and a request-rate sparkline. Only complete lines are
/// consumed; rotation resets the offset.
fn sample_traffic(
    offset: &mut u64,
    window: &mut VecDeque<(f64, String, u16)>,
) -> HashMap<String, Traffic> {
    // Age and bucket by the log's own `ts` (unix secs), not read time —
    // otherwise a respawn dumps the whole backlog tail into "now", spiking
    // every count and sparkline for the first five minutes.
    let now = SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_secs_f64()).unwrap_or(0.0);
    if let Ok(mut f) = fs::File::open(ACCESS_LOG) {
        let len = f.metadata().map(|m| m.len()).unwrap_or(0);
        if len < *offset {
            *offset = 0; // rotated
        }
        // First pass: start near the tail, not from history.
        if *offset == 0 && len > 524_288 {
            *offset = len - 524_288;
        }
        if len > *offset && f.seek(SeekFrom::Start(*offset)).is_ok() {
            let mut buf = Vec::with_capacity((len - *offset) as usize);
            if (&mut f).take(len - *offset).read_to_end(&mut buf).is_ok() {
                // Consume only up to the last complete line.
                if let Some(last_nl) = buf.iter().rposition(|b| *b == b'\n') {
                    for l in String::from_utf8_lossy(&buf[..=last_nl]).lines() {
                        let Ok(v) = serde_json::from_str::<Value>(l) else { continue };
                        let host = v["request"]["host"]
                            .as_str()
                            .unwrap_or("")
                            .split(':')
                            .next()
                            .unwrap_or("")
                            .to_string();
                        if host.is_empty() {
                            continue;
                        }
                        let ts = v["ts"].as_f64().unwrap_or(now);
                        let status = v["status"].as_u64().unwrap_or(0) as u16;
                        window.push_back((ts, host, status));
                    }
                    *offset += last_nl as u64 + 1;
                }
            }
        }
    }
    while window.front().is_some_and(|(t, ..)| now - t > 300.0) {
        window.pop_front();
    }
    // 404 is bucketed apart from the rest of the 4xx range: on a public
    // host it's almost entirely bot/scanner/missing-asset noise, whereas
    // 400/401/403/429 usually mean something a human should look at.
    let mut map: HashMap<String, Traffic> = HashMap::new();
    for (t, host, status) in window.iter() {
        let e = map.entry(host.clone()).or_default();
        if e.spark.is_empty() {
            e.spark = vec![0.0; TRAFFIC_BINS];
        }
        e.reqs += 1;
        match *status {
            404 => e.e404 += 1,
            400..=499 => e.e4xx += 1,
            s if s >= 500 => e.e5xx += 1,
            _ => {}
        }
        // Oldest (≈300s ago) → bin 0, newest → last bin.
        let age = (now - t).clamp(0.0, 300.0);
        let bin = (((300.0 - age) / 300.0) * (TRAFFIC_BINS as f64 - 1.0)).round() as usize;
        e.spark[bin.min(TRAFFIC_BINS - 1)] += 1.0;
    }
    map
}

fn sudo_lines(args: &[&str]) -> Vec<String> {
    Command::new("sudo")
        .arg("-n")
        .args(args)
        .output()
        .ok()
        .map(|o| {
            String::from_utf8_lossy(&o.stdout)
                .lines()
                .map(|l| l.trim_end().to_string())
                .filter(|l| !l.is_empty())
                .collect()
        })
        .unwrap_or_default()
}

/// Host alerts, with enough detail to act on — not just counts. All via
/// passwordless sudo (gnar grants it by design). Coredumps log entire
/// stack traces at priority err, which would read as hundreds of "errors"
/// per crash — so crashes are their own signal (grouped by process) and
/// the trace spam is excluded from the error count + sample.
fn sample_alerts() -> Alerts {
    let failed_units: Vec<String> = sudo_lines(&["systemctl", "--failed", "--plain", "--no-legend"])
        .iter()
        .filter_map(|l| l.split_whitespace().next().map(String::from))
        .collect();
    let p3 = sudo_lines(&["journalctl", "-p", "3", "--since", "-1 hour", "-q", "--no-pager", "-o", "cat", "-n", "1000"]);
    // Group coredumps by the "(process)" field so it reads "mango ×3".
    let mut crash_counts: BTreeMap<String, usize> = BTreeMap::new();
    for l in p3.iter().filter(|l| l.contains(" dumped core")) {
        let proc = l
            .split('(')
            .nth(1)
            .and_then(|s| s.split(')').next())
            .filter(|s| !s.is_empty())
            .unwrap_or("?");
        *crash_counts.entry(proc.to_string()).or_default() += 1;
    }
    let crashes: Vec<String> = crash_counts
        .into_iter()
        .map(|(p, n)| if n > 1 { format!("{p} ×{n}") } else { p })
        .collect();
    // Exclude every line of a systemd-coredump dump — crashes are their own
    // signal, so the trace, module list, and the trailing "ELF object binary
    // architecture: …" epilogue must not read as separate "journal errors".
    let err_lines: Vec<&String> = p3
        .iter()
        .filter(|l| {
            let t = l.trim_start();
            !(t.starts_with('#')
                || t.starts_with("Module ")
                || t.starts_with("Found module")
                || t.starts_with("Stack trace of")
                || t.starts_with("ELF object")
                || t.starts_with("Stored in")
                || t.contains(" dumped core"))
        })
        .collect();
    let journal_errs = err_lines.len();
    // The two most recent distinct messages, clipped — what's actually wrong.
    let mut err_sample: Vec<String> = Vec::new();
    for l in err_lines.iter().rev() {
        let s: String = l.trim().chars().take(64).collect();
        if !s.is_empty() && !err_sample.contains(&s) {
            err_sample.push(s);
        }
        if err_sample.len() >= 2 {
            break;
        }
    }
    let banned_ips = sudo_lines(&["fail2ban-client", "status", "sshd"])
        .iter()
        .find_map(|l| {
            l.contains("Currently banned:")
                .then(|| l.split_whitespace().last()?.parse().ok())
                .flatten()
        })
        .unwrap_or(0);
    let ssh_fails = sudo_lines(&["journalctl", "-u", "sshd", "--since", "-1 hour", "-q", "--no-pager", "-o", "cat", "-n", "500"])
        .iter()
        .filter(|l| l.contains("Failed password") || l.contains("Invalid user"))
        .count();
    Alerts { failed_units, crashes, journal_errs, err_sample, banned_ips, ssh_fails }
}

/// (tailnet IP, peers online, peers total) from the tailscale container.
fn sample_tailscale() -> Option<(String, usize, usize)> {
    let out = Command::new("timeout")
        .args(["10", "docker", "exec", "gnar-tailscale", "tailscale", "status", "--json"])
        .output()
        .ok()?;
    let v: Value = serde_json::from_slice(&out.stdout).ok()?;
    let ip = v["Self"]["TailscaleIPs"][0].as_str().unwrap_or("").to_string();
    let (online, total) = v["Peer"]
        .as_object()
        .map(|p| {
            (
                p.values().filter(|x| x["Online"].as_bool().unwrap_or(false)).count(),
                p.len(),
            )
        })
        .unwrap_or((0, 0));
    Some((ip, online, total))
}

/// The running kernel's modules vanish from /usr/lib/modules when
/// pacman installs a new kernel — the classic Arch "reboot pending"
/// signal. Returns the newest installed version when they differ.
fn reboot_pending() -> Option<String> {
    let running = fs::read_to_string("/proc/sys/kernel/osrelease").ok()?.trim().to_string();
    let dirs: Vec<String> = fs::read_dir("/usr/lib/modules")
        .ok()?
        .flatten()
        .filter_map(|e| e.file_name().to_str().map(String::from))
        .collect();
    if dirs.iter().any(|d| *d == running) {
        None
    } else {
        dirs.into_iter().max()
    }
}

/// (NVMe wear %, NVMe temperature °C) via smartctl.
fn nvme_health() -> (Option<u64>, Option<u64>) {
    Command::new("sudo")
        .args(["-n", "smartctl", "-j", "-A", "/dev/nvme0"])
        .output()
        .ok()
        .and_then(|o| serde_json::from_slice::<Value>(&o.stdout).ok())
        .map(|v| {
            let log = &v["nvme_smart_health_information_log"];
            (log["percentage_used"].as_u64(), log["temperature"].as_u64())
        })
        .unwrap_or((None, None))
}

fn snapshot_count() -> usize {
    sudo_lines(&["ls", "/.snapshots"])
        .iter()
        .filter(|l| l.chars().all(|c| c.is_ascii_digit()))
        .count()
}

fn days_from_civil(y: i64, m: i64, d: i64) -> i64 {
    let y = if m <= 2 { y - 1 } else { y };
    let era = if y >= 0 { y } else { y - 399 } / 400;
    let yoe = y - era * 400;
    let doy = (153 * (if m > 2 { m - 3 } else { m + 9 }) + 2) / 5 + d - 1;
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    era * 146097 + doe - 719468
}

/// Days since the last `pacman -Syu` per /var/log/pacman.log
/// (timestamps are UTC, e.g. [2026-06-11T00:08:11+0000]).
fn last_update_days() -> Option<u64> {
    let s = fs::read_to_string("/var/log/pacman.log").ok()?;
    let line = s.lines().rev().find(|l| l.contains("starting full system upgrade"))?;
    let ts = line.split(']').next()?.trim_start_matches('[');
    let (date, time) = ts.split_once('T')?;
    let mut dp = date.split('-');
    let (y, m, d): (i64, i64, i64) = (
        dp.next()?.parse().ok()?,
        dp.next()?.parse().ok()?,
        dp.next()?.parse().ok()?,
    );
    let mut tp = time.get(..8)?.split(':');
    let (hh, mm, ss): (i64, i64, i64) = (
        tp.next()?.parse().ok()?,
        tp.next()?.parse().ok()?,
        tp.next()?.parse().ok()?,
    );
    let then = days_from_civil(y, m, d) * 86400 + hh * 3600 + mm * 60 + ss;
    let now = SystemTime::now().duration_since(UNIX_EPOCH).ok()?.as_secs() as i64;
    Some(((now - then).max(0) / 86400) as u64)
}

/// (claude transcripts touched in 24h, total transcripts) — the
/// delegated-coding workload, from the persisted ~/.claude state.
fn claude_usage() -> (usize, usize) {
    let base = format!("{STACK}/data/claude/projects");
    let recent = sudo_lines(&["find", &base, "-name", "*.jsonl", "-mtime", "-1"]).len();
    let total = sudo_lines(&["find", &base, "-name", "*.jsonl"]).len();
    (recent, total)
}

/// "Mon 2026-06-15" from the prune timer's next elapse, or "".
fn prune_timer_next() -> String {
    Command::new("systemctl")
        .args(["show", "gnar-docker-prune.timer", "-p", "NextElapseUSecRealtime", "--value"])
        .output()
        .ok()
        .map(|o| {
            String::from_utf8_lossy(&o.stdout)
                .split_whitespace()
                .take(2)
                .collect::<Vec<_>>()
                .join(" ")
        })
        .unwrap_or_default()
}

fn caddy_sites() -> Vec<Site> {
    let hostish = |h: &str| !h.is_empty() && h.chars().all(|c| c.is_ascii_alphanumeric() || c == '.' || c == '-');
    let site = |host: &str, kind: &str| Site {
        host: host.to_string(),
        kind: kind.to_string(),
        ok: None,
        code: 0,
        ms: 0,
    };
    let mut out = Vec::new();
    if let Ok(s) = fs::read_to_string(format!("{STACK}/Caddyfile")) {
        for l in s.lines() {
            let l = l.trim_end();
            if let Some(h) = l.strip_suffix(":80 {") {
                if h.ends_with(".local") && hostish(h) {
                    out.push(site(h, "private"));
                }
            } else if let Some(h) = l.strip_prefix("http://").and_then(|r| r.strip_suffix(":8080 {")) {
                if hostish(h) {
                    out.push(site(h, "public"));
                }
            }
        }
    }
    let apex = fs::read_to_string(format!("{STACK}/.env"))
        .ok()
        .and_then(|s| {
            s.lines()
                .find_map(|l| l.strip_prefix("PREVIEW_APEX=").map(|v| v.trim_matches(['"', '\'', ' ']).to_string()))
        })
        .filter(|v| !v.is_empty())
        .unwrap_or_else(|| "previews.example.com".into());
    if let Ok(dir) = fs::read_dir(format!("{STACK}/preview-handles")) {
        let mut previews: Vec<String> = dir
            .flatten()
            .filter_map(|e| {
                e.file_name()
                    .to_str()?
                    .strip_suffix(".caddy")
                    .map(|stem| format!("{stem}.{apex}"))
            })
            .collect();
        previews.sort();
        out.extend(previews.into_iter().map(|h| site(&h, "preview")));
    }
    out
}

/// (age h, size MB of newest, all sizes oldest→newest in MB) for the
/// hermes backup archives — the size trend catches "backup suddenly
/// doubled/shrank", which age alone misses.
fn backup_info() -> Option<(u64, u64, Vec<f64>)> {
    let mut archives: Vec<(SystemTime, u64)> = fs::read_dir(format!("{STACK}/data/backups"))
        .ok()?
        .flatten()
        .filter(|e| {
            let n = e.file_name();
            let n = n.to_string_lossy();
            n.starts_with("hermes-backup-") && n.ends_with(".zip")
        })
        .filter_map(|e| {
            let m = e.metadata().ok()?;
            Some((m.modified().ok()?, m.len()))
        })
        .collect();
    archives.sort_by_key(|(t, _)| *t);
    let (mtime, size) = *archives.last()?;
    let age = SystemTime::now().duration_since(mtime).ok()?.as_secs() / 3600;
    let sizes = archives.iter().map(|(_, s)| *s as f64 / 1e6).collect();
    Some((age, size / 1_000_000, sizes))
}

fn disk_usage() -> (u8, String) {
    Command::new("df")
        .args(["-h", "/"])
        .output()
        .ok()
        .and_then(|o| {
            let out = String::from_utf8_lossy(&o.stdout).to_string();
            let f: Vec<&str> = out.lines().nth(1)?.split_whitespace().collect();
            let pct = f.get(4)?.trim_end_matches('%').parse().ok()?;
            Some((pct, format!("{}/{}", f.get(2)?, f.get(1)?)))
        })
        .unwrap_or((0, "?".into()))
}

// ---------------------------------------------------------------------------
// Rendering
// ---------------------------------------------------------------------------

// Tokyo Night-ish truecolor palette. foot (the kiosk terminal) speaks
// 24-bit color; on lesser terminals crossterm degrades to nearest-match.
const C_FG: Color = Color::Rgb(0xc0, 0xca, 0xf5);
const C_DIM: Color = Color::Rgb(0x56, 0x5f, 0x89);
const C_BORDER: Color = Color::Rgb(0x3b, 0x42, 0x61);
const C_BG_ALT: Color = Color::Rgb(0x1a, 0x1b, 0x26);
const C_CYAN: Color = Color::Rgb(0x7d, 0xcf, 0xff);
const C_BLUE: Color = Color::Rgb(0x7a, 0xa2, 0xf7);
const C_MAGENTA: Color = Color::Rgb(0xbb, 0x9a, 0xf7);
const C_GREEN: Color = Color::Rgb(0x9e, 0xce, 0x6a);
const C_YELLOW: Color = Color::Rgb(0xe0, 0xaf, 0x68);
const C_RED: Color = Color::Rgb(0xf7, 0x76, 0x8e);

const GREEN_RGB: (u8, u8, u8) = (0x9e, 0xce, 0x6a);
const YELLOW_RGB: (u8, u8, u8) = (0xe0, 0xaf, 0x68);
const RED_RGB: (u8, u8, u8) = (0xf7, 0x76, 0x8e);
const BLUE_RGB: (u8, u8, u8) = (0x7a, 0xa2, 0xf7);
const MAGENTA_RGB: (u8, u8, u8) = (0xbb, 0x9a, 0xf7);
const CYAN_RGB: (u8, u8, u8) = (0x7d, 0xcf, 0xff);

fn lerp(a: (u8, u8, u8), b: (u8, u8, u8), t: f64) -> Color {
    let t = t.clamp(0.0, 1.0);
    let c = |x: u8, y: u8| (x as f64 + (y as f64 - x as f64) * t).round() as u8;
    Color::Rgb(c(a.0, b.0), c(a.1, b.1), c(a.2, b.2))
}

/// green → amber → rose as t goes 0 → 1. The signature gradient for
/// anything that means "how loaded is this".
fn heat(t: f64) -> Color {
    let t = t.clamp(0.0, 1.0);
    if t < 0.5 {
        lerp(GREEN_RGB, YELLOW_RGB, t * 2.0)
    } else {
        lerp(YELLOW_RGB, RED_RGB, (t - 0.5) * 2.0)
    }
}

/// Intensity tint of a hue: muted slate at t=0, full color at t=1.
/// Used for throughput graphs, where "hot" means "busy" not "bad".
fn tint(hue: (u8, u8, u8)) -> impl Fn(f64) -> Color {
    move |t: f64| lerp((0x2f, 0x33, 0x4d), hue, 0.35 + 0.65 * t.clamp(0.0, 1.0))
}

fn dim() -> Style {
    Style::new().fg(C_DIM)
}

fn accent(c: Color) -> Style {
    Style::new().fg(c).add_modifier(Modifier::BOLD)
}

fn section(title: Vec<Span<'static>>) -> Block<'static> {
    Block::bordered()
        .border_set(ratatui::symbols::border::ROUNDED)
        .border_style(Style::new().fg(C_BORDER))
        .title(Line::from(title))
}

/// Panel chrome, returning the content Rect. On the kiosk, Mango already
/// draws a 2px border + gap around every tile, so a second ratatui box in
/// the same color is pure redundant ink (and costs two rows + two cols) —
/// there we render only a bold header row and hand back the rest. The
/// ssh/tmux `full` board has no compositor, so it keeps the box as its
/// only separation between panels. `right` is an optional right-aligned
/// header (clock, etc.).
fn panel(
    frame: &mut Frame,
    area: Rect,
    bordered: bool,
    title: Vec<Span<'static>>,
    right: Option<Line<'static>>,
) -> Rect {
    if bordered {
        let mut block = section(title);
        if let Some(r) = right {
            block = block.title(r.right_aligned());
        }
        let inner = block.inner(area);
        frame.render_widget(block, area);
        inner
    } else {
        let hdr = Rect { height: 1, ..area };
        frame.render_widget(Paragraph::new(Line::from(title)), hdr);
        if let Some(r) = right {
            frame.render_widget(Paragraph::new(r).right_aligned(), hdr);
        }
        Rect { y: area.y + 1, height: area.height.saturating_sub(1), ..area }
    }
}

/// Single-row sparkline string — the per-container mini charts.
fn spark(vals: &VecDeque<f64>, width: usize, floor: f64, head: f64) -> String {
    let take = vals.len().min(width);
    let slice: Vec<f64> = vals.iter().skip(vals.len() - take).copied().collect();
    let mut max = floor;
    for v in &slice {
        if *v > max {
            max = *v;
        }
    }
    max = (max * head).max(f64::MIN_POSITIVE);
    let mut s = " ".repeat(width - take);
    for v in slice {
        let idx = ((v / max * 7.0).round() as usize).min(7);
        s.push(TICKS[idx]);
    }
    s
}

/// Sparkline scaled to a FIXED absolute ceiling, not the data's own max.
/// For level metrics (temp, watts, sockets) this is what makes a steady
/// reading render as a calm low line instead of an alarming full-height
/// block — auto-scaling a flat signal always pins it to the top.
fn spark_abs(vals: &VecDeque<f64>, width: usize, max: f64) -> String {
    let take = vals.len().min(width);
    let max = max.max(f64::MIN_POSITIVE);
    let mut s = " ".repeat(width - take);
    for v in vals.iter().skip(vals.len() - take) {
        s.push(TICKS[((v / max * 7.0).round() as usize).min(7)]);
    }
    s
}

/// Sparkline from a fixed slice (already bucketed), scaled to its own max
/// with `floor` as the minimum ceiling. Width == slice length.
fn spark_vec(vals: &[f64], floor: f64, head: f64) -> String {
    let mut max = floor;
    for v in vals {
        if *v > max {
            max = *v;
        }
    }
    max = (max * head).max(f64::MIN_POSITIVE);
    vals.iter()
        .map(|v| TICKS[((v / max * 7.0).round() as usize).min(7)])
        .collect()
}

/// Multi-row graph with per-column color: each column is the newest
/// `width` samples scaled to `max`, drawn in eighth-block resolution
/// across `rows` lines and colored by `color(value/max)`. This is what
/// replaced ratatui's stock Sparkline — same geometry, but the color
/// carries the value too.
fn graph_lines(
    vals: &VecDeque<f64>,
    width: usize,
    rows: usize,
    max: f64,
    color: impl Fn(f64) -> Color,
) -> Vec<Line<'static>> {
    let take = vals.len().min(width);
    let slice: Vec<f64> = vals.iter().skip(vals.len() - take).copied().collect();
    let max = max.max(f64::MIN_POSITIVE);
    let pad = width - take;
    let mut lines = Vec::with_capacity(rows);
    for r in 0..rows {
        let mut spans = Vec::with_capacity(take + 1);
        if pad > 0 {
            spans.push(Span::raw(" ".repeat(pad)));
        }
        for v in &slice {
            let t = (v / max).clamp(0.0, 1.0);
            let eighths = (t * (rows * 8) as f64).round() as usize;
            let filled = eighths.saturating_sub((rows - 1 - r) * 8).min(8);
            if filled == 0 {
                spans.push(Span::raw(" "));
            } else {
                spans.push(Span::styled(TICKS[filled - 1].to_string(), Style::new().fg(color(t))));
            }
        }
        lines.push(Line::from(spans));
    }
    lines
}

const PAGE_SECS: f64 = 5.0; // seconds each page of a cycled list is shown

/// Cycle a list of rendered lines through pages, advancing every PAGE_SECS
/// so a long list is shown in full over time rather than crammed. Pages are
/// sized to fit `rows`, or to `cap` items when `cap > 0 and < rows` — that
/// forces a calmer page even when more would fit. Appends a dim "⟳ n/m"
/// indicator while paging; returns the list unchanged when it all fits.
fn paged(lines: Vec<Line<'static>>, rows: usize, cap: usize, secs: f64) -> Vec<Line<'static>> {
    if rows <= 1 {
        return lines;
    }
    let mut per = rows - 1; // reserve a row for the indicator
    if cap > 0 {
        per = per.min(cap);
    }
    if lines.len() <= per || (cap == 0 && lines.len() <= rows) {
        return lines;
    }
    let pages = lines.len().div_ceil(per);
    let page = ((secs / PAGE_SECS) as usize) % pages;
    let start = page * per;
    let end = (start + per).min(lines.len());
    let mut out: Vec<Line<'static>> = lines[start..end].to_vec();
    out.push(Line::from(Span::styled(format!("⟳ {}/{}", page + 1, pages), dim())));
    out
}

fn human_mem(mib: f64) -> String {
    if mib < 1024.0 {
        format!("{mib:5.0}M")
    } else {
        format!("{:5.1}G", mib / 1024.0)
    }
}

fn human_rate(rate: Option<f64>) -> String {
    match rate {
        None => "    -  ".into(),
        Some(b) if b < 1024.0 => format!("{b:4.0}B/s"),
        Some(b) if b < 1048576.0 => format!("{:4.1}K/s", b / 1024.0),
        Some(b) if b < 1073741824.0 => format!("{:4.1}M/s", b / 1048576.0),
        Some(b) => format!("{:4.1}G/s", b / 1073741824.0),
    }
}

fn human_size(bytes: f64) -> String {
    if bytes < 1048576.0 {
        format!("{:.0}K", bytes / 1024.0)
    } else if bytes < 1073741824.0 {
        format!("{:.1}M", bytes / 1048576.0)
    } else if bytes < 1099511627776.0 {
        format!("{:.1}G", bytes / 1073741824.0)
    } else {
        format!("{:.2}T", bytes / 1099511627776.0)
    }
}

/// "label ▓▓▓░░░ value" breakdown row (tile-mode MEM panel).
fn gauge_line(label: &'static str, frac: f64, value: String, color: Color, width: usize) -> Line<'static> {
    let frac = if frac.is_finite() { frac.clamp(0.0, 1.0) } else { 0.0 };
    let barw = width.saturating_sub(24).clamp(8, 40);
    let filled = (frac * barw as f64).round() as usize;
    Line::from(vec![
        Span::styled(format!("{label:<7}"), dim()),
        Span::styled("▓".repeat(filled), Style::new().fg(color)),
        Span::styled("░".repeat(barw - filled), Style::new().fg(C_BORDER)),
        Span::raw(format!(" {value}")),
    ])
}

/// "TOP CPU/MEM" process table (tile-mode CPU + MEM panels). `by_mem`
/// picks which column gets the heat color.
fn proc_lines(title: &'static str, procs: &[String], n: usize, by_mem: bool) -> Vec<Line<'static>> {
    let mut lines = vec![
        Line::default(),
        Line::styled(title, accent(C_BLUE)),
        Line::styled(format!("{:>5} {:>5}  {}", "CPU%", "MEM%", "COMMAND"), dim()),
    ];
    for p in procs.iter().take(n) {
        let f: Vec<&str> = p.split_whitespace().collect();
        if f.len() < 3 {
            continue;
        }
        let cpu: f64 = f[0].parse().unwrap_or(0.0);
        let mem: f64 = f[1].parse().unwrap_or(0.0);
        let (cpu_style, mem_style) = if by_mem {
            (dim(), Style::new().fg(heat(mem / 25.0)))
        } else {
            (Style::new().fg(heat(cpu / 50.0)), dim())
        };
        lines.push(Line::from(vec![
            Span::styled(format!("{:>5}", f[0]), cpu_style),
            Span::styled(format!(" {:>5}", f[1]), mem_style),
            Span::styled(format!("  {}", f[2..].join(" ")), Style::new().fg(C_FG)),
        ]));
    }
    lines
}

fn human_uptime(secs: u64) -> String {
    let d = secs / 86400;
    let h = secs % 86400 / 3600;
    let m = secs % 3600 / 60;
    if d > 0 {
        format!("{d}d {h}h")
    } else if h > 0 {
        format!("{h}h {m}m")
    } else {
        format!("{m}m")
    }
}

fn dot_color(state: &str) -> Color {
    match state {
        "active" | "running" | "ok" | "up" => C_GREEN,
        "inactive" | "failed" | "exited" | "dead" | "down" => C_RED,
        _ => C_YELLOW,
    }
}

fn ui(frame: &mut Frame, app: &App, mode: Mode) {
    let area = frame.area();
    match mode {
        Mode::Full => ui_full(frame, app),
        // Kiosk tiles: Mango draws the frame, so render borderless.
        Mode::Cpu => render_cpu(frame, area, app, false),
        Mode::Mem => render_mem(frame, area, app, false),
        Mode::Net => render_net(frame, area, app, false),
        Mode::Disk => render_disk(frame, area, app, false),
        Mode::Containers => render_containers(frame, area, app, false),
        Mode::Status => render_status(frame, area, app, true, false),
    }
}

/// The whole composite board — what tmux/ssh sessions see. The kiosk
/// instead runs six single-panel processes tiled by Mango.
fn ui_full(frame: &mut Frame, app: &App) {
    let h = &app.host;
    // Proportional heights: big history graphs up top (~24% of however
    // tall the display is), a fixed net/disk band, the rest to the
    // container + status grids. Degrades cleanly on small terminals.
    let [header, hosttop, hostnet, lower] =
        Layout::vertical([Constraint::Length(1), Constraint::Percentage(24), Constraint::Length(8), Constraint::Min(8)])
            .areas(frame.area());

    let loadc = heat(h.load / h.ncpu.max(1) as f64);
    let title = Line::from(vec![
        Span::styled(" ▲ GNAR ", accent(C_MAGENTA)),
        Span::styled(format!("· {} · up {} · ", h.hostname, human_uptime(h.uptime)), dim()),
        Span::styled(format!("load {:.2}", h.load), Style::new().fg(loadc)),
        Span::styled(format!("/{}", h.ncpu), dim()),
    ]);
    let clock = Line::from(Span::styled(format!("{} ", app.clock), accent(C_CYAN))).right_aligned();
    frame.render_widget(Paragraph::new(title), header);
    frame.render_widget(Paragraph::new(clock), header);

    // Full board has no compositor — keep the boxes as panel separators.
    let [cpu_a, mem_a] = Layout::horizontal([Constraint::Percentage(50), Constraint::Percentage(50)]).areas(hosttop);
    render_cpu(frame, cpu_a, app, true);
    render_mem(frame, mem_a, app, true);

    let [net_a, disk_a] = Layout::horizontal([Constraint::Percentage(50), Constraint::Percentage(50)]).areas(hostnet);
    render_net(frame, net_a, app, true);
    render_disk(frame, disk_a, app, true);

    let [cont_a, stat_a] = Layout::horizontal([Constraint::Percentage(62), Constraint::Percentage(38)]).areas(lower);
    render_containers(frame, cont_a, app, true);
    render_status(frame, stat_a, app, false, true);
}

fn render_cpu(frame: &mut Frame, cpu_a: Rect, app: &App, bordered: bool) {
    let h = &app.host;
    // Sensors ride the header as Tufte word-graphics: trend sparkline then
    // the current reading. Flat = steady, which is its own glanceable signal.
    let mut title = vec![
        Span::styled(" CPU ", accent(C_CYAN)),
        Span::styled(format!("{:.1}% ", h.cpu_cur), Style::new().fg(heat(h.cpu_cur / 100.0))),
    ];
    if let Some(t) = h.temp_c {
        title.push(Span::styled("· ", dim()));
        title.push(Span::styled(spark_abs(&h.temp_hist, 5, 95.0), Style::new().fg(heat((t / 90.0).clamp(0.0, 1.0)))));
        title.push(Span::styled(format!(" {t:.0}°C "), dim()));
    }
    if let Some(w) = h.watts {
        title.push(Span::styled("· ", dim()));
        title.push(Span::styled(spark_abs(&h.watts_hist, 5, 25.0), Style::new().fg(C_YELLOW)));
        title.push(Span::styled(format!(" {w:.0}W "), dim()));
    }
    // Tile mode: the kiosk has no global header, so clock + uptime ride
    // this tile's header line.
    let right = (cpu_a.height >= 22 && !app.clock.is_empty()).then(|| {
        Line::from(Span::styled(
            format!(" {} · up {} ", app.clock, human_uptime(h.uptime)),
            dim(),
        ))
    });
    let cpu_inner = panel(frame, cpu_a, bordered, title, right);
    if cpu_inner.height >= 20 && !h.cores_hist.is_empty() {
        // Tile mode: graph + per-core sparkline grid + load + top procs.
        let ncores = h.cores_hist.len();
        let half = ncores.div_ceil(2);
        let nprocs = app.procs_cpu.len().min(6) as u16;
        let [graph_a, cores_a, load_a, procs_a] = Layout::vertical([
            Constraint::Min(5),
            Constraint::Length(half as u16 + 1),
            Constraint::Length(1),
            Constraint::Length(nprocs + 3),
        ])
        .areas(cpu_inner);
        frame.render_widget(
            Paragraph::new(graph_lines(&h.cpu, graph_a.width as usize, graph_a.height as usize, 100.0, heat)),
            graph_a,
        );
        let csw = ((cores_a.width as usize).saturating_sub(2 * 9 + 3) / 2).clamp(8, 32);
        let seg = |i: usize| -> Vec<Span<'static>> {
            let cur = h.cores.get(i).copied().unwrap_or(0.0);
            let t = (cur / 100.0).clamp(0.0, 1.0);
            vec![
                Span::styled(format!("c{i:<2} "), dim()),
                Span::styled(spark(&h.cores_hist[i], csw, 5.0, 1.0), Style::new().fg(heat(t))),
                Span::styled(format!(" {cur:3.0}%"), Style::new().fg(heat(t))),
            ]
        };
        let mut core_lines = vec![Line::default()];
        for r in 0..half {
            let mut spans = seg(r);
            if r + half < ncores {
                spans.push(Span::raw("   "));
                spans.extend(seg(r + half));
            }
            core_lines.push(Line::from(spans));
        }
        frame.render_widget(Paragraph::new(core_lines), cores_a);
        let loadc = heat(h.load / h.ncpu.max(1) as f64);
        frame.render_widget(
            Paragraph::new(Line::from(vec![
                Span::styled("load ", dim()),
                Span::styled(spark(&h.load_hist, 24, h.ncpu as f64, 1.0), Style::new().fg(loadc)),
                Span::styled(format!(" {:.2}", h.load), Style::new().fg(loadc)),
                Span::styled(format!("/{}", h.ncpu), dim()),
            ])),
            load_a,
        );
        frame.render_widget(Paragraph::new(proc_lines("TOP CPU", &app.procs_cpu, 6, false)), procs_a);
    } else if cpu_inner.height > 1 {
        let graph = Rect { height: cpu_inner.height - 1, ..cpu_inner };
        frame.render_widget(
            Paragraph::new(graph_lines(&h.cpu, graph.width as usize, graph.height as usize, 100.0, heat)),
            graph,
        );
        let mut core_spans = vec![Span::styled("cores ", dim())];
        for p in &h.cores {
            let t = (p / 100.0).clamp(0.0, 1.0);
            core_spans.push(Span::styled(TICKS[(t * 7.0).round() as usize].to_string(), Style::new().fg(heat(t))));
        }
        let coreline = Rect { y: cpu_inner.y + cpu_inner.height - 1, height: 1, ..cpu_inner };
        frame.render_widget(Paragraph::new(Line::from(core_spans)), coreline);
    }
}

fn render_mem(frame: &mut Frame, mem_a: Rect, app: &App, bordered: bool) {
    let h = &app.host;
    let mem_t = if h.mem_total > 0.0 { h.mem_cur / h.mem_total } else { 0.0 };
    let title = vec![
        Span::styled(" MEM ", accent(C_MAGENTA)),
        Span::styled(
            format!("{} / {} ", human_mem(h.mem_cur).trim(), human_mem(h.mem_total).trim()),
            Style::new().fg(C_FG),
        ),
        Span::styled(format!("· {:.0}% ", mem_t * 100.0), dim()),
    ];
    let mem_inner = panel(frame, mem_a, bordered, title, None);
    if mem_inner.height >= 20 {
        // Tile mode: graph + breakdown gauges + top procs by memory.
        let nprocs = app.procs_mem.len().min(6) as u16;
        let [graph_a, brk_a, procs_a] = Layout::vertical([
            Constraint::Min(5),
            Constraint::Length(6),
            Constraint::Length(nprocs + 3),
        ])
        .areas(mem_inner);
        frame.render_widget(
            Paragraph::new(graph_lines(
                &h.mem_used,
                graph_a.width as usize,
                graph_a.height as usize,
                h.mem_total.max(1.0),
                |t| lerp(BLUE_RGB, MAGENTA_RGB, t),
            )),
            graph_a,
        );
        let w = brk_a.width as usize;
        let total = h.mem_total.max(1.0);
        frame.render_widget(
            Paragraph::new(vec![
                Line::default(),
                gauge_line("used", h.mem_cur / total, human_mem(h.mem_cur).trim().to_string(), C_MAGENTA, w),
                gauge_line("avail", h.mem_avail / total, human_mem(h.mem_avail).trim().to_string(), C_GREEN, w),
                gauge_line("cache", h.mem_cache / total, human_mem(h.mem_cache).trim().to_string(), C_BLUE, w),
                gauge_line(
                    "swap",
                    if h.swap_total > 0.0 { h.swap_used / h.swap_total } else { 0.0 },
                    format!("{} / {}", human_mem(h.swap_used).trim(), human_mem(h.swap_total).trim()),
                    C_YELLOW,
                    w,
                ),
            ]),
            brk_a,
        );
        frame.render_widget(Paragraph::new(proc_lines("TOP MEM", &app.procs_mem, 6, true)), procs_a);
    } else if mem_inner.height > 1 {
        let graph = Rect { height: mem_inner.height - 1, ..mem_inner };
        frame.render_widget(
            Paragraph::new(graph_lines(
                &h.mem_used,
                graph.width as usize,
                graph.height as usize,
                h.mem_total.max(1.0),
                |t| lerp(BLUE_RGB, MAGENTA_RGB, t),
            )),
            graph,
        );
        let swap_style = if h.swap_total > 0.0 && h.swap_used / h.swap_total > 0.5 {
            Style::new().fg(C_YELLOW)
        } else {
            dim()
        };
        let swapline = Rect { y: mem_inner.y + mem_inner.height - 1, height: 1, ..mem_inner };
        frame.render_widget(
            Paragraph::new(Line::from(Span::styled(
                format!("swap {} / {}", human_mem(h.swap_used).trim(), human_mem(h.swap_total).trim()),
                swap_style,
            ))),
            swapline,
        );
    }
}

fn render_net(frame: &mut Frame, net_a: Rect, app: &App, bordered: bool) {
    let h = &app.host;
    let peak = |v: &VecDeque<f64>| v.iter().copied().fold(0.0f64, f64::max);

    let net_inner = panel(
        frame,
        net_a,
        bordered,
        vec![
            Span::styled(" NET ", accent(C_YELLOW)),
            Span::styled(format!("{} ", h.iface), dim()),
        ],
        None,
    );
    // Tile mode gets a totals/sockets footer and the probed site list
    // (ingress health is network business) under the graphs.
    let mut sites_a = None;
    let (body, footer) = if net_inner.height >= 22 && !app.sites.is_empty() {
        // Fixed graphs band, then the rest goes to the site list — which
        // cycles (see paged()) rather than stretching the tile to fit all.
        let [b, f, s] =
            Layout::vertical([Constraint::Length(9), Constraint::Length(3), Constraint::Min(5)]).areas(net_inner);
        sites_a = Some(s);
        (b, Some(f))
    } else if net_inner.height >= 14 {
        let [b, f] = Layout::vertical([Constraint::Min(4), Constraint::Length(3)]).areas(net_inner);
        (b, Some(f))
    } else {
        (net_inner, None)
    };
    let [rx_a, tx_a] =
        Layout::vertical([Constraint::Percentage(50), Constraint::Percentage(50)]).areas(body);
    for (area, arrow, hue, cur, series) in [
        (rx_a, '↓', CYAN_RGB, h.rx_cur, &h.rx),
        (tx_a, '↑', MAGENTA_RGB, h.tx_cur, &h.tx),
    ] {
        let [label_a, graph_a] =
            Layout::vertical([Constraint::Length(1), Constraint::Min(1)]).areas(area);
        frame.render_widget(
            Paragraph::new(Line::from(vec![
                Span::styled(format!("{arrow} "), accent(lerp(hue, hue, 0.0))),
                Span::styled(human_rate(Some(cur)), Style::new().fg(C_FG)),
                Span::styled(format!("   peak {}", human_rate(Some(peak(series)))), dim()),
            ])),
            label_a,
        );
        let pk = peak(series).max(10240.0);
        frame.render_widget(
            Paragraph::new(graph_lines(series, graph_a.width as usize, graph_a.height as usize, pk, tint(hue))),
            graph_a,
        );
    }
    if let Some(f) = footer {
        let mut lines = vec![
            Line::default(),
            Line::from(vec![
                Span::styled("Σ ", dim()),
                Span::styled(format!("↓ {}", human_size(h.rx_total as f64)), Style::new().fg(C_CYAN)),
                Span::styled(" · ", dim()),
                Span::styled(format!("↑ {}", human_size(h.tx_total as f64)), Style::new().fg(C_MAGENTA)),
                Span::styled("      tcp ", dim()),
                Span::styled(spark_abs(&h.tcp_hist, 10, 128.0), Style::new().fg(C_BLUE)),
                Span::styled(format!(" {} estab · {} tw", h.tcp_inuse, h.tcp_tw), dim()),
            ]),
        ];
        // Radio + tailnet line: link quality colored good→bad (inverted
        // heat — high quality is green), peer reachability beside it.
        let mut link = Vec::new();
        if let Some(q) = h.wifi.back().copied() {
            let qc = heat(1.0 - q / 100.0);
            link.push(Span::styled("wifi ", dim()));
            link.push(Span::styled(spark(&h.wifi, 16, 100.0, 1.0), Style::new().fg(qc)));
            link.push(Span::styled(format!(" {q:.0}%"), Style::new().fg(qc)));
            link.push(Span::styled(format!(" · {:.0}dBm", h.wifi_dbm), dim()));
        }
        if app.ts_total > 0 {
            link.push(Span::styled("      TS ", dim()));
            link.push(Span::styled(
                "● ".to_string(),
                Style::new().fg(if app.ts_online > 0 { C_GREEN } else { C_YELLOW }),
            ));
            link.push(Span::styled(
                format!("{}/{} peers", app.ts_online, app.ts_total),
                Style::new().fg(C_FG),
            ));
            link.push(Span::styled(format!(" · {}", app.ts_ip), dim()));
        }
        if !link.is_empty() {
            lines.push(Line::from(link));
        }
        frame.render_widget(Paragraph::new(lines), f);
    }
    if let Some(sa) = sites_a {
        let down = app.sites.iter().filter(|s| s.ok == Some(false)).count();
        let mut header = vec![
            Span::styled("SITES ".to_string(), accent(C_BLUE)),
            Span::styled(format!("{}", app.sites.len()), dim()),
        ];
        if down > 0 {
            header.push(Span::styled(format!(" · {down} down"), Style::new().fg(C_RED)));
        }
        let mut lines = vec![Line::default(), Line::from(header), Line::default()];
        // Three header lines above; cycle the site rows through what's left.
        lines.extend(paged(site_rows(app), (sa.height as usize).saturating_sub(3), 0, app.render_secs));
        frame.render_widget(Paragraph::new(lines), sa);
    }
}

fn render_disk(frame: &mut Frame, disk_a: Rect, app: &App, bordered: bool) {
    let h = &app.host;
    let peak = |v: &VecDeque<f64>| v.iter().copied().fold(0.0f64, f64::max);

    let nvme = match (app.nvme_wear, app.nvme_temp) {
        (Some(w), Some(t)) => format!("· wear {w}% · {t}°C "),
        (Some(w), None) => format!("· wear {w}% "),
        _ => String::new(),
    };
    let disk_inner = panel(
        frame,
        disk_a,
        bordered,
        vec![
            Span::styled(" DISK ", accent(C_BLUE)),
            Span::styled(
                format!("/ {}% · {} · {} images {}", app.disk_pct, app.disk_detail, app.images, nvme),
                dim(),
            ),
        ],
        None,
    );
    // Tile mode gets a lifetime-IO footer under the graphs.
    let (body, footer) = if disk_inner.height >= 14 {
        let [b, f] = Layout::vertical([Constraint::Min(4), Constraint::Length(2)]).areas(disk_inner);
        (b, Some(f))
    } else {
        (disk_inner, None)
    };
    if let Some(f) = footer {
        frame.render_widget(
            Paragraph::new(vec![
                Line::default(),
                Line::from(vec![
                    Span::styled("Σ ", dim()),
                    Span::styled(format!("read {}", human_size(h.io_r_total as f64)), Style::new().fg(C_CYAN)),
                    Span::styled(" · ", dim()),
                    Span::styled(format!("written {}", human_size(h.io_w_total as f64)), Style::new().fg(C_MAGENTA)),
                    Span::styled(
                        if app.snapshots > 0 {
                            format!("      since boot · {} btrfs snapshots", app.snapshots)
                        } else {
                            "      since boot".to_string()
                        },
                        dim(),
                    ),
                ]),
            ]),
            f,
        );
    }
    let [gauge_a, iolabel_a, iograph_a] =
        Layout::vertical([Constraint::Length(1), Constraint::Length(1), Constraint::Min(1)]).areas(body);
    let barw = gauge_a.width as usize;
    let filled = (app.disk_pct as usize * barw / 100).min(barw);
    let mut gauge_spans = Vec::with_capacity(barw);
    for i in 0..barw {
        if i < filled {
            gauge_spans.push(Span::styled("▓", Style::new().fg(heat(i as f64 / barw as f64))));
        } else {
            gauge_spans.push(Span::styled("░", Style::new().fg(C_BORDER)));
        }
    }
    frame.render_widget(Paragraph::new(Line::from(gauge_spans)), gauge_a);
    frame.render_widget(
        Paragraph::new(Line::from(vec![
            Span::styled("io  read ", dim()),
            Span::styled(human_rate(Some(h.io_r_cur)), Style::new().fg(C_CYAN)),
            Span::styled(format!("  peak {}", human_rate(Some(peak(&h.io_r)))), dim()),
            Span::styled("      write ", dim()),
            Span::styled(human_rate(Some(h.io_w_cur)), Style::new().fg(C_MAGENTA)),
            Span::styled(format!("  peak {}", human_rate(Some(peak(&h.io_w)))), dim()),
        ])),
        iolabel_a,
    );
    let [ior_a, iow_a] =
        Layout::horizontal([Constraint::Percentage(50), Constraint::Percentage(50)]).areas(iograph_a);
    let pk_r = peak(&h.io_r).max(1048576.0);
    let pk_w = peak(&h.io_w).max(1048576.0);
    frame.render_widget(
        Paragraph::new(graph_lines(&h.io_r, ior_a.width as usize, ior_a.height as usize, pk_r, tint(CYAN_RGB))),
        ior_a,
    );
    frame.render_widget(
        Paragraph::new(graph_lines(&h.io_w, iow_a.width as usize, iow_a.height as usize, pk_w, tint(MAGENTA_RGB))),
        iow_a,
    );
}

fn render_containers(frame: &mut Frame, cont_a: Rect, app: &App, bordered: bool) {
    let total_mem: f64 = app.containers.values().map(|s| s.mem_cur).sum();
    let flagged = app.containers.values().filter(|s| s.flag.is_some()).count();
    let mut title = vec![
        Span::styled(" CONTAINERS ", accent(C_CYAN)),
        Span::styled(format!("{} ", app.containers.len()), Style::new().fg(C_FG)),
        Span::styled(format!("· mem {} ", human_mem(total_mem).trim()), dim()),
    ];
    if flagged > 0 {
        title.push(Span::styled(format!("· {flagged} unhealthy "), Style::new().fg(C_RED)));
    }
    let cont_inner = panel(frame, cont_a, bordered, title, None);
    // The list cycles (containers_panel) with breathing room at the bottom;
    // host-services + docker-ops moved to the OPS tile, which had the room.
    frame.render_widget(
        Paragraph::new(containers_panel(app, cont_inner.width as usize, cont_inner.height as usize)),
        cont_inner,
    );
}

fn render_status(frame: &mut Frame, stat_a: Rect, app: &App, tile: bool, bordered: bool) {
    // On the kiosk this tile is the OPS surface — services/sites/docker
    // live in the NET and CONTAINERS tiles there.
    let (title, content) = if tile {
        (" OPS ", ops_panel(app))
    } else {
        (" STATUS ", status_panel(app))
    };
    let stat_inner = panel(frame, stat_a, bordered, vec![Span::styled(title, accent(C_MAGENTA))], None);
    frame.render_widget(Paragraph::new(content), stat_inner);
}

fn containers_panel(app: &App, width: usize, height: usize) -> Vec<Line<'static>> {
    let namew = 26usize;
    let sw = ((width.saturating_sub(namew + 2 + 7 + 3 + 7 + 3 + 8)) / 2).clamp(8, 56);
    let rowlen = namew + 2 + sw + 7 + 3 + sw + 7 + 3 + 8;
    let memblue = Color::Rgb(0x6a, 0x7e, 0xc2);

    let mut lines = vec![
        Line::from(vec![
            Span::styled(format!("{:<w$}", "NAME", w = namew + 2), dim()),
            Span::styled(format!("{:<w$}", "CPU", w = sw + 1 + 6 + 3), dim()),
            Span::styled(format!("{:<w$}", "MEM", w = sw + 1 + 6 + 3), dim()),
            Span::styled("NET".to_string(), dim()),
        ]),
        Line::default(),
    ];

    if let Some(err) = &app.docker_err {
        lines.push(Line::styled(format!("docker unavailable: {err}"), Style::new().fg(C_RED)));
        return lines;
    }

    let mut rows: Vec<Line<'static>> = Vec::new();
    for (i, (name, s)) in app.containers.iter().enumerate() {
        let t = (s.cpu_cur / 100.0).clamp(0.0, 1.0);
        let name_color = if s.flag.is_some() {
            C_RED // restarting / unhealthy
        } else if name.starts_with("gnar") {
            C_CYAN
        } else {
            C_BLUE
        };
        let shown: String = name.chars().take(namew).collect();
        let net_style = match s.net_rate {
            Some(r) if r >= 1024.0 => Style::new().fg(C_CYAN),
            _ => dim(),
        };
        let mut spans = vec![
            Span::styled(format!("{shown:<namew$}  "), Style::new().fg(name_color)),
            Span::styled(spark(&s.cpu, sw, 5.0, 1.0), Style::new().fg(heat(t))),
            Span::styled(format!(" {:5.1}%", s.cpu_cur), Style::new().fg(heat(t))),
            Span::raw("   "),
            Span::styled(spark(&s.mem, sw, 1.0, 1.25), Style::new().fg(memblue)),
            Span::styled(format!(" {}", human_mem(s.mem_cur)), Style::new().fg(C_FG)),
            Span::raw("   "),
            Span::styled(human_rate(s.net_rate), net_style),
        ];
        // Pad to the panel edge so the zebra stripe runs full width.
        spans.push(Span::raw(" ".repeat(width.saturating_sub(rowlen))));
        let mut line = Line::from(spans);
        if i % 2 == 1 {
            line = line.style(Style::new().bg(C_BG_ALT));
        }
        rows.push(line);
    }
    if rows.is_empty() {
        lines.push(Line::styled("(no running containers)", dim()));
    } else {
        // Kiosk tile: cycle ~12 at a time for a calmer view, breathing room
        // pooling at the bottom. Full board (short): just show what fits.
        let cap = if height >= 20 { 12 } else { 0 };
        lines.extend(paged(rows, height.saturating_sub(2), cap, app.render_secs));
    }
    lines
}

/// Host services, two per row — six units in three lines.
fn service_rows(app: &App) -> Vec<Line<'static>> {
    app.services
        .chunks(2)
        .map(|pair| {
            let mut spans = Vec::new();
            for (name, state) in pair {
                spans.push(Span::styled("● ".to_string(), Style::new().fg(dot_color(state))));
                spans.push(Span::styled(format!("{name:<14}"), Style::new().fg(C_FG)));
                spans.push(Span::styled(format!("{state:<12}"), dim()));
            }
            Line::from(spans)
        })
        .collect()
}

/// Probed site rows: dot = live health, then host, probe result,
/// 5-minute traffic (from the caddy access log), kind.
fn site_rows(app: &App) -> Vec<Line<'static>> {
    app.sites
        .iter()
        .map(|site| {
            let (dotc, info) = match site.ok {
                Some(true) if site.code == 0 => (C_GREEN, format!("tls {}ms", site.ms)),
                Some(true) => (C_GREEN, format!("{} {}ms", site.code, site.ms)),
                Some(false) if site.code > 0 => (C_RED, format!("{} {}ms", site.code, site.ms)),
                Some(false) => (C_RED, "down".to_string()),
                None => (C_YELLOW, String::new()),
            };
            let info_style = if matches!(site.ok, Some(false)) { Style::new().fg(C_RED) } else { dim() };
            let kind_color = match site.kind.as_str() {
                "private" => C_CYAN,
                "public" => C_MAGENTA,
                _ => C_YELLOW,
            };
            // Truncate long hostnames — format width pads but never cuts.
            let mut host: String = site.host.chars().take(24).collect();
            if site.host.chars().count() > 24 {
                host.pop();
                host.push('…');
            }
            let mut spans = vec![
                Span::styled("● ".to_string(), Style::new().fg(dotc)),
                Span::styled(format!("{host:<25}"), Style::new().fg(C_FG)),
                Span::styled(format!("{info:<10}"), info_style),
            ];
            match app.traffic.get(&site.host) {
                Some(t) if t.reqs > 0 => {
                    let sp = if t.spark.is_empty() {
                        " ".repeat(TRAFFIC_BINS)
                    } else {
                        spark_vec(&t.spark, 1.0, 1.1)
                    };
                    spans.push(Span::styled(sp, dim()));
                    spans.push(Span::styled(format!(" {:>4}/5m ", t.reqs), Style::new().fg(C_CYAN)));
                    // Priority: server errors > actionable 4xx > 404 noise.
                    // 404s are dimmed so they read as background hum, not a fault.
                    if t.e5xx > 0 {
                        spans.push(Span::styled(format!("{}×5xx ", t.e5xx), Style::new().fg(C_RED)));
                    } else if t.e4xx > 0 {
                        spans.push(Span::styled(format!("{}×4xx ", t.e4xx), Style::new().fg(C_YELLOW)));
                    } else if t.e404 > 0 {
                        spans.push(Span::styled(format!("{}×404 ", t.e404), dim()));
                    } else {
                        spans.push(Span::raw("      "));
                    }
                }
                _ => {
                    spans.push(Span::raw(" ".repeat(TRAFFIC_BINS)));
                    spans.push(Span::styled("    -/5m      ", dim()));
                }
            }
            spans.push(Span::styled(site.kind.clone(), Style::new().fg(kind_color)));
            Line::from(spans)
        })
        .collect()
}

/// One-line docker ops summary: running/total, images, next prune,
/// pending updates.
fn docker_line(app: &App) -> Line<'static> {
    let mut spans = vec![
        Span::styled("● ".to_string(), Style::new().fg(C_GREEN)),
        Span::styled(
            format!("{}/{} containers running", app.containers.len(), app.containers_total),
            Style::new().fg(C_FG),
        ),
        Span::styled(format!("   {} images", app.images), dim()),
    ];
    if !app.prune_next.is_empty() {
        spans.push(Span::styled(format!("   prune {}", app.prune_next), dim()));
    }
    // Updates / security / reboot live in the OPS tile's SECURITY section,
    // which renders right below this line — no need to repeat them here.
    Line::from(spans)
}

fn hermes_summary_line(app: &App) -> Line<'static> {
    let gateway_up = app.containers.contains_key("gnar-hermes-gateway");
    let mut hermes = vec![
        Span::styled("HERMES".to_string(), accent(C_MAGENTA)),
        Span::raw("   "),
        Span::styled("● ".to_string(), Style::new().fg(if gateway_up { C_GREEN } else { C_RED })),
        Span::styled(
            if gateway_up { "gateway up" } else { "gateway down" },
            Style::new().fg(C_FG),
        ),
    ];
    if !app.kanban_lines.is_empty() {
        hermes.push(Span::styled(format!("   kanban {}", app.kanban_lines.len()), Style::new().fg(C_CYAN)));
    }
    if !app.cron_lines.is_empty() {
        hermes.push(Span::styled(format!("   cron {}", app.cron_lines.len()), Style::new().fg(C_CYAN)));
    }
    let size = if app.backup_size_mb > 0 { format!(" · {}M", app.backup_size_mb) } else { String::new() };
    match app.backup_age_h {
        Some(hh) if hh > 36 => hermes.push(Span::styled(format!("   ● backup {hh}h old{size}"), Style::new().fg(C_RED))),
        Some(hh) => hermes.push(Span::styled(format!("   ✓ backup {hh}h{size}"), Style::new().fg(C_GREEN))),
        None => hermes.push(Span::styled("   backup ?", dim())),
    }
    Line::from(hermes)
}

/// Full-board STATUS panel: services, probed sites, top procs, HERMES
/// summary. (The kiosk splits this across tiles.)
fn status_panel(app: &App) -> Vec<Line<'static>> {
    let mut lines = vec![Line::styled("HOST SERVICES", accent(C_BLUE)), Line::default()];
    lines.extend(service_rows(app));
    lines.push(Line::default());
    lines.push(Line::styled("CADDY SITES", accent(C_BLUE)));
    lines.push(Line::default());
    if app.sites.is_empty() {
        lines.push(Line::styled("(no sites)", dim()));
    }
    lines.extend(site_rows(app));
    if !app.procs_cpu.is_empty() {
        lines.extend(proc_lines("TOP PROCESSES", &app.procs_cpu, 10, false));
    }
    lines.push(Line::default());
    lines.push(hermes_summary_line(app));
    lines
}

/// The prominent ALERTS block — a red title bar plus one descriptive line
/// per fault (which units, which crashed processes, sample error text).
/// Empty when the host is clean, so it only appears when it matters.
fn alert_lines(app: &App) -> Vec<Line<'static>> {
    if app.failed_units.is_empty() && app.crashes.is_empty() && app.journal_errs == 0 {
        return Vec::new();
    }
    let red_bold = Style::new().fg(C_RED).add_modifier(Modifier::BOLD);
    let mut out = vec![
        Line::default(),
        Line::from(Span::styled(
            "  ⚠  ALERTS  ",
            Style::new().bg(C_RED).fg(Color::Black).add_modifier(Modifier::BOLD),
        )),
    ];
    let bullet = || Span::styled("● ".to_string(), Style::new().fg(C_RED));
    if !app.failed_units.is_empty() {
        out.push(Line::from(vec![
            bullet(),
            Span::styled(
                format!("{} unit{} failed", app.failed_units.len(), if app.failed_units.len() == 1 { "" } else { "s" }),
                red_bold,
            ),
            Span::styled(format!(" — {}", app.failed_units.join(", ")), Style::new().fg(C_FG)),
        ]));
    }
    if !app.crashes.is_empty() {
        out.push(Line::from(vec![
            bullet(),
            Span::styled("crashes/h".to_string(), red_bold),
            Span::styled(format!(" — {}", app.crashes.join(", ")), Style::new().fg(C_FG)),
        ]));
    }
    if app.journal_errs > 0 {
        out.push(Line::from(vec![
            bullet(),
            Span::styled(
                format!("{} journal error{}/h", app.journal_errs, if app.journal_errs == 1 { "" } else { "s" }),
                red_bold,
            ),
        ]));
        for s in &app.err_sample {
            out.push(Line::from(Span::styled(format!("    {s}"), dim())));
        }
    }
    out
}

/// The kiosk OPS tile: Hermes gateway + backup health, live claude runs,
/// the box's security posture, host alerts, kanban, and cron. Folds what
/// used to be three sparse half-empty regions into one dense ops surface.
fn ops_panel(app: &App) -> Vec<Line<'static>> {
    let gateway_up = app.containers.contains_key("gnar-hermes-gateway");
    let size = if app.backup_size_mb > 0 { format!(" · {}M", app.backup_size_mb) } else { String::new() };
    let backup_span = match app.backup_age_h {
        Some(hh) if hh > 36 => Span::styled(format!("     ● backup {hh}h old{size}"), Style::new().fg(C_RED)),
        Some(hh) => Span::styled(format!("     ✓ backup {hh}h{size}"), Style::new().fg(C_GREEN)),
        None => Span::styled("     backup ?", dim()),
    };
    let mut status_line = vec![
        Span::styled("● ".to_string(), Style::new().fg(if gateway_up { C_GREEN } else { C_RED })),
        Span::styled(
            if gateway_up { "gateway up" } else { "gateway down" },
            Style::new().fg(C_FG),
        ),
        backup_span,
    ];
    if app.backup_sizes.len() >= 3 {
        let sizes: VecDeque<f64> = app.backup_sizes.iter().copied().collect();
        status_line.push(Span::raw(" "));
        status_line.push(Span::styled(spark(&sizes, 8, 1.0, 1.25), dim()));
    }
    let mut lines = vec![Line::from(status_line)];
    // Alerts ride up top, right under the gateway line, so a fault is the
    // first thing the eye lands on.
    lines.extend(alert_lines(app));
    lines.push(if app.claude_runs > 0 {
        Line::from(vec![
            Span::styled("● ".to_string(), Style::new().fg(C_CYAN)),
            Span::styled(
                format!(
                    "{} claude process{} live",
                    app.claude_runs,
                    if app.claude_runs == 1 { "" } else { "es" }
                ),
                Style::new().fg(C_CYAN),
            ),
        ])
    } else {
        Line::from(Span::styled("○ idle — no claude processes", dim()))
    });
    if app.claude_total > 0 {
        lines.push(Line::from(Span::styled(
            format!(
                "claude: {} session{} active 24h · {} transcripts",
                app.claude_24h,
                if app.claude_24h == 1 { "" } else { "s" },
                app.claude_total
            ),
            dim(),
        )));
    }
    // SERVICES + DOCKER — host units and the container-ops summary, moved
    // here from the (now calmer, cycling) CONTAINERS tile.
    lines.push(Line::default());
    lines.push(Line::styled("SERVICES", accent(C_BLUE)));
    lines.extend(service_rows(app));
    lines.push(docker_line(app));
    // SECURITY — posture at a glance. Updates stay dim (routine on a
    // rolling release); CVE-fixing updates, a pending reboot, and live
    // intrusion counters carry color.
    lines.push(Line::default());
    lines.push(Line::styled("SECURITY", accent(C_BLUE)));
    let mut sec = Vec::new();
    if let Some(n) = app.updates {
        sec.push(Span::styled(format!("{n} updates"), dim()));
    }
    match app.sec_updates {
        Some(s) if s > 0 => {
            sec.push(Span::styled("   ● ".to_string(), Style::new().fg(C_RED)));
            sec.push(Span::styled(format!("{s} security"), Style::new().fg(C_RED)));
        }
        Some(_) => sec.push(Span::styled("   ✓ no known CVEs".to_string(), Style::new().fg(C_GREEN))),
        None => {}
    }
    if let Some(d) = app.last_update_days {
        sec.push(Span::styled(format!("   · updated {d}d ago"), dim()));
    }
    if !sec.is_empty() {
        lines.push(Line::from(sec));
    }
    let mut intr = Vec::new();
    if let Some(v) = &app.reboot_pending {
        intr.push(Span::styled(format!("● reboot pending ({v})   "), Style::new().fg(C_YELLOW)));
    }
    intr.push(Span::styled(
        format!("{} banned", app.banned_ips),
        Style::new().fg(if app.banned_ips > 0 { C_YELLOW } else { C_DIM }),
    ));
    intr.push(Span::styled(" · ", dim()));
    intr.push(Span::styled(
        format!("{} ssh fails/h", app.ssh_fails),
        Style::new().fg(if app.ssh_fails > 0 { C_YELLOW } else { C_DIM }),
    ));
    lines.push(Line::from(intr));

    lines.extend([
        Line::default(),
        Line::from(vec![
            Span::styled("KANBAN ".to_string(), accent(C_BLUE)),
            Span::styled(format!("{}", app.kanban_lines.len()), dim()),
        ]),
        Line::default(),
    ]);
    if app.kanban_lines.is_empty() {
        lines.push(Line::styled("(no open tasks)", dim()));
    }
    for t in app.kanban_lines.iter().take(8) {
        lines.push(Line::styled(t.clone(), Style::new().fg(C_FG)));
    }
    lines.push(Line::default());
    lines.push(Line::from(vec![
        Span::styled("CRON ".to_string(), accent(C_BLUE)),
        Span::styled(format!("{}", app.cron_lines.len()), dim()),
    ]));
    lines.push(Line::default());
    if app.cron_lines.is_empty() {
        lines.push(Line::styled("(no scheduled jobs)", dim()));
    }
    for (active, name, sched) in app.cron_lines.iter().take(12) {
        lines.push(Line::from(vec![
            Span::styled(
                if *active { "● " } else { "○ " }.to_string(),
                Style::new().fg(if *active { C_GREEN } else { C_DIM }),
            ),
            Span::styled(format!("{name:<26}"), Style::new().fg(C_FG)),
            Span::styled(sched.clone(), dim()),
        ]));
    }
    lines
}

// ---------------------------------------------------------------------------

fn main() -> std::io::Result<()> {
    let mode = match std::env::args().nth(1).as_deref() {
        None | Some("full") => Mode::Full,
        Some("cpu") => Mode::Cpu,
        Some("mem") => Mode::Mem,
        Some("net") => Mode::Net,
        Some("disk") => Mode::Disk,
        Some("containers") => Mode::Containers,
        Some("status") => Mode::Status,
        Some(other) => {
            eprintln!("gnar-board: unknown panel '{other}'");
            eprintln!("usage: gnar-board [full|cpu|mem|net|disk|containers|status]");
            std::process::exit(2);
        }
    };

    let app = Arc::new(Mutex::new(App::default()));

    // Each panel only runs the samplers it displays — six Mango tiles
    // shouldn't mean six docker pollers.
    if matches!(mode, Mode::Full | Mode::Cpu | Mode::Mem | Mode::Net | Mode::Disk) {
        let a = app.clone();
        thread::spawn(move || host_loop(a));
    }
    if matches!(mode, Mode::Full | Mode::Containers | Mode::Status) {
        let a = app.clone();
        thread::spawn(move || docker_loop(a));
    }
    {
        // Every panel shows something from the status loop now (procs,
        // sites, services, disk, hermes) — hermes execs and the heavy
        // hourly samplers stay gated to the panels that render them.
        let a = app.clone();
        thread::spawn(move || status_loop(a, mode));
    }
    if matches!(mode, Mode::Full | Mode::Cpu) {
        let a = app.clone();
        thread::spawn(move || clock_loop(a));
    }

    let mut terminal = ratatui::init();
    // Touch/mouse: each kiosk tile is its own foot window, so a tap on a
    // tile reaches that one process. Capturing the press lets it advance
    // its own paginated view (see `taps` below). Harmless when no pointer
    // exists. Needs the compositor to deliver touch as pointer events.
    execute!(std::io::stdout(), EnableMouseCapture).ok();
    // Kiosk tiles respawn inside one long-lived foot alt-screen (the
    // `while :; do gnar-board …` loop), so the buffer still holds the
    // previous run's cells. ratatui assumes a blank screen and only
    // diffs against it, leaving stale glyphs wherever the new frame is
    // shorter. A one-time clear realigns its model with the screen.
    terminal.clear()?;
    let start = Instant::now();
    // A tap (or a fallback key) advances every cycled list in this tile by
    // one page. Modeled as added time so the page index jumps forward by
    // exactly one and the gentle auto-cycle simply continues from there.
    let mut taps: u64 = 0;
    loop {
        {
            let mut st = app.lock().unwrap();
            st.render_secs = start.elapsed().as_secs_f64() + taps as f64 * PAGE_SECS;
            terminal.draw(|f| ui(f, &st, mode))?;
        }
        if event::poll(Duration::from_millis(500))? {
            match event::read()? {
                Event::Mouse(m) if matches!(m.kind, MouseEventKind::Down(_)) => taps += 1,
                Event::Key(k) if k.kind == KeyEventKind::Press => {
                    // Advance keys double as a keyboard fallback for the tap.
                    if matches!(
                        k.code,
                        KeyCode::Char(' ') | KeyCode::Char('n') | KeyCode::Right | KeyCode::Down
                    ) {
                        taps += 1;
                    } else if matches!(k.code, KeyCode::Char('q') | KeyCode::Char('Q') | KeyCode::Esc)
                        || (k.code == KeyCode::Char('c') && k.modifiers.contains(KeyModifiers::CONTROL))
                    {
                        break;
                    }
                }
                _ => {}
            }
        }
    }
    execute!(std::io::stdout(), DisableMouseCapture).ok();
    ratatui::restore();
    Ok(())
}
