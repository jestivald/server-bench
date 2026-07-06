# Upstream Script Audit

server-bench executes several well-known community scripts at run time.
This is a point-in-time security review of every upstream we call — checked
for backdoors, data exfiltration, persistence, obfuscated payloads and
privilege abuse. **None was found.**

- **Snapshot date: 2026-07-06.** SHA-256 hashes below identify the exact
  bytes reviewed. Upstreams update independently and server-bench always
  runs the *live* copy, so this audit describes that snapshot, not eternity.
- Method: five scripts got a full line-by-line read, the rest a mechanical
  sweep (obfuscation patterns, all network endpoints, POST/upload payloads,
  filesystem writes, cron/systemd/authorized_keys/profile persistence, sudo
  usage, secondary downloads) with targeted reads of every hit.
- Nothing was executed during the audit.

## Verdicts

| # | Script | Size / SHA-256 (2026-07-06) | Verdict | Notes |
|--:|:---|:---|:---|:---|
| 1 | **ip.check.place** (xykt/IPQuality) | 107 894 B `69e7a8d0…cb76c03` | ✅ CLEAN | sudo only for dep install behind a y/n prompt. ⚠️ By default uploads the finished report to `upload.check.place` and prints a public share link — **server-bench passes `-p` (privacy) to disable that**, plus `-y` to auto-confirm deps. Menu items can relaunch sibling Check.Place scripts (same author). |
| 2 | **ipregion.xyz** (Davoyan fork of vernette/ipregion) | 55 787 B `17eb73e7…f06b4e` | ✅ CLEAN | Our primary. Fork *removes* upstream's 0x0.st result-upload (more private) and adds sudo dep-install behind a y/N prompt. POSTs are per-service geo queries (e.g. `ip=<your ip>` to iplocation.com) — inherent to what it does. |
| 3 | **ipregion** (vernette, GitHub — fallback) | 50 185 B `23c79238…f371e25a8` | ✅ CLEAN | Same as above; contains a 0x0.st paste-upload code path (share feature). Only used if ipregion.xyz is down. |
| 4 | **censorcheck** (vernette) | 27 396 B `48c908ce…3991cdd` | ✅ CLEAN | Full read. mktemp-only writes, sudo only after explicit y/N, DNS-answer injection guarded. OPSEC note: by design it probes known-censored domains — from a RU vantage point that traffic itself is visible to the ISP. |
| 5 | **bench.sh** (teddysun) | 17 564 B `fbc7d7ec…974ae04` | ✅ CLEAN | Byte-identical to canonical GitHub master. Caveats: Ookla speedtest binary fetched **without checksum** and with `--no-check-certificate`; geo lookups to ipinfo.io over plain HTTP. |
| 6 | **speed.tlab.pw** (tracerlab) | 16 006 B `cf86221c…6e08073` | ✅ CLEAN | Honest teddysun fork with EU/RU-adjacent Ookla server list. Same unchecksummed-binary caveat as upstream. No prompts. |
| 7 | **bench.tlab.pw** (tracerlab) | 19 883 B `a02ff383…ac38853` | ✅ CLEAN | RU-provider speed test via iperf3 (SPB Er-Telecom, Moscow MTS, Omsk…). ⚠️ Silently installs a static iperf3 (github.com/userdocs/iperf3-static, unchecksummed) to `/usr/local/bin/iperf3` when run as root — a persistent (benign) system write. |
| 8 | **bench.gig.ovh** | root = HTML info page | ➖ N/A | The root URL no longer serves a script (server-bench detects HTML and skips to the mirror). Its hosted scripts were scanned anyway: `checker.sh` 23 205 B `3b477c6e…13d400e` and `multi_check_ru.sh` 288 772 B `eb3a95e9…2716963` — service/region checkers, mechanically clean (no writes, no persistence, streaming-API POSTs with public hardcoded tokens, lmc999 style). |
| 9 | **checker_inst.sh** (bench.openode.xyz) | 12 696 B `776b4d44…28b903ff` | ✅ CLEAN | Full read. RU-localized trim of lmc999/RegionRestrictionCheck (Instagram audio only). Caveats: silently apt/yum-installs python/dnsutils if missing (as root); a Debian 10/11 detection bug can run the Instagram request with relaxed TLS (`-k`, SECLEVEL=1); all users share the same hardcoded browser cookies. |
| 10 | **yabs.sh** (masonr) | 49 954 B `389a0726…3443a069` | ✅ CLEAN | Byte-identical to GitHub master. Caveats: **Geekbench uploads system specs to browser.geekbench.com by default** (public results page; yabs `-g` skips it); own IP shown to ip6.me / ip-api.com over plain HTTP; fio/iperf3/Geekbench binaries fetched without checksums. |

## Common findings (the honest picture)

- **No backdoors, no exfiltration of secrets**: none of the scripts read
  env vars, SSH keys, shell history or files for transmission; none touch
  cron/systemd/rc.local/authorized_keys/shell profiles; no reverse shells,
  no obfuscated payloads.
- The **systemic weakness** of the whole genre: helper binaries (Ookla
  speedtest, iperf3, fio, Geekbench) are downloaded **without checksum
  verification** — trust rests on TLS and the upstream repo. If your threat
  model can't accept that, run local modules only (`--info --disk --network
  --security --docker`).
- Your **public IP is inherently disclosed** to geo/測 services
  (ipinfo.io, ip-api.com, Ookla…) — that's what these tools are for. Some
  use plain HTTP for it.
- Result-upload defaults are the other thing to watch: server-bench
  disables IP.Check.Place's report upload with `-p`; YABS still uploads
  Geekbench results by design (opt-in module).

*Re-audit hint: fetch an upstream, `sha256sum` it, compare with the table;
if it changed, diff before trusting.*
