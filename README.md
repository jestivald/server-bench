<p align="center">
  <img src="https://img.shields.io/badge/bash-5.0+-4EAA25?style=for-the-badge&logo=gnu-bash&logoColor=white" alt="Bash">
  <img src="https://img.shields.io/badge/platform-linux-FCC624?style=for-the-badge&logo=linux&logoColor=black" alt="Linux">
  <img src="https://img.shields.io/badge/license-MIT-blue?style=for-the-badge" alt="License">
</p>

<h1 align="center">🚀 Server Bench</h1>

<p align="center">
  <b>All-in-one server diagnostics & performance testing</b><br>
  <sub>One command. Beautiful output. All the info you need.</sub>
</p>

## ⚡ Quick Start

Run on any server, no installation needed:

```bash
bash <(curl -Ls https://raw.githubusercontent.com/jestivald/server-bench/main/server-bench.sh)
```

Quick check (system info + network + security + docker, ~30 sec):

```bash
bash <(curl -Ls https://raw.githubusercontent.com/jestivald/server-bench/main/server-bench.sh) --quick
```

Save results to file:

```bash
bash <(curl -Ls https://raw.githubusercontent.com/jestivald/server-bench/main/server-bench.sh) --quick 2>&1 | tee /tmp/bench-results.txt
```

> Dependencies (sysbench, fio, dnsutils, etc.) are installed automatically on first run.

## 🧪 What It Tests

| Module | Flag | What it does | Time |
|:---|:---|:---|:---|
| 📋 System Info | `--info` | OS, CPU, RAM, disk usage, IP, geo, CPU benchmark | ~15s |
| 💾 Disk Bench | `--disk` | Sequential read/write (dd) + random IOPS (fio) | ~30s |
| 🌐 Network | `--network` | Ping latency to Cloudflare/Google/Yandex + DNS resolution | ~15s |
| 🔒 Security | `--security` | SSH config audit, firewall, fail2ban, pending updates | ~5s |
| 🐳 Docker | `--docker` | Container status, images, disk usage | ~5s |
| 🔍 IP Check | `--ip` | IP reputation (IP.Check.Place) + IP region detection | ~3min |
| 🇷🇺 Speed RU | `--speed-ru` | Speed test to Russian providers | ~5min |
| 🌍 Speed INT | `--speed-int` | Speed test to international providers | ~5min |
| 📸 Instagram | `--instagram` | Instagram audio block check | ~30s |
| 🛡️ DPI Check | `--dpi` | DPI censorship check (for RU servers) | ~1min |

## 🎯 Usage

```bash
# full test suite
bash <(curl -Ls https://raw.githubusercontent.com/jestivald/server-bench/main/server-bench.sh) --all

# quick health check
bash <(curl -Ls https://raw.githubusercontent.com/jestivald/server-bench/main/server-bench.sh) --quick

# pick what you need
bash <(curl -Ls https://raw.githubusercontent.com/jestivald/server-bench/main/server-bench.sh) --info --disk

# ip checks only
bash <(curl -Ls https://raw.githubusercontent.com/jestivald/server-bench/main/server-bench.sh) --ip

# speed tests only
bash <(curl -Ls https://raw.githubusercontent.com/jestivald/server-bench/main/server-bench.sh) --speed

# help
bash <(curl -Ls https://raw.githubusercontent.com/jestivald/server-bench/main/server-bench.sh) --help
```

Flags can be combined: `--info --disk --network`

## 📸 Sample Output

```
   ┌─────────────────────────────────────────────────┐
   │   ___                          ___              │
   │  / __| ___ _ ___ _____ _ _   | _ ) ___ _ _  __ │
   │  \__ \/ -_) '_\ V / -_) '_|  | _ \/ -_) ' \/ _|│
   │  |___/\___|_|  \_/\___|_|    |___/\___|_||_\__|│
   │                                                 │
   │         All-in-One Server Diagnostics           │
   └─────────────────────────────────────────────────┘

════════════════════════════════════════════════════
  SYSTEM INFORMATION
════════════════════════════════════════════════════
  ┌─ CPU
  Model:       Intel Xeon E5-2680 v4
  Cores:       4
  Events/sec:  2847.31
  ✔ Good CPU performance

  ┌─ Network
  IPv4:        203.0.113.42
  Location:    Amsterdam, Netherlands
  ISP:         Example Hosting

  ┌─ Ping Latency
  Cloudflare   1.2ms    ✔
  Google       2.1ms    ✔
  Yandex       45.3ms   ✔

  ┌─ Security
  ✔ Root login disabled
  ✔ Password auth disabled
  ✔ UFW: active
  ✔ Fail2ban: active (2 jails)

  ✔ All tests completed in 0m 28s
════════════════════════════════════════════════════
```

## 📋 Requirements

- Linux (Ubuntu, Debian, CentOS, Fedora)
- Root or sudo access
- curl or wget

Everything else is auto-installed.

## 📄 License

MIT
