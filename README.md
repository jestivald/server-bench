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

Run on any server, no installation needed:

```bash
bash <(curl -Ls https://raw.githubusercontent.com/jestivald/server-bench/main/server-bench.sh)
```

Quick health check (system info + network + security + docker, ~1 min):

```bash
bash <(curl -Ls https://raw.githubusercontent.com/jestivald/server-bench/main/server-bench.sh) --quick
```

Save results to a file:

```bash
bash <(curl -Ls https://raw.githubusercontent.com/jestivald/server-bench/main/server-bench.sh) --quick 2>&1 | tee bench-results.txt
```

> Dependencies (sysbench, fio, dnsutils) are installed automatically — but only
> the ones the selected modules actually need. Use `--no-install` to forbid
> any package installation.

**Report mode (v2.1):** when you run more than one module on a terminal, tests
execute quietly behind a progress checklist (`[████░░░░] 44% ► speed-ru 2m 14s`),
and a full **structured report** is printed once everything finishes — no more
walls of text scrolling past. The complete plain-text report is also saved
automatically to `./server-bench-<timestamp>.log`. Prefer the old streaming
output? Add `--live`.

## 🧪 What It Tests

| Module | Flag | What it does | Time |
|:---|:---|:---|:---|
| 📋 System Info | `--info` | OS, CPU model/steal%/AES-NI, virtualization, RAM, disk usage, IP, geo, rDNS, sysbench CPU (1 + N threads) | ~30s |
| 💾 Disk Bench | `--disk` | fio: sequential 1M read/write + 4K random IOPS, direct I/O on a real (non-tmpfs) path; dd fallback | ~1min |
| 🌐 Network | `--network` | TCP stack (BBR? qdisc? MTU), outbound port 25, ping latency+loss, DNS resolution timing | ~30s |
| 🔒 Security | `--security` | Effective sshd config (`sshd -T` incl. drop-ins), firewall (ufw/nft/iptables), fail2ban, pending updates | ~10s |
| 🐳 Docker | `--docker` | Container status, counts, disk usage | ~5s |
| 🔍 IP Check | `--ip` | IP reputation ([IP.Check.Place](https://ip.check.place)) + region detection ([ipregion](https://github.com/vernette/ipregion)) | ~3min |
| 🇷🇺 Speed RU | `--speed-ru` | Speed test to Russian providers (bench.gig.ovh / bench.tlab.pw) | ~5min |
| 🌍 Speed INT | `--speed-int` | Speed test to international providers (bench.sh / speed.tlab.pw) | ~5min |
| 📸 Instagram | `--instagram` | Instagram audio block check (bench.openode.xyz) | ~30s |
| 🛡️ DPI Check | `--dpi` | DPI censorship check for RU servers ([censorcheck](https://github.com/vernette/censorcheck)) | ~1min |
| 📊 YABS | `--yabs` | Classic [yabs.sh](https://github.com/masonr/yet-another-bench-script): fio + iperf3 + Geekbench 6 | ~20min |

`--all` (default) runs everything except `--instagram`, `--dpi` and `--yabs` — those are opt-in.

## 🎯 Usage

```bash
# full test suite
bash <(curl -Ls https://raw.githubusercontent.com/jestivald/server-bench/main/server-bench.sh) --all

# quick health check
bash <(curl -Ls https://raw.githubusercontent.com/jestivald/server-bench/main/server-bench.sh) --quick

# pick what you need (flags combine)
bash <(curl -Ls https://raw.githubusercontent.com/jestivald/server-bench/main/server-bench.sh) --info --disk --network

# machine-readable: JSON to stdout, human report to stderr
bash <(curl -Ls https://raw.githubusercontent.com/jestivald/server-bench/main/server-bench.sh) --json --quick 2>/dev/null

# results you can paste publicly — public IPs masked (a.b.x.x)
bash <(curl -Ls https://raw.githubusercontent.com/jestivald/server-bench/main/server-bench.sh) --quick --hide-ip
```

### Options

| Flag | Effect |
|:---|:---|
| `--report` | Progress checklist + structured report at the end + autosave to file (default for multi-module terminal runs) |
| `--live` | Stream test output live as it happens (default for single-module runs) |
| `--json` | JSON object to stdout (local modules only), pretty report goes to stderr |
| `--hide-ip` | Mask public IPs in the report — safe to paste into forums/chats |
| `--no-install` | Never install packages; tests degrade gracefully |
| `--no-color` | Disable colors (the `NO_COLOR` env var works too) |
| `--version` / `--help` | You guessed it |

### JSON output example

```json
{"version":"2.0.0","os":"Debian GNU/Linux 12 (bookworm)","virt":"kvm",
 "cpu_cores":4,"cpu_eps_1t":2847.31,"cpu_steal_pct":0.3,
 "disk_seq_write_mbs":412.7,"disk_rand_read_iops":48210,
 "tcp_cc":"bbr","qdisc":"fq","ping_yandex_avg_ms":38.2,
 "ssh_password_auth":"no","fail2ban":"yes","fails":0,"warns":1}
```

## 📋 Requirements

- Linux (Debian, Ubuntu, CentOS, Fedora, AlmaLinux, Rocky)
- bash 4+, curl
- root **or** sudo recommended (auto-install + privileged checks); runs
  unprivileged too, with some checks skipped

Every push is smoke-tested on a real Ubuntu runner: the full local suite
(`--info --disk --network --security --docker`) must complete end-to-end.

## 🔗 Under the Hood

The heavy lifting in external modules is done by well-known community
scripts, executed at run time (with timeouts):

| Check | Upstream |
|:---|:---|
| IP reputation | [IP.Check.Place](https://ip.check.place) |
| IP region | [vernette/ipregion](https://github.com/vernette/ipregion) |
| DPI censorship | [vernette/censorcheck](https://github.com/vernette/censorcheck) |
| RU speed | bench.gig.ovh, bench.tlab.pw |
| International speed | [bench.sh](https://bench.sh) (teddysun), speed.tlab.pw |
| Instagram audio | bench.openode.xyz |
| YABS | [masonr/yet-another-bench-script](https://github.com/masonr/yet-another-bench-script) |

Local modules (info/disk/network/security/docker) are self-contained and use
`sysbench`, `fio`, `dd`, `ping`, `dig` directly.

> ⚠️ External modules download and execute third-party scripts. That is the
> nature of this tool — all upstreams were security-audited (no backdoors,
> no exfiltration, no persistence): see **[docs/UPSTREAM-AUDIT.md](docs/UPSTREAM-AUDIT.md)**
> (snapshot 2026-07-06, with hashes). If your threat model can't accept
> executing live upstream copies, stick to local modules.

## 📝 Changelog

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
