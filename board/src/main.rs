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
    collections::{BTreeMap, VecDeque},
    fs,
    io::{Read, Write},
    os::unix::net::UnixStream,
    process::Command,
    sync::{Arc, Mutex},
    thread,
    time::{Duration, Instant, SystemTime},
};

use ratatui::{
    crossterm::event::{self, Event, KeyCode, KeyEventKind, KeyModifiers},
    prelude::*,
    widgets::{Block, Paragraph, Sparkline},
};
use serde_json::Value;

const DOCKER_SOCK: &str = "/var/run/docker.sock";
const KEEP: usize = 240; // samples per series (~8 min at 2s cadence)
const STATS_EVERY: Duration = Duration::from_secs(2);
const STATUS_EVERY: Duration = Duration::from_secs(30);
const SERVICES: [&str; 6] = ["docker", "postgresql", "valkey", "fail2ban", "ufw", "gnar-stack"];
const STACK: &str = "/srv/stack";
const TICKS: [char; 8] = ['▁', '▂', '▃', '▄', '▅', '▆', '▇', '█'];

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
    prev: Option<Prev>,
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
    cores: Vec<f64>, // per-core %, latest sample
    temp_c: Option<f64>,
    mem_used: VecDeque<f64>, // MiB
    mem_cur: f64,
    mem_total: f64,
    swap_used: f64,
    swap_total: f64,
    iface: String,
    rx: VecDeque<f64>, // bytes/sec
    tx: VecDeque<f64>,
    rx_cur: f64,
    tx_cur: f64,
    io_r: VecDeque<f64>, // bytes/sec
    io_w: VecDeque<f64>,
    io_r_cur: f64,
    io_w_cur: f64,
    uptime: u64,
    hostname: String,
    load: f64,
    ncpu: usize,
    prev_cpu: Option<(Vec<(u64, u64)>, (u64, u64))>, // per-core + total (busy, total)
    prev_net: Option<(Instant, u64, u64)>,
    prev_io: Option<(Instant, u64, u64)>,
}

#[derive(Default)]
struct App {
    host: Host,
    containers: BTreeMap<String, Series>,
    services: Vec<(String, String)>,
    sites: Vec<(String, String)>,
    procs: Vec<String>,
    disk_pct: u8,
    disk_detail: String,
    images: usize,
    kanban: usize,
    cron: usize,
    backup_age_h: Option<u64>,
    docker_err: Option<String>,
    clock: String,
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

fn meminfo() -> Option<(f64, f64, f64, f64)> {
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
    let st = get("SwapTotal:").unwrap_or(0.0);
    let sf = get("SwapFree:").unwrap_or(0.0);
    Some((total - avail, total, st - sf, st))
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
        }
        h.ncpu = cores.len().max(1);
        h.prev_cpu = Some((cores, agg));
    }
    if let Some((used, total, sused, stotal)) = meminfo() {
        h.mem_cur = used;
        h.mem_total = total;
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
        h.prev_net = Some((now, rx, tx));
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
        h.prev_io = Some((now, r, w));
    }
    if let Ok(s) = fs::read_to_string("/proc/uptime") {
        h.uptime = s.split('.').next().and_then(|v| v.parse().ok()).unwrap_or(0);
    }
    if let Ok(s) = fs::read_to_string("/proc/loadavg") {
        h.load = s.split_whitespace().next().and_then(|v| v.parse().ok()).unwrap_or(0.0);
    }
    if h.hostname.is_empty() {
        h.hostname = fs::read_to_string("/etc/hostname").map(|s| s.trim().to_string()).unwrap_or_default();
    }
    h.temp_c = cpu_temp();
}

// ---------------------------------------------------------------------------
// Container + status sampling
// ---------------------------------------------------------------------------

fn stats_loop(app: Arc<Mutex<App>>) {
    loop {
        let started = Instant::now();
        sample_host(&mut app.lock().unwrap().host);
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
        s.prev = Some(Prev { at: now, cpu_total, sys_total, net_total });
        drop(a);
        seen.push(name);
    }

    app.lock().unwrap().containers.retain(|k, _| seen.contains(k));
    Ok(())
}

fn status_loop(app: Arc<Mutex<App>>) {
    let mut tick: u64 = 0;
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

        let sites = caddy_sites();
        let backup_age_h = backup_age_hours();
        let (disk_pct, disk_detail) = disk_usage();
        let procs = top_procs();
        let images = docker_get("/images/json")
            .ok()
            .and_then(|v| v.as_array().map(|a| a.len()))
            .unwrap_or(0);

        // Hermes counts are docker-exec subprocesses — every other cycle.
        let hermes = if tick % 2 == 0 {
            Some((hermes_count("kanban"), hermes_count("cron")))
        } else {
            None
        };

        {
            let mut a = app.lock().unwrap();
            a.services = services;
            a.sites = sites;
            a.procs = procs;
            a.backup_age_h = backup_age_h;
            a.disk_pct = disk_pct;
            a.disk_detail = disk_detail;
            a.images = images;
            if let Some((k, c)) = hermes {
                a.kanban = k;
                a.cron = c;
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

fn hermes_count(what: &str) -> usize {
    Command::new("timeout")
        .args(["10", "docker", "exec", "gnar-hermes-gateway", "hermes", what, "list"])
        .output()
        .ok()
        .map(|o| {
            String::from_utf8_lossy(&o.stdout)
                .lines()
                .filter(|l| !l.trim().is_empty())
                .count()
        })
        .unwrap_or(0)
}

fn top_procs() -> Vec<String> {
    Command::new("ps")
        .args(["-eo", "pcpu,pmem,comm", "--sort=-pcpu", "--no-headers"])
        .output()
        .ok()
        .map(|o| {
            String::from_utf8_lossy(&o.stdout)
                .lines()
                .take(6)
                .map(|l| l.trim().to_string())
                .collect()
        })
        .unwrap_or_default()
}

fn caddy_sites() -> Vec<(String, String)> {
    let hostish = |h: &str| !h.is_empty() && h.chars().all(|c| c.is_ascii_alphanumeric() || c == '.' || c == '-');
    let mut out = Vec::new();
    if let Ok(s) = fs::read_to_string(format!("{STACK}/Caddyfile")) {
        for l in s.lines() {
            let l = l.trim_end();
            if let Some(h) = l.strip_suffix(":80 {") {
                if h.ends_with(".local") && hostish(h) {
                    out.push((h.to_string(), "private".into()));
                }
            } else if let Some(h) = l.strip_prefix("http://").and_then(|r| r.strip_suffix(":8080 {")) {
                if hostish(h) {
                    out.push((h.to_string(), "public".into()));
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
        out.extend(previews.into_iter().map(|h| (h, "preview".into())));
    }
    out
}

fn backup_age_hours() -> Option<u64> {
    let newest = fs::read_dir(format!("{STACK}/data/backups"))
        .ok()?
        .flatten()
        .filter(|e| {
            let n = e.file_name();
            let n = n.to_string_lossy();
            n.starts_with("hermes-backup-") && n.ends_with(".zip")
        })
        .filter_map(|e| e.metadata().ok()?.modified().ok())
        .max()?;
    SystemTime::now()
        .duration_since(newest)
        .ok()
        .map(|d| d.as_secs() / 3600)
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
        "active" | "running" | "ok" | "up" => Color::Green,
        "inactive" | "failed" | "exited" | "dead" | "down" => Color::Red,
        _ => Color::Yellow,
    }
}

fn dim() -> Style {
    Style::new().add_modifier(Modifier::DIM)
}

fn head_style() -> Style {
    Style::new().fg(Color::Cyan).add_modifier(Modifier::BOLD)
}

fn section(title: Vec<Span<'static>>) -> Block<'static> {
    Block::bordered()
        .border_style(dim())
        .title(Line::from(title))
}

fn spark_u64(vals: &VecDeque<f64>, width: usize) -> Vec<u64> {
    let take = vals.len().min(width);
    vals.iter().skip(vals.len() - take).map(|v| (*v).max(0.0) as u64).collect()
}

fn ui(frame: &mut Frame, app: &App) {
    let h = &app.host;
    let [header, hosttop, hostnet, lower] =
        Layout::vertical([Constraint::Length(1), Constraint::Length(9), Constraint::Length(5), Constraint::Min(8)])
            .areas(frame.area());

    // --- header -------------------------------------------------------------
    let title = Line::from(vec![
        Span::styled(" GNAR ", head_style()),
        Span::styled(format!("· {} · up {} · load {:.2}/{}", h.hostname, human_uptime(h.uptime), h.load, h.ncpu), dim()),
    ]);
    let clock = Line::from(Span::styled(format!("{} ", app.clock), dim())).right_aligned();
    frame.render_widget(Paragraph::new(title), header);
    frame.render_widget(Paragraph::new(clock), header);

    // --- CPU / MEM graphs ----------------------------------------------------
    let [cpu_a, mem_a] = Layout::horizontal([Constraint::Percentage(50), Constraint::Percentage(50)]).areas(hosttop);

    let temp = h.temp_c.map(|t| format!(" · {t:.0}°C")).unwrap_or_default();
    let cpu_block = section(vec![
        Span::styled(" CPU ", head_style()),
        Span::styled(format!("{:.1}%{} ", h.cpu_cur, temp), dim()),
    ]);
    let cpu_inner = cpu_block.inner(cpu_a);
    frame.render_widget(cpu_block, cpu_a);
    if cpu_inner.height > 1 {
        let graph = Rect { height: cpu_inner.height - 1, ..cpu_inner };
        frame.render_widget(
            Sparkline::default()
                .data(&spark_u64(&h.cpu, graph.width as usize))
                .max(100)
                .style(Style::new().fg(Color::Cyan)),
            graph,
        );
        let cores: String = h.cores.iter().map(|p| TICKS[((p / 100.0 * 7.0).round() as usize).min(7)]).collect();
        let coreline = Rect { y: cpu_inner.y + cpu_inner.height - 1, height: 1, ..cpu_inner };
        frame.render_widget(
            Paragraph::new(Line::from(vec![Span::styled("cores ", dim()), Span::raw(cores)])),
            coreline,
        );
    }

    let mem_block = section(vec![
        Span::styled(" MEM ", head_style()),
        Span::styled(format!("{} / {} ", human_mem(h.mem_cur).trim().to_string(), human_mem(h.mem_total).trim()), dim()),
    ]);
    let mem_inner = mem_block.inner(mem_a);
    frame.render_widget(mem_block, mem_a);
    if mem_inner.height > 1 {
        let graph = Rect { height: mem_inner.height - 1, ..mem_inner };
        frame.render_widget(
            Sparkline::default()
                .data(&spark_u64(&h.mem_used, graph.width as usize))
                .max(h.mem_total.max(1.0) as u64)
                .style(Style::new().fg(Color::Green)),
            graph,
        );
        let swapline = Rect { y: mem_inner.y + mem_inner.height - 1, height: 1, ..mem_inner };
        frame.render_widget(
            Paragraph::new(Line::from(Span::styled(
                format!("swap {} / {}", human_mem(h.swap_used).trim(), human_mem(h.swap_total).trim()),
                dim(),
            ))),
            swapline,
        );
    }

    // --- NET / DISK ------------------------------------------------------------
    let [net_a, disk_a] = Layout::horizontal([Constraint::Percentage(50), Constraint::Percentage(50)]).areas(hostnet);

    let net_block = section(vec![
        Span::styled(" NET ", head_style()),
        Span::styled(format!("{} ", h.iface), dim()),
    ]);
    let net_inner = net_block.inner(net_a);
    frame.render_widget(net_block, net_a);
    let nsw = (net_inner.width as usize).saturating_sub(14).clamp(8, 80);
    frame.render_widget(
        Paragraph::new(vec![
            Line::from(vec![
                Span::raw(format!("↓ {} ", human_rate(Some(h.rx_cur)))),
                Span::styled(spark(&h.rx, nsw, 10240.0, 1.0), dim()),
            ]),
            Line::from(vec![
                Span::raw(format!("↑ {} ", human_rate(Some(h.tx_cur)))),
                Span::styled(spark(&h.tx, nsw, 10240.0, 1.0), dim()),
            ]),
        ]),
        net_inner,
    );

    let disk_block = section(vec![
        Span::styled(" DISK ", head_style()),
        Span::styled(format!("/ {}% · {} ", app.disk_pct, app.disk_detail), dim()),
    ]);
    let disk_inner = disk_block.inner(disk_a);
    frame.render_widget(disk_block, disk_a);
    let barw = (disk_inner.width as usize).saturating_sub(2).clamp(10, 60);
    let filled = (app.disk_pct as usize * barw / 100).min(barw);
    let dsw = (disk_inner.width as usize).saturating_sub(16).clamp(8, 60);
    frame.render_widget(
        Paragraph::new(vec![
            Line::from(vec![
                Span::styled("▓".repeat(filled), Style::new().fg(if app.disk_pct > 85 { Color::Red } else { Color::Cyan })),
                Span::styled("░".repeat(barw - filled), dim()),
            ]),
            Line::from(vec![
                Span::raw(format!("io r {} ", human_rate(Some(h.io_r_cur)))),
                Span::styled(spark(&h.io_r, dsw / 2, 1048576.0, 1.0), dim()),
                Span::raw(format!("  w {} ", human_rate(Some(h.io_w_cur)))),
                Span::styled(spark(&h.io_w, dsw / 2, 1048576.0, 1.0), dim()),
            ]),
        ]),
        disk_inner,
    );

    // --- lower: containers + status -------------------------------------------
    let [cont_a, stat_a] = Layout::horizontal([Constraint::Percentage(58), Constraint::Percentage(42)]).areas(lower);

    let cont_block = section(vec![Span::styled(" CONTAINERS ", head_style())]);
    let cont_inner = cont_block.inner(cont_a);
    frame.render_widget(cont_block, cont_a);
    frame.render_widget(
        Paragraph::new(containers_panel(app, cont_inner.width as usize, cont_inner.height as usize)),
        cont_inner,
    );

    let stat_block = section(vec![Span::styled(" STATUS ", head_style())]);
    let stat_inner = stat_block.inner(stat_a);
    frame.render_widget(stat_block, stat_a);
    frame.render_widget(Paragraph::new(status_panel(app)), stat_inner);
}

fn containers_panel(app: &App, width: usize, height: usize) -> Vec<Line<'static>> {
    let namew = 22usize;
    let sw = ((width.saturating_sub(namew + 2 + 7 + 3 + 7 + 3 + 8)) / 2).clamp(8, 40);

    let mut lines = vec![
        Line::from(vec![
            Span::styled(format!("{:<w$}", "NAME", w = namew + 2), Style::new().fg(Color::Cyan)),
            Span::styled(format!("{:<w$}", "CPU", w = sw + 1 + 6 + 3), Style::new().fg(Color::Cyan)),
            Span::styled(format!("{:<w$}", "MEM", w = sw + 1 + 6 + 3), Style::new().fg(Color::Cyan)),
            Span::styled("NET".to_string(), Style::new().fg(Color::Cyan)),
        ]),
        Line::default(),
    ];

    if let Some(err) = &app.docker_err {
        lines.push(Line::styled(format!("docker unavailable: {err}"), Style::new().fg(Color::Red)));
        return lines;
    }

    let avail = height.saturating_sub(3);
    for (i, (name, s)) in app.containers.iter().enumerate() {
        if i >= avail {
            lines.push(Line::styled(format!("… +{} more", app.containers.len() - i), dim()));
            break;
        }
        let cpu_color = if s.cpu_cur >= 80.0 {
            Color::Red
        } else if s.cpu_cur >= 40.0 {
            Color::Yellow
        } else {
            Color::Green
        };
        let shown: String = name.chars().take(namew).collect();
        lines.push(Line::from(vec![
            Span::raw(format!("{shown:<namew$}  ")),
            Span::styled(spark(&s.cpu, sw, 5.0, 1.0), dim()),
            Span::styled(format!(" {:5.1}%", s.cpu_cur), Style::new().fg(cpu_color)),
            Span::raw("   "),
            Span::styled(spark(&s.mem, sw, 1.0, 1.25), dim()),
            Span::raw(format!(" {}", human_mem(s.mem_cur))),
            Span::raw("   "),
            Span::styled(human_rate(s.net_rate), dim()),
        ]));
    }
    if app.containers.is_empty() {
        lines.push(Line::styled("(no running containers)", dim()));
    }
    lines
}

fn status_panel(app: &App) -> Vec<Line<'static>> {
    let mut lines = vec![Line::styled("HOST SERVICES".to_string(), head_style()), Line::default()];

    for (name, state) in &app.services {
        lines.push(Line::from(vec![
            Span::styled("● ".to_string(), Style::new().fg(dot_color(state))),
            Span::raw(format!("{name:<14}")),
            Span::styled(state.clone(), dim()),
        ]));
    }

    lines.push(Line::default());
    lines.push(Line::styled("CADDY SITES".to_string(), head_style()));
    lines.push(Line::default());
    if app.sites.is_empty() {
        lines.push(Line::styled("(no sites)", dim()));
    }
    for (host, kind) in &app.sites {
        lines.push(Line::from(vec![
            Span::styled("● ".to_string(), Style::new().fg(Color::Green)),
            Span::raw(format!("{host:<28}")),
            Span::styled(kind.clone(), dim()),
        ]));
    }

    if !app.procs.is_empty() {
        lines.push(Line::default());
        lines.push(Line::styled("TOP PROCESSES".to_string(), head_style()));
        lines.push(Line::default());
        lines.push(Line::styled(format!("{:>5} {:>5}  {}", "CPU%", "MEM%", "COMMAND"), dim()));
        for p in &app.procs {
            let f: Vec<&str> = p.split_whitespace().collect();
            if f.len() >= 3 {
                lines.push(Line::raw(format!("{:>5} {:>5}  {}", f[0], f[1], f[2..].join(" "))));
            }
        }
    }

    let gateway_up = app.containers.contains_key("gnar-hermes-gateway");
    let mut hermes = vec![
        Span::styled("HERMES".to_string(), head_style()),
        Span::raw("   "),
        Span::styled("● ".to_string(), Style::new().fg(if gateway_up { Color::Green } else { Color::Red })),
        Span::raw(if gateway_up { "gateway up" } else { "gateway down" }),
    ];
    if app.kanban > 0 {
        hermes.push(Span::styled(format!("   kanban {}", app.kanban), dim()));
    }
    if app.cron > 0 {
        hermes.push(Span::styled(format!("   cron {}", app.cron), dim()));
    }
    match app.backup_age_h {
        Some(h) if h > 36 => hermes.push(Span::styled(format!("   ● backup {h}h old"), Style::new().fg(Color::Red))),
        Some(h) => hermes.push(Span::styled(format!("   backup {h}h"), dim())),
        None => hermes.push(Span::styled("   backup ?", dim())),
    }
    lines.push(Line::default());
    lines.push(Line::from(hermes));
    lines
}

// ---------------------------------------------------------------------------

fn main() -> std::io::Result<()> {
    let app = Arc::new(Mutex::new(App::default()));
    for f in [stats_loop, status_loop, clock_loop] {
        let a = app.clone();
        thread::spawn(move || f(a));
    }

    let mut terminal = ratatui::init();
    loop {
        {
            let st = app.lock().unwrap();
            terminal.draw(|f| ui(f, &st))?;
        }
        if event::poll(Duration::from_millis(500))? {
            if let Event::Key(k) = event::read()? {
                if k.kind != KeyEventKind::Press {
                    continue;
                }
                let quit = matches!(k.code, KeyCode::Char('q') | KeyCode::Char('Q') | KeyCode::Esc)
                    || (k.code == KeyCode::Char('c') && k.modifiers.contains(KeyModifiers::CONTROL));
                if quit {
                    break;
                }
            }
        }
    }
    ratatui::restore();
    Ok(())
}
