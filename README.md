<h1 align="center">🚀 Server Bench</h1>

<p align="center">
  <b>All-in-one server diagnostics & performance testing</b><br>
  <sub>One command. Beautiful output. All the info you need to vet a VPS.</sub>
</p>

<p align="center">
  <a href="README.ru.md">🇷🇺 Читать по-русски</a>
</p>

<p align="center">
  <img src="https://img.shields.io/github/v/tag/jestivald/server-bench?style=for-the-badge&label=version&color=blueviolet" alt="Version">
  <img src="https://img.shields.io/github/actions/workflow/status/jestivald/server-bench/lint.yml?style=for-the-badge&label=lint" alt="Lint">
  <img src="https://img.shields.io/github/actions/workflow/status/jestivald/server-bench/smoke.yml?style=for-the-badge&label=smoke%20test" alt="Smoke">
  <img src="https://img.shields.io/badge/platform-linux-FCC624?style=for-the-badge&logo=linux&logoColor=black" alt="Linux">
  <img src="https://img.shields.io/badge/license-MIT-blue?style=for-the-badge" alt="License">
</p>

<p align="center">
  <img src="assets/demo.svg" alt="server-bench demo" width="680">
</p>

## ⚡ Quick Start

Run on a Linux server:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/jestivald/server-bench/main/server-bench.sh)
```

Choose tests interactively (numbers/ranges, estimated duration, tool requirements):

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/jestivald/server-bench/main/server-bench.sh) --menu
```

Quick health check (system info + network + security + docker, ~1 min):

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/jestivald/server-bench/main/server-bench.sh) --quick
```

Save results to a file:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/jestivald/server-bench/main/server-bench.sh) --quick 2>&1 | tee bench-results.txt
```

> Dependencies (sysbench, fio, dnsutils, iperf3, jq) are installed automatically — but only
> the ones the selected modules actually need. Use `--no-install` to forbid
> any package installation; external scripts are skipped in this mode.

**Report mode (v2.1):** when you run more than one module on a terminal, tests
execute quietly behind a progress checklist (`[████░░░░] 44% ► speed-ru 2m 14s`),
and a full **structured report** is printed once everything finishes — no more
walls of text scrolling past. The complete plain-text report is also saved
automatically to `./server-bench-<timestamp>.log.<random>`. Prefer the old streaming
output? Add `--live`. Reports are private (mode `600`), and concurrent runs get distinct files.

## 🧪 What It Tests

| Module | Flag | What it does | Time |
|:---|:---|:---|:---|
| 📋 System Info | `--info` | OS, CPU model/steal%/AES-NI, virtualization, RAM, disk usage, IP, geo, rDNS, sysbench CPU (1 + N threads) | ~30s |
| 💾 Disk Bench | `--disk` | fio: sequential 1M read/write + 4K random IOPS, direct I/O on a real (non-tmpfs) path; dd fallback | ~1min |
| 🌐 Network | `--network` | TCP stack (BBR? qdisc? MTU), outbound port 25, parallel ping latency+loss and DNS probes | ~15s |
| 🔒 Security | `--security` | Effective sshd config (`sshd -T` incl. drop-ins), firewall (ufw/nft/iptables), fail2ban, pending updates | ~10s |
| 🐳 Docker | `--docker` | Container status, counts, disk usage | ~5s |
| 🔍 IP Check | `--ip` | IP reputation ([IP.Check.Place](https://ip.check.place)) + region detection ([ipregion](https://github.com/vernette/ipregion)) | ~3min |
| 🇷🇺 Speed RU | `--speed-ru` | Native iPerf3 to five Russian cities; separate upload and reverse download, 4 streams, 5s per direction | ~2min |
| 🌍 Speed INT | `--speed-int` | Speed test to international providers (bench.sh / speed.tlab.pw) | ~5min |
| 🌍 Geoblocks | `--geoblock` | Service geoblocking checks ([censorcheck](https://github.com/vernette/censorcheck), `--mode geoblock`) | ~2min |
| 📸 Instagram | `--instagram` | Instagram audio block check (bench.openode.xyz) | ~30s |
| 🛡️ DPI Check | `--dpi` | DPI censorship check for RU servers ([censorcheck](https://github.com/vernette/censorcheck)) | ~1min |
| 📊 YABS | `--yabs` | Classic [yabs.sh](https://github.com/masonr/yet-another-bench-script): fio + iperf3 + Geekbench 6 | ~20min |

`--all` (default) runs everything except `--geoblock`, `--instagram`, `--dpi` and `--yabs` — those are opt-in.

## 🎯 Usage

```bash
# full test suite
bash <(curl -fsSL https://raw.githubusercontent.com/jestivald/server-bench/main/server-bench.sh) --all

# quick health check
bash <(curl -fsSL https://raw.githubusercontent.com/jestivald/server-bench/main/server-bench.sh) --quick

# pick what you need (flags combine)
bash <(curl -fsSL https://raw.githubusercontent.com/jestivald/server-bench/main/server-bench.sh) --info --disk --network

# machine-readable: JSON to stdout, human report to stderr
bash <(curl -fsSL https://raw.githubusercontent.com/jestivald/server-bench/main/server-bench.sh) --json --quick 2>/dev/null

# hide detected server IPs (a.b.x.x), hostname and rDNS
bash <(curl -fsSL https://raw.githubusercontent.com/jestivald/server-bench/main/server-bench.sh) --quick --hide-ip
```

### Options

| Flag | Effect |
|:---|:---|
| `--menu` | Interactive module selection; Enter starts the selection, `q` cancels |
| `--list` | List modules, duration estimates and required tools without running anything |
| `--report` | Progress checklist + structured report at the end + autosave to file (default for multi-module terminal runs) |
| `--live` | Stream test output live as it happens (default for single-module runs) |
| `--json` | JSON to stdout for built-in modules, including `--speed-ru`; human report to stderr |
| `--hide-ip` | Mask detected server IPs and hide hostname/rDNS; skip external scripts |
| `--no-install` | Never install packages; missing tools degrade gracefully and external scripts are skipped |
| `--no-color` | Disable colors (the `NO_COLOR` env var works too) |
| `--version` / `--help` | You guessed it |

With only output/control flags, the default `--all` selection still applies. Use
`--quick` for a shorter run. `--ip-check` and `--ip-region` select the two parts
of `--ip` separately. `--menu` requires a terminal and cannot combine with `--json`.

### JSON output example

```json
{"version":"2.3.0","os":"Debian GNU/Linux 12 (bookworm)","virt":"kvm",
 "cpu_cores":4,"cpu_eps_1t":2847.31,"cpu_steal_pct":0.3,
 "disk_seq_write_mbs":412.7,"disk_rand_read_iops":48210,
 "tcp_cc":"bbr","qdisc":"fq","ping_yandex_avg_ms":38.2,
 "ssh_password_auth":"no","fail2ban":"yes",
 "module_security_status":"warning","module_security_elapsed_s":2,
 "fails":0,"warns":1,"skips":0}
```

Module status keys use `ok`, `warning`, `failed` or `skipped`. Missing numeric
measurements are `null`. RU throughput is in Mbps, for example
`speed_ru_moscow_upload_mbps` and `speed_ru_moscow_download_mbps`.
Legacy disk keys ending in `_mbs` contain MiB/s (fio KiB/s divided by 1024).
A completed diagnostic run exits `0`, even when findings are present; automation
should inspect `fails`, `warns` and module statuses. CLI/setup errors exit nonzero.

## 📋 Requirements

- Linux (Debian, Ubuntu, CentOS, Fedora, AlmaLinux, Rocky)
- bash 4+, GNU coreutils (`timeout`), curl for IP/external checks
- root **or** sudo recommended (auto-install + privileged checks); runs
  unprivileged too, with some checks skipped

CI runs offline regressions on Ubuntu 22.04 and 24.04. Pull requests and main
pushes also run the full local suite, validate measured fio/CPU values, and
exercise real iPerf3 on loopback plus timeout cleanup. See [development notes](docs/V2.3-NOTES.md).

## 🔗 Under the Hood

The heavy lifting in external modules is done by well-known community
scripts, executed at run time (with timeouts):

| Check | Upstream |
|:---|:---|
| IP reputation | [IP.Check.Place](https://ip.check.place) |
| IP region | [vernette/ipregion](https://github.com/vernette/ipregion) |
| DPI censorship / geoblocks | [vernette/censorcheck](https://github.com/vernette/censorcheck) |
| International speed | [bench.sh](https://bench.sh) (teddysun), speed.tlab.pw |
| Instagram audio | bench.openode.xyz |
| YABS | [masonr/yet-another-bench-script](https://github.com/masonr/yet-another-bench-script) |

Built-in modules (info/disk/network/security/docker/speed-ru) call installed
`sysbench`, `fio`, `dd`, `ping`, `dig`, `iperf3` and `jq` directly. The RU endpoint
list comes from [itdoginfo/russian-iperf3-servers](https://github.com/itdoginfo/russian-iperf3-servers).
The menu and geoblock additions were inspired by [saveksme/multitest](https://github.com/saveksme/multitest)
and implemented independently. Server Bench saves its own report locally.

> External modules download and execute live third-party scripts. The historical
> [upstream review](docs/UPSTREAM-AUDIT.md) describes its July snapshot, not later
> upstream changes. `--json`, `--no-install` and `--hide-ip` skip those scripts.
> IP.Check.Place keeps its `-p` privacy option; opt-in YABS can publish Geekbench results.

## 📝 Changelog

**v2.3** — 2026-09-06
- `--menu` / `--list`: choose checks, see approximate duration and tool requirements.
- `--geoblock`: separate service geoblocking checks through censorcheck.
- Native `--speed-ru`: real upload and download (`iperf3 -R`), bounded port retries, JSON metrics.
- Parallel ping, DNS and IPv4/IPv6 probes; one batched dependency install and one apt refresh per run.
- Correct fio error validation and 10-second random tests; full/unknown filesystems are skipped during path selection.
- Fix UFW `inactive` detection, unknown SSH settings, stale update claims and Docker rows with empty ports.
- Reliable JSON escaping, module statuses/timings, private unique reports and child-process timeouts.
- `--no-install` / `--hide-ip` now skip external scripts; output-only flags correctly select the default suite.

**v2.2** — 2026-07-06
- External scripts get **"y" auto-answered** — no more hanging or dying on "continue? [y/n]" prompts (dependency installs are confirmed for you)
- If an upstream endpoint returns an HTML page or the script dies right after start, server-bench now **fails over to the mirror** (bench.gig.ovh root became an HTML page — RU speed test now runs bench.tlab.pw first)
- **⚡ Scorecard**: the structured report opens with a one-screen summary — CPU/RAM/disk/network/IP/security at a glance
- IP.Check.Place is called with **`-p` (privacy)**: your report is no longer uploaded to upload.check.place for a public share link (+`-y` for deps)
- Progress spinners of captured scripts no longer flood the report or the saved log (proper `\r` emulation)
- Disk-usage table cleaned of tmpfs/docker-overlay noise; Docker status column no longer truncated mid-word; DNS shows `<1ms` instead of `0ms`
- **Security audit of all upstream scripts** — [docs/UPSTREAM-AUDIT.md](docs/UPSTREAM-AUDIT.md)

**v2.1** — 2026-07-06
- **Report mode**: multi-module runs now show a progress checklist with percentage instead of scrolling output, then print a structured report at the end (local modules replayed in full, speed tests condensed to their result tables, IP check to key findings)
- Full plain-text report **auto-saved** to `./server-bench-<timestamp>.log` (ANSI-stripped)
- `--live` to stream output like before, `--report` to force report mode for a single module

**v2.0** — 2026-07-06
- No more mid-run death: removed fragile `set -e`, every check degrades gracefully; summary shows fail/warn counts and per-module timing
- Works as plain root without `sudo` installed (typical VPS); never prompts for a password in non-interactive runs
- Honest disk benchmark: fio with direct I/O on a real disk-backed filesystem (never tmpfs), free-space guard, dd kept as fallback
- Dependencies installed lazily — only what the selected modules need; `--help` no longer touches apt 🙃
- New: `--yabs`, `--json`, `--hide-ip`, `--no-install`, `--no-color`, `--version`
- New checks: CPU steal%, virtualization type, AES-NI, multi-thread sysbench, BBR/qdisc/MTU, outbound port 25, packet loss, rDNS, effective sshd config (drop-ins included), nftables
- External scripts run with timeouts, stderr no longer swallowed; correct yum/dnf package names; CI: shellcheck + smoke test on a real runner

<details>
<summary><b>v1.0</b></summary>

- Initial release: system info, dd disk test, ping/DNS, SSH/firewall audit, docker status, wrappers for IP.Check.Place / ipregion / bench.sh / bench.gig.ovh / censorcheck / Instagram checker
</details>

## 📄 License

MIT
