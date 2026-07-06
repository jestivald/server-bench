<p align="center">
  <img src="https://img.shields.io/badge/version-2.0-blueviolet?style=for-the-badge" alt="Version">
  <img src="https://img.shields.io/badge/bash-4.0+-4EAA25?style=for-the-badge&logo=gnu-bash&logoColor=white" alt="Bash">
  <img src="https://img.shields.io/badge/platform-linux-FCC624?style=for-the-badge&logo=linux&logoColor=black" alt="Linux">
  <img src="https://img.shields.io/badge/license-MIT-blue?style=for-the-badge" alt="License">
</p>

<h1 align="center">🚀 Server Bench</h1>

<p align="center">
  <b>All-in-one server diagnostics & performance testing</b><br>
  <sub>One command. Beautiful output. All the info you need to vet a VPS.</sub>
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

## 📸 Sample Output

```
   ╔═╗┌─┐┬─┐┬  ┬┌─┐┬─┐  ╔╗ ┌─┐┌┐┌┌─┐┬ ┬
   ╚═╗├┤ ├┬┘└┐┌┘├┤ ├┬┘  ╠╩╗├┤ ││││  ├─┤
   ╚═╝└─┘┴└─ └┘ └─┘┴└─  ╚═╝└─┘┘└┘└─┘┴ ┴
   v2.0.0 • all-in-one server diagnostics

════════════════════════════════════════════════════
  SYSTEM INFORMATION
════════════════════════════════════════════════════
  ┌─ CPU
  Model:        Intel Xeon E5-2680 v4
  Cores:        4
  AES-NI:       yes
  CPU steal:    0.3%
  Single-thread: 2847.31 events/sec
  ✔ Good CPU performance

  ┌─ Network
  IPv4:         203.0.113.42
  Location:     Amsterdam, Netherlands
  ISP:          Example Hosting

  ┌─ TCP Stack
  Congestion control:  bbr
  Default qdisc:       fq
  Outbound port 25:    blocked or filtered

  ┌─ Security
  ✔ Root login: key only
  ✔ Password authentication disabled
  ✔ UFW: active
  ✔ Fail2ban: active (2 jails)

  ✔ All tests completed in 1m 12s  (0 failed, 1 warnings)
════════════════════════════════════════════════════
```

## 📋 Requirements

- Linux (Debian, Ubuntu, CentOS, Fedora, AlmaLinux, Rocky)
- bash 4+, curl
- root **or** sudo recommended (auto-install + privileged checks); runs
  unprivileged too, with some checks skipped

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
> nature of this tool — audit the upstreams above if your threat model
> requires it, or stick to local modules.

## 📝 Changelog

**v2.0**
- No more mid-run death: removed fragile `set -e`, every check degrades gracefully; summary shows fail/warn counts and per-module timing
- Works as plain root without `sudo` installed (typical VPS); never prompts for a password in non-interactive runs
- Honest disk benchmark: fio with direct I/O and correct package names per distro, test file placed on a real disk-backed filesystem (never tmpfs), free-space guard, dd kept as fallback
- Dependencies installed lazily — only what the selected modules need; `--help` no longer touches apt 🙃
- New: `--yabs`, `--json`, `--hide-ip`, `--no-install`, `--no-color`, `--version`
- New checks: CPU steal%, virtualization type, AES-NI, multi-thread sysbench, BBR/qdisc/MTU, outbound port 25, packet loss, rDNS, effective sshd config (drop-ins included), nftables
- External scripts run with timeouts, stderr no longer swallowed; correct yum/dnf package names; CI shellcheck

## 📄 License

MIT
