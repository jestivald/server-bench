#!/usr/bin/env bash
# shellcheck disable=SC2059,SC2317,SC2329,SC1091
# ╔══════════════════════════════════════════════════════════════╗
# ║  Server Benchmark Suite v2.1                                 ║
# ║  All-in-one server diagnostics & performance testing        ║
# ╚══════════════════════════════════════════════════════════════╝
#
# Usage: bash server-bench.sh [options]
#   --all         Run all tests (default)
#   --quick       Quick: info + network + security + docker
#   --info        System info + CPU bench
#   --disk        Disk benchmark (fio, dd fallback)
#   --network     Ping / DNS / TCP-stack checks
#   --security    Security audit
#   --docker      Docker status
#   --ip          IP quality + region checks
#   --speed       Speed tests (RU + international)
#   --speed-ru    Speed test to Russian providers only
#   --speed-int   Speed test to international providers only
#   --instagram   Instagram audio block check
#   --dpi         DPI censorship check (for RU servers)
#   --yabs        YABS (fio + iperf3 + Geekbench 6)
#   --live        Stream test output live (default for single-module runs)
#   --report      Progress checklist + structured report at the end
#                 (default for multi-module runs on a terminal)
#   --json        Machine-readable output (local modules only)
#   --hide-ip     Mask public IPs in output (for public pastes)
#   --no-install  Never install packages, degrade gracefully
#   --no-color    Disable colored output (also honors NO_COLOR)
#   --version     Print version
#   --help        Show help
#
# Author: jestivald (generated with Claude)
# License: MIT

VERSION="2.1.0"

set -u

# ═══════════════════════════════════════════════════════════════
# GLOBAL STATE
# ═══════════════════════════════════════════════════════════════
FAILS=0
WARNS=0
JSON_MODE=0
HIDE_IP=0
NO_INSTALL=0
USE_COLOR=1
APT_UPDATED=0
TMPDIR=""
DISK_FILE=""
declare -a JSON_KV=()
declare -a MODULE_TIMES=()

# report mode (progress checklist + structured report at the end)
LIVE_MODE=0
FORCE_REPORT=0
REPORT_MODE=0
REPORT_FILE=""
TICK_PID=""
TOTAL_MODULES=0
DONE_MODULES=0
declare -a DONE_TITLES=()

# Color vars (filled by init_colors)
RED='' GREEN='' YELLOW='' BLUE='' CYAN='' WHITE='' GRAY=''
BOLD='' DIM='' RESET=''
CHECK='✔' CROSS='✘' WARN_S='⚠' INFO_S='ℹ'
TERM_WIDTH=70

# ═══════════════════════════════════════════════════════════════
# PRIVILEGE HANDLING (root / passwordless sudo / interactive sudo)
# ═══════════════════════════════════════════════════════════════
declare -a SUDO_CMD=()
if [[ ${EUID:-$(id -u)} -ne 0 ]] && command -v sudo &>/dev/null; then
    if sudo -n true 2>/dev/null; then
        SUDO_CMD=(sudo -n)      # passwordless — never prompts
    elif [[ -t 0 && -t 1 ]]; then
        SUDO_CMD=(sudo)         # interactive terminal — may prompt once
    fi
    # neither: run unprivileged, privileged checks degrade gracefully
fi

can_priv() {
    [[ ${EUID:-$(id -u)} -eq 0 || ${#SUDO_CMD[@]} -gt 0 ]]
}

run_priv() {
    if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
        "$@"
    elif [[ ${#SUDO_CMD[@]} -gt 0 ]]; then
        "${SUDO_CMD[@]}" "$@"
    else
        return 1
    fi
}

# ═══════════════════════════════════════════════════════════════
# OUTPUT HELPERS
# ═══════════════════════════════════════════════════════════════
init_colors() {
    # colors only on a terminal, unless disabled
    if [[ $USE_COLOR -eq 1 && -t 1 && -z "${NO_COLOR:-}" ]]; then
        RED=$'\033[0;31m'    GREEN=$'\033[0;32m'  YELLOW=$'\033[1;33m'
        BLUE=$'\033[0;34m'   CYAN=$'\033[0;36m'
        WHITE=$'\033[1;37m'  GRAY=$'\033[0;90m'
        BOLD=$'\033[1m'      DIM=$'\033[2m'       RESET=$'\033[0m'
    fi
    CHECK="${GREEN}✔${RESET}"
    CROSS="${RED}✘${RESET}"
    WARN_S="${YELLOW}⚠${RESET}"
    INFO_S="${BLUE}ℹ${RESET}"

    TERM_WIDTH=$(tput cols 2>/dev/null) || TERM_WIDTH=70
    [[ -z "$TERM_WIDTH" ]] && TERM_WIDTH=70
    [[ $TERM_WIDTH -gt 80 ]] && TERM_WIDTH=80
}

repeat_char() {
    local pad
    printf -v pad '%*s' "$TERM_WIDTH" ''
    printf '%s' "${pad// /$1}"
}

line() {
    printf '%s%s%s\n' "$GRAY" "$(repeat_char '─')" "$RESET"
}

double_line() {
    printf '%s%s%s\n' "$BLUE" "$(repeat_char '═')" "$RESET"
}

header() {
    echo ""
    double_line
    printf "${BOLD}${WHITE}  %s${RESET}\n" "$1"
    [[ -n "${2:-}" ]] && printf "${DIM}${GRAY}  %s${RESET}\n" "$2"
    double_line
}

section() {
    echo ""
    printf "${BOLD}${CYAN}  ┌─ %s${RESET}\n" "$1"
    line
}

kv() {
    # key-value pair: kv "Label" "Value" [color]
    local color="${3:-$WHITE}"
    printf "  ${GRAY}%-22s${RESET} ${color}%s${RESET}\n" "$1" "$2"
}

status_ok()   { printf "  ${CHECK} %s\n" "$1"; }
status_fail() { printf "  ${CROSS} %s\n" "$1"; FAILS=$((FAILS + 1)); }
status_warn() { printf "  ${WARN_S} %s\n" "$1"; WARNS=$((WARNS + 1)); }
status_info() { printf "  ${INFO_S} %s\n" "$1"; }

# Run a command silently with a spinner; output captured to a file.
# usage: run_quiet "message" /path/outfile cmd [args...]
run_quiet() {
    local msg="$1" out="$2"
    shift 2
    "$@" >"$out" 2>&1 &
    local pid=$!
    if [[ -t 1 ]]; then
        local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏') i=0
        while kill -0 "$pid" 2>/dev/null; do
            printf "\r  ${CYAN}%s${RESET} ${DIM}%s${RESET}" "${frames[$i]}" "$msg"
            i=$(( (i + 1) % 10 ))
            sleep 0.12
        done
        printf '\r%*s\r' "$TERM_WIDTH" ' '
    else
        printf '  … %s\n' "$msg"
        wait "$pid" 2>/dev/null
        return $?
    fi
    wait "$pid" 2>/dev/null
}

# ═══════════════════════════════════════════════════════════════
# PROGRESS TICKER (report mode)
# ═══════════════════════════════════════════════════════════════
start_ticker() {
    # start_ticker "title" done_count total — animated progress line
    local title="$1" done_n="$2" total="$3"
    if [[ ! -t 1 ]]; then
        printf '  … %s — running...\n' "$title"
        return 0
    fi
    (
        local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
        local i=0 t=0 pct fill bar="" j secs
        pct=$(( done_n * 100 / total ))
        fill=$(( done_n * 24 / total ))
        for (( j = 0; j < 24; j++ )); do
            if (( j < fill )); then bar+="█"; else bar+="░"; fi
        done
        while :; do
            secs=$(( t / 5 ))
            printf '\r  %s%s%s [%s] %3d%%  %s►%s %-11s %dm %02ds ' \
                "$CYAN" "${frames[$i]}" "$RESET" "$bar" "$pct" \
                "$YELLOW" "$RESET" "$title" $(( secs / 60 )) $(( secs % 60 ))
            i=$(( (i + 1) % 10 ))
            t=$(( t + 1 ))
            sleep 0.2
        done
    ) &
    TICK_PID=$!
}

stop_ticker() {
    if [[ -n "$TICK_PID" ]]; then
        kill "$TICK_PID" 2>/dev/null
        wait "$TICK_PID" 2>/dev/null
        TICK_PID=""
    fi
    [[ -t 1 ]] && printf '\r%*s\r' "$TERM_WIDTH" ' '
    return 0
}

# ═══════════════════════════════════════════════════════════════
# JSON OUTPUT (--json, local modules only)
# ═══════════════════════════════════════════════════════════════
record() {
    # record key value [num]
    [[ $JSON_MODE -eq 1 ]] || return 0
    local k="$1" v="${2:-}" t="${3:-str}"
    if [[ "$t" == "num" ]]; then
        if [[ "$v" =~ ^-?[0-9]+([.][0-9]+)?$ ]]; then
            JSON_KV+=("\"$k\":$v")
        else
            JSON_KV+=("\"$k\":null")
        fi
    else
        v=${v//\\/\\\\}
        v=${v//\"/\\\"}
        v=${v//$'\n'/ }
        v=${v//$'\t'/ }
        JSON_KV+=("\"$k\":\"$v\"")
    fi
}

emit_json() {
    local IFS=','
    printf '{%s}\n' "${JSON_KV[*]-}" >&3
}

# ═══════════════════════════════════════════════════════════════
# MISC HELPERS
# ═══════════════════════════════════════════════════════════════
command_exists() {
    command -v "$1" &>/dev/null
}

cleanup() {
    [[ -n "$TICK_PID" ]] && kill "$TICK_PID" 2>/dev/null
    [[ -n "$TMPDIR" ]] && rm -rf "$TMPDIR"
    [[ -n "$DISK_FILE" ]] && rm -f "$DISK_FILE"
    return 0
}

strip_ansi() {
    sed -e $'s/\x1b\\[[0-9;]*[a-zA-Z]//g' -e 's/\r$//' -e 's/\r/\n/g'
}

mod_log() {
    printf '%s/mod_%s.log' "$TMPDIR" "$1"
}

mask_ip() {
    local ip="${1:-}"
    [[ $HIDE_IP -eq 1 ]] || { printf '%s' "$ip"; return; }
    if [[ "$ip" == *:* ]]; then
        printf '%s' "$(printf '%s' "$ip" | awk -F: '{print $1":"$2"::xxxx"}')"
    elif [[ "$ip" == *.* ]]; then
        printf '%s' "$(printf '%s' "$ip" | awk -F. '{print $1"."$2".x.x"}')"
    else
        printf '%s' "$ip"
    fi
}

# ═══════════════════════════════════════════════════════════════
# DEPENDENCIES (lazy, per selected modules)
# ═══════════════════════════════════════════════════════════════
PM=""
detect_pm() {
    local p
    for p in apt-get dnf yum; do
        if command_exists "$p"; then PM="$p"; return 0; fi
    done
    return 1
}

pkg_for() {
    # map command -> package name for the detected package manager
    local c="$1"
    case "$PM" in
        apt-get)
            case "$c" in
                dig)  echo "dnsutils" ;;
                ping) echo "iputils-ping" ;;
                *)    echo "$c" ;;
            esac ;;
        dnf|yum)
            case "$c" in
                dig)  echo "bind-utils" ;;
                ping) echo "iputils" ;;
                *)    echo "$c" ;;
            esac ;;
        *) echo "$c" ;;
    esac
}

pm_install() {
    local pkg="$1"
    case "$PM" in
        apt-get)
            if [[ $APT_UPDATED -eq 0 ]]; then
                run_quiet "Updating package list..." "$TMPDIR/apt.log" \
                    run_priv env DEBIAN_FRONTEND=noninteractive apt-get update -qq || true
                APT_UPDATED=1
            fi
            run_priv env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "$pkg" &>/dev/null ;;
        dnf) run_priv dnf install -y -q "$pkg" &>/dev/null ;;
        yum) run_priv yum install -y -q "$pkg" &>/dev/null ;;
        *)   return 1 ;;
    esac
}

ensure_deps() {
    # ensure_deps cmd [cmd...] — install what's missing, warn on failure
    local missing=() c
    for c in "$@"; do
        command_exists "$c" || missing+=("$c")
    done
    [[ ${#missing[@]} -eq 0 ]] && return 0

    if [[ $NO_INSTALL -eq 1 ]]; then
        status_warn "Missing tools (skipped install, --no-install): ${missing[*]}"
        return 0
    fi
    if ! can_priv; then
        status_warn "Missing tools (need root/sudo to install): ${missing[*]}"
        return 0
    fi
    if ! detect_pm; then
        status_warn "Missing tools (unsupported package manager): ${missing[*]}"
        return 0
    fi

    status_info "Installing missing tools: ${missing[*]}"
    for c in "${missing[@]}"; do
        local pkg
        pkg=$(pkg_for "$c")
        run_quiet "Installing ${pkg}..." "$TMPDIR/install_${c}.log" pm_install "$pkg" || true
        if command_exists "$c"; then
            status_ok "${pkg} installed"
        else
            status_warn "Could not install ${pkg} (test will degrade or be skipped)"
        fi
    done
}

# ═══════════════════════════════════════════════════════════════
# EXTERNAL SCRIPT RUNNER (fetch first, then execute with timeout)
# ═══════════════════════════════════════════════════════════════
run_external() {
    # run_external "label" timeout_sec url [args...]
    # returns 1 only when FETCH failed (caller may try a mirror);
    # a timed-out or partially-failed run is reported but not retried.
    local label="$1" tmo="$2" url="$3"
    shift 3
    local body
    status_info "Fetching ${label}..."
    if ! body=$(curl -fsSL --connect-timeout 10 --max-time 60 "$url" 2>/dev/null) || [[ -z "$body" ]]; then
        status_warn "${label}: could not fetch script"
        return 1
    fi
    echo ""
    timeout --foreground -k 15 "$tmo" bash <(printf '%s\n' "$body") "$@" </dev/null
    local rc=$?
    case $rc in
        0) return 0 ;;
        124|137) status_fail "${label}: timed out after ${tmo}s" ;;
        *)       status_warn "${label}: exited with code ${rc}" ;;
    esac
    return 0
}

# ═══════════════════════════════════════════════════════════════
# BANNER
# ═══════════════════════════════════════════════════════════════
show_banner() {
    echo ""
    printf "${BOLD}${CYAN}"
    printf '   %s\n' \
        '╔═╗┌─┐┬─┐┬  ┬┌─┐┬─┐  ╔╗ ┌─┐┌┐┌┌─┐┬ ┬' \
        '╚═╗├┤ ├┬┘└┐┌┘├┤ ├┬┘  ╠╩╗├┤ ││││  ├─┤' \
        '╚═╝└─┘┴└─ └┘ └─┘┴└─  ╚═╝└─┘┘└┘└─┘┴ ┴'
    printf "${RESET}"
    printf "${DIM}${GRAY}   v%s • all-in-one server diagnostics • %s${RESET}\n" \
        "$VERSION" "$(date '+%Y-%m-%d %H:%M:%S %Z')"
    echo ""
}

# ═══════════════════════════════════════════════════════════════
# SYSTEM INFO
# ═══════════════════════════════════════════════════════════════
test_system_info() {
    header "SYSTEM INFORMATION" "Hardware, OS & network configuration"

    # OS
    section "Operating System"
    local os_name=""
    if [[ -f /etc/os-release ]]; then
        # subshell: do not pollute our vars (os-release sets VERSION, NAME, ...)
        os_name=$(. /etc/os-release 2>/dev/null; echo "${PRETTY_NAME:-${NAME:-} ${VERSION:-}}")
    fi
    [[ -z "$os_name" ]] && os_name="Unknown"
    kv "OS:" "$os_name" "$GREEN"
    kv "Kernel:" "$(uname -r)"
    kv "Arch:" "$(uname -m)"
    kv "Hostname:" "$(hostname 2>/dev/null || echo "${HOSTNAME:-?}")"
    kv "Uptime:" "$(uptime -p 2>/dev/null || uptime 2>/dev/null | sed 's/.*up //; s/,.*//')"

    local virt="unknown"
    if command_exists systemd-detect-virt; then
        virt=$(systemd-detect-virt 2>/dev/null || echo "none")
    elif grep -q '^flags.*hypervisor' /proc/cpuinfo 2>/dev/null; then
        virt="vm (unknown)"
    fi
    kv "Virtualization:" "$virt"
    record "os" "$os_name"
    record "kernel" "$(uname -r)"
    record "arch" "$(uname -m)"
    record "virt" "$virt"

    # CPU
    section "CPU"
    local cpu_model cpu_cores cpu_freq aes="no"
    cpu_model=$(awk -F': ' '/^model name/{print $2; exit}' /proc/cpuinfo 2>/dev/null)
    [[ -z "$cpu_model" ]] && cpu_model="Unknown"
    cpu_cores=$(nproc 2>/dev/null || grep -c ^processor /proc/cpuinfo 2>/dev/null || echo "?")
    cpu_freq=$(awk -F': ' '/^cpu MHz/{printf "%.0f", $2; exit}' /proc/cpuinfo 2>/dev/null)
    grep -qm1 -w aes /proc/cpuinfo 2>/dev/null && aes="yes"
    kv "Model:" "$cpu_model" "$YELLOW"
    kv "Cores:" "$cpu_cores"
    [[ -n "$cpu_freq" ]] && kv "Frequency:" "${cpu_freq} MHz"
    if [[ "$aes" == "yes" ]]; then
        kv "AES-NI:" "yes" "$GREEN"
    else
        kv "AES-NI:" "no (crypto workloads will be slow)" "$YELLOW"
    fi
    kv "Load average:" "$(cut -d' ' -f1-3 /proc/loadavg 2>/dev/null || echo '?')"
    record "cpu_model" "$cpu_model"
    record "cpu_cores" "$cpu_cores" num
    record "cpu_mhz" "${cpu_freq:-}" num
    record "cpu_aes" "$aes"

    # CPU steal (1s sample) — how much the hypervisor takes from you
    if [[ -r /proc/stat ]]; then
        local t1 s1 t2 s2 steal
        read -r t1 s1 < <(awk '/^cpu /{print $2+$3+$4+$5+$6+$7+$8+$9, $9}' /proc/stat)
        sleep 1
        read -r t2 s2 < <(awk '/^cpu /{print $2+$3+$4+$5+$6+$7+$8+$9, $9}' /proc/stat)
        steal=$(awk -v a=$((s2 - s1)) -v b=$((t2 - t1)) 'BEGIN{if (b > 0) printf "%.1f", a * 100 / b; else print "0.0"}')
        local steal_int=${steal%.*}
        if [[ ${steal_int:-0} -ge 10 ]]; then
            kv "CPU steal:" "${steal}% (oversold host!)" "$RED"
        elif [[ ${steal_int:-0} -ge 3 ]]; then
            kv "CPU steal:" "${steal}% (noticeable)" "$YELLOW"
        else
            kv "CPU steal:" "${steal}%" "$GREEN"
        fi
        record "cpu_steal_pct" "$steal" num
    fi

    # CPU quick bench
    if command_exists sysbench; then
        section "CPU Benchmark (sysbench)"
        local out eps_1t eps_mt
        run_quiet "Running sysbench CPU test (1 thread, 10s)..." "$TMPDIR/sb1.log" \
            sysbench cpu run --threads=1
        eps_1t=$(awk '/events per second/{print $NF}' "$TMPDIR/sb1.log")
        if [[ -n "$eps_1t" ]]; then
            kv "Single-thread:" "${eps_1t} events/sec" "$YELLOW"
            record "cpu_eps_1t" "$eps_1t" num
            local eps_int=${eps_1t%.*}
            if [[ ${eps_int:-0} -gt 3000 ]]; then
                status_ok "Excellent CPU performance (dedicated core likely)"
            elif [[ ${eps_int:-0} -gt 1500 ]]; then
                status_ok "Good CPU performance"
            elif [[ ${eps_int:-0} -gt 800 ]]; then
                status_warn "Average CPU (shared/throttled?)"
            else
                status_fail "Low CPU performance (heavily shared)"
            fi
        else
            status_warn "sysbench produced no result"
        fi
        if [[ "${cpu_cores:-1}" =~ ^[0-9]+$ ]] && [[ $cpu_cores -gt 1 ]]; then
            run_quiet "Running sysbench CPU test (${cpu_cores} threads, 10s)..." "$TMPDIR/sbn.log" \
                sysbench cpu run --threads="$cpu_cores"
            eps_mt=$(awk '/events per second/{print $NF}' "$TMPDIR/sbn.log")
            if [[ -n "$eps_mt" ]]; then
                kv "Multi-thread:" "${eps_mt} events/sec (${cpu_cores} threads)" "$YELLOW"
                record "cpu_eps_mt" "$eps_mt" num
            fi
        fi
    else
        status_warn "sysbench not available — CPU benchmark skipped"
    fi

    # Memory
    section "Memory"
    kv "Total:" "$(free -h 2>/dev/null | awk '/^Mem:/{print $2}')" "$YELLOW"
    kv "Used:" "$(free -h 2>/dev/null | awk '/^Mem:/{print $3}')"
    kv "Available:" "$(free -h 2>/dev/null | awk '/^Mem:/{print $7}')" "$GREEN"
    kv "Swap:" "$(free -h 2>/dev/null | awk '/^Swap:/{print $2}')"
    record "mem_total_mb" "$(free -m 2>/dev/null | awk '/^Mem:/{print $2}')" num
    record "mem_avail_mb" "$(free -m 2>/dev/null | awk '/^Mem:/{print $7}')" num
    record "swap_total_mb" "$(free -m 2>/dev/null | awk '/^Swap:/{print $2}')" num

    # Disk usage
    section "Disk Usage"
    printf "  ${GRAY}%-20s %-8s %-8s %-8s %-6s${RESET}\n" "MOUNT" "SIZE" "USED" "AVAIL" "USE%"
    line
    df -h --output=target,size,used,avail,pcent 2>/dev/null \
        | grep -vE '^Mounted|tmpfs|devtmpfs|udev|efivarfs' \
        | while read -r mount size used avail pct; do
            local pct_num=${pct%\%}
            local color="$GREEN"
            [[ ${pct_num:-0} -gt 70 ]] 2>/dev/null && color="$YELLOW"
            [[ ${pct_num:-0} -gt 90 ]] 2>/dev/null && color="$RED"
            printf "  ${WHITE}%-20s${RESET} %-8s %-8s %-8s ${color}%-6s${RESET}\n" \
                "$mount" "$size" "$used" "$avail" "$pct"
        done
    record "disk_root_used_pct" "$(df --output=pcent / 2>/dev/null | tail -1 | tr -dc '0-9')" num

    # Public IPs & geo
    section "Network"
    local ipv4 ipv6
    ipv4=$(curl -4 -fsS --max-time 5 https://ifconfig.me 2>/dev/null \
        || curl -4 -fsS --max-time 5 https://icanhazip.com 2>/dev/null || echo "N/A")
    ipv6=$(curl -6 -fsS --max-time 5 https://ifconfig.me 2>/dev/null \
        || curl -6 -fsS --max-time 5 https://icanhazip.com 2>/dev/null || echo "N/A")
    ipv4=$(printf '%s' "$ipv4" | tr -d '[:space:]')
    ipv6=$(printf '%s' "$ipv6" | tr -d '[:space:]')
    kv "IPv4:" "$(mask_ip "$ipv4")" "$YELLOW"
    kv "IPv6:" "$(mask_ip "${ipv6:-N/A}")"
    record "ipv4" "$(mask_ip "$ipv4")"
    record "ipv6" "$(mask_ip "${ipv6:-N/A}")"

    if [[ "$ipv4" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        local geo
        geo=$(curl -fsS --max-time 5 "http://ip-api.com/line/${ipv4}?fields=country,regionName,city,isp,as" 2>/dev/null)
        if [[ -n "$geo" ]]; then
            local country city isp asn
            country=$(sed -n '1p' <<<"$geo")
            city=$(sed -n '3p' <<<"$geo")
            isp=$(sed -n '4p' <<<"$geo")
            asn=$(sed -n '5p' <<<"$geo")
            kv "Location:" "${city:-?}, ${country:-?}"
            kv "ISP:" "${isp:-?}"
            kv "AS:" "${asn:-?}"
            record "geo_country" "$country"
            record "geo_city" "$city"
            record "isp" "$isp"
            record "asn" "$asn"
        fi
        if command_exists dig; then
            local rdns
            rdns=$(dig +short +time=3 +tries=1 -x "$ipv4" 2>/dev/null | head -1)
            [[ -n "$rdns" ]] && kv "rDNS:" "$rdns" && record "rdns" "$rdns"
        fi
    fi
}

# ═══════════════════════════════════════════════════════════════
# DISK BENCHMARK (fio primary, dd fallback)
# ═══════════════════════════════════════════════════════════════
pick_disk_dir() {
    # find a writable, disk-backed (non-tmpfs) directory with enough space
    local d fstype avail_kb
    for d in "$PWD" "${HOME:-/root}" /var/tmp /tmp; do
        [[ -d "$d" && -w "$d" ]] || continue
        fstype=$(df --output=fstype "$d" 2>/dev/null | tail -1 | tr -d ' ')
        case "$fstype" in
            tmpfs|ramfs) continue ;;
        esac
        avail_kb=$(df --output=avail "$d" 2>/dev/null | tail -1 | tr -d ' ')
        [[ "${avail_kb:-0}" =~ ^[0-9]+$ ]] || continue
        printf '%s\t%s\t%s\n' "$d" "$fstype" "$avail_kb"
        return 0
    done
    return 1
}

terse_field() {
    # terse_field N file — field N of the last terse v3 line
    awk -F';' -v n="$1" 'END{print $n}' "$2" 2>/dev/null
}

kb_to_mb() {
    awk -v k="${1:-0}" 'BEGIN{printf "%.1f", k / 1024}'
}

fmt_iops() {
    awk -v i="${1:-0}" 'BEGIN{if (i >= 1000) printf "%.1fk", i / 1000; else printf "%.0f", i}'
}

fio_job() {
    # fio_job "message" outfile [fio-args...] — direct=1, buffered retry
    local msg="$1" out="$2"
    shift 2
    run_quiet "$msg" "$out" env LC_ALL=C fio --output-format=terse --terse-version=3 \
        --name=bench --filename="$DISK_FILE" --direct=1 --ioengine="$FIO_ENG" "$@"
    grep -q '^3;' "$out" 2>/dev/null && return 0
    # O_DIRECT unsupported on this fs? retry buffered
    run_quiet "$msg (buffered)" "$out" env LC_ALL=C fio --output-format=terse --terse-version=3 \
        --name=bench --filename="$DISK_FILE" --direct=0 --ioengine="$FIO_ENG" "$@"
    grep -q '^3;' "$out" 2>/dev/null
}

test_disk() {
    header "DISK BENCHMARK" "Sequential & random I/O performance"

    local pick dir fstype avail_kb size_mb=512
    if ! pick=$(pick_disk_dir); then
        status_fail "No writable disk-backed directory found — disk test skipped"
        return 0
    fi
    IFS=$'\t' read -r dir fstype avail_kb <<<"$pick"

    if   [[ $avail_kb -ge $((1200 * 1024)) ]]; then size_mb=512
    elif [[ $avail_kb -ge  $((600 * 1024)) ]]; then size_mb=256
    elif [[ $avail_kb -ge  $((350 * 1024)) ]]; then size_mb=128; status_warn "Low free space — using a small ${size_mb}MB test file"
    else
        status_fail "Not enough free space in ${dir} ($(( avail_kb / 1024 ))MB) — disk test skipped"
        return 0
    fi

    DISK_FILE="${dir%/}/.server-bench-fio.$$"
    kv "Test path:" "${dir} (${fstype}, ${size_mb}MB file)"
    record "disk_test_path" "$dir"
    record "disk_test_fs" "$fstype"

    if command_exists fio; then
        FIO_ENG="psync"
        fio --enghelp 2>/dev/null | grep -qw libaio && FIO_ENG="libaio"

        section "Sequential (fio, 1M blocks)"
        local bw
        if fio_job "Sequential write (${size_mb}MB)..." "$TMPDIR/fio_sw.log" \
                --rw=write --bs=1M --iodepth=8 --size="${size_mb}M" --runtime=60; then
            bw=$(terse_field 48 "$TMPDIR/fio_sw.log")
            kv "Sequential Write:" "$(kb_to_mb "$bw") MB/s" "$YELLOW"
            record "disk_seq_write_mbs" "$(kb_to_mb "$bw")" num
        else
            status_fail "fio sequential write failed"
        fi
        if fio_job "Sequential read (${size_mb}MB)..." "$TMPDIR/fio_sr.log" \
                --rw=read --bs=1M --iodepth=8 --size="${size_mb}M" --runtime=30; then
            bw=$(terse_field 7 "$TMPDIR/fio_sr.log")
            kv "Sequential Read:" "$(kb_to_mb "$bw") MB/s" "$YELLOW"
            record "disk_seq_read_mbs" "$(kb_to_mb "$bw")" num
        else
            status_fail "fio sequential read failed"
        fi

        section "Random 4K (fio, iodepth 32, 10s each)"
        local iops
        if fio_job "4K random read..." "$TMPDIR/fio_rr.log" \
                --rw=randread --bs=4k --iodepth=32 --size="${size_mb}M" --runtime=10; then
            iops=$(terse_field 8 "$TMPDIR/fio_rr.log")
            bw=$(terse_field 7 "$TMPDIR/fio_rr.log")
            kv "4K Random Read:" "$(fmt_iops "$iops") IOPS ($(kb_to_mb "$bw") MB/s)" "$YELLOW"
            record "disk_rand_read_iops" "${iops%%.*}" num
        else
            status_fail "fio random read failed"
        fi
        if fio_job "4K random write..." "$TMPDIR/fio_rw.log" \
                --rw=randwrite --bs=4k --iodepth=32 --size="${size_mb}M" --runtime=10; then
            iops=$(terse_field 49 "$TMPDIR/fio_rw.log")
            bw=$(terse_field 48 "$TMPDIR/fio_rw.log")
            kv "4K Random Write:" "$(fmt_iops "$iops") IOPS ($(kb_to_mb "$bw") MB/s)" "$YELLOW"
            record "disk_rand_write_iops" "${iops%%.*}" num
        else
            status_fail "fio random write failed"
        fi
    else
        # dd fallback: /dev/zero is compressible — take results with a grain
        # of salt on ZFS/thin-provisioned storage
        section "Sequential (dd fallback — install fio for accurate numbers)"
        local out speed
        if run_quiet "Writing ${size_mb}MB (direct I/O)..." "$TMPDIR/dd_w.log" \
                env LC_ALL=C dd if=/dev/zero of="$DISK_FILE" bs=1M count="$size_mb" oflag=direct conv=fdatasync \
            || run_quiet "Writing ${size_mb}MB (fdatasync)..." "$TMPDIR/dd_w.log" \
                env LC_ALL=C dd if=/dev/zero of="$DISK_FILE" bs=1M count="$size_mb" conv=fdatasync; then
            speed=$(tail -n1 "$TMPDIR/dd_w.log" | awk '{print $(NF-1), $NF}')
            kv "Sequential Write:" "$speed" "$YELLOW"
        else
            status_fail "dd write test failed"
        fi
        if [[ -f "$DISK_FILE" ]]; then
            if run_quiet "Reading ${size_mb}MB (direct I/O)..." "$TMPDIR/dd_r.log" \
                    env LC_ALL=C dd if="$DISK_FILE" of=/dev/null bs=1M iflag=direct \
                || run_quiet "Reading ${size_mb}MB..." "$TMPDIR/dd_r.log" \
                    env LC_ALL=C dd if="$DISK_FILE" of=/dev/null bs=1M; then
                speed=$(tail -n1 "$TMPDIR/dd_r.log" | awk '{print $(NF-1), $NF}')
                kv "Sequential Read:" "$speed" "$YELLOW"
            else
                status_fail "dd read test failed"
            fi
        fi
    fi

    rm -f "$DISK_FILE"
    DISK_FILE=""
}

# ═══════════════════════════════════════════════════════════════
# NETWORK DIAGNOSTICS (ping, DNS, TCP stack, port 25)
# ═══════════════════════════════════════════════════════════════
test_network() {
    header "NETWORK DIAGNOSTICS" "Latency, DNS & TCP stack"

    # TCP stack — matters a lot for throughput on lossy links
    section "TCP Stack"
    local cc qdisc mtu iface
    cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "?")
    qdisc=$(sysctl -n net.core.default_qdisc 2>/dev/null || echo "?")
    if [[ "$cc" == "bbr" || "$cc" == "bbr2" ]]; then
        kv "Congestion control:" "$cc" "$GREEN"
    else
        kv "Congestion control:" "$cc (consider enabling bbr)" "$YELLOW"
    fi
    case "$qdisc" in
        fq|cake|fq_codel) kv "Default qdisc:" "$qdisc" "$GREEN" ;;
        *)                kv "Default qdisc:" "$qdisc" "$YELLOW" ;;
    esac
    iface=$(ip -o route get 8.8.8.8 2>/dev/null | sed -n 's/.* dev \([^ ]*\).*/\1/p' | head -1)
    if [[ -n "$iface" && -r "/sys/class/net/$iface/mtu" ]]; then
        mtu=$(cat "/sys/class/net/$iface/mtu")
        kv "MTU ($iface):" "$mtu"
        record "mtu" "$mtu" num
    fi
    record "tcp_cc" "$cc"
    record "qdisc" "$qdisc"

    # Outbound port 25 (commonly blocked by hosters)
    local p25="blocked/filtered"
    if timeout 5 bash -c 'exec 3<>/dev/tcp/smtp.gmail.com/25' 2>/dev/null; then
        p25="open"
        kv "Outbound port 25:" "open (mail can be sent)" "$GREEN"
    else
        kv "Outbound port 25:" "blocked or filtered" "$GRAY"
    fi
    record "port25" "$p25"

    # Ping
    section "Ping Latency"
    if command_exists ping; then
        local targets=("1.1.1.1:Cloudflare" "8.8.8.8:Google" "77.88.8.8:Yandex" "208.67.222.222:OpenDNS")
        printf "  ${GRAY}%-22s %-9s %-9s %-9s %-6s${RESET}\n" "TARGET" "MIN" "AVG" "MAX" "LOSS"
        line
        local entry ip name out stats min_ms avg_ms max_ms loss perm_hint=0
        for entry in "${targets[@]}"; do
            ip="${entry%%:*}"
            name="${entry##*:}"
            out=$(ping -c 3 -W 3 "$ip" 2>&1)
            if grep -q 'not permitted' <<<"$out"; then perm_hint=1; fi
            stats=$(grep -E 'min/avg/max' <<<"$out" | grep -oE '[0-9.]+/[0-9.]+/[0-9.]+' | head -1)
            loss=$(grep -oE '[0-9.]+% packet loss' <<<"$out" | cut -d% -f1)
            if [[ -n "$stats" ]]; then
                min_ms=$(cut -d/ -f1 <<<"$stats")
                avg_ms=$(cut -d/ -f2 <<<"$stats")
                max_ms=$(cut -d/ -f3 <<<"$stats")
                local color="$GREEN" avg_int=${avg_ms%.*}
                [[ ${avg_int:-0} -gt 50 ]] && color="$YELLOW"
                [[ ${avg_int:-0} -gt 150 ]] && color="$RED"
                local loss_color="$GREEN"
                [[ "${loss%%.*}" != "0" ]] && loss_color="$RED"
                printf "  ${WHITE}%-22s${RESET} %-9s ${color}%-9s${RESET} %-9s ${loss_color}%-6s${RESET}\n" \
                    "$name ($ip)" "${min_ms}ms" "${avg_ms}ms" "${max_ms}ms" "${loss:-?}%"
                record "ping_$(tr '[:upper:]' '[:lower:]' <<<"$name")_avg_ms" "$avg_ms" num
            else
                printf "  ${WHITE}%-22s${RESET} ${RED}%s${RESET}\n" "$name ($ip)" "unreachable"
                record "ping_$(tr '[:upper:]' '[:lower:]' <<<"$name")_avg_ms" "" num
            fi
        done
        [[ $perm_hint -eq 1 ]] && status_warn "ping lacks raw-socket permission (container?) — results unreliable"
    else
        status_warn "ping not available — latency test skipped"
    fi

    # DNS
    section "DNS Resolution"
    local dns_targets=("google.com" "youtube.com" "telegram.org" "instagram.com" "cloudflare.com")
    local domain resolved dns_ms
    for domain in "${dns_targets[@]}"; do
        resolved="" dns_ms=""
        if command_exists dig; then
            local dout
            dout=$(dig +tries=1 +time=3 +noall +answer +stats "$domain" A 2>/dev/null)
            resolved=$(awk '$4 == "A" {print $5; exit}' <<<"$dout")
            dns_ms=$(sed -n 's/.*Query time: \([0-9]*\) msec.*/\1/p' <<<"$dout" | head -1)
        fi
        if [[ -z "$resolved" ]] && command_exists getent; then
            # dig missing or blocked — fall back to the system resolver
            local start_ns end_ns
            start_ns=$(date +%s%N 2>/dev/null || echo 0)
            resolved=$(getent hosts "$domain" 2>/dev/null | awk '{print $1; exit}')
            end_ns=$(date +%s%N 2>/dev/null || echo 0)
            dns_ms=$(( (end_ns - start_ns) / 1000000 ))
            [[ "$dns_ms" =~ ^[0-9]+$ ]] || dns_ms=""
        fi
        if [[ -n "$resolved" ]]; then
            local color="$GREEN"
            [[ ${dns_ms:-0} -gt 100 ]] && color="$YELLOW"
            [[ ${dns_ms:-0} -gt 500 ]] && color="$RED"
            printf "  ${CHECK} %-22s ${color}%sms${RESET}  ${DIM}→ %s${RESET}\n" "$domain" "${dns_ms:-?}" "$resolved"
            record "dns_${domain//./_}_ms" "$dns_ms" num
        else
            printf "  ${CROSS} %-22s ${RED}FAILED${RESET}\n" "$domain"
            FAILS=$((FAILS + 1))
        fi
    done
}

# ═══════════════════════════════════════════════════════════════
# SECURITY QUICK CHECK
# ═══════════════════════════════════════════════════════════════
test_security() {
    header "SECURITY QUICK CHECK" "Basic server hardening audit"

    section "SSH Configuration"
    local eff="" root_login="" pass_auth="" ssh_port=""
    # effective config (includes sshd_config.d/*.conf) — needs root
    eff=$(run_priv sshd -T 2>/dev/null | grep -E '^(permitrootlogin|passwordauthentication|port) ') || eff=""
    if [[ -n "$eff" ]]; then
        root_login=$(awk '$1 == "permitrootlogin" {print $2; exit}' <<<"$eff")
        pass_auth=$(awk '$1 == "passwordauthentication" {print $2; exit}' <<<"$eff")
        ssh_port=$(awk '$1 == "port" {print $2; exit}' <<<"$eff")
    elif [[ -r /etc/ssh/sshd_config ]]; then
        # fallback: main config + drop-in dir, first match wins
        local conf
        conf=$(cat /etc/ssh/sshd_config /etc/ssh/sshd_config.d/*.conf 2>/dev/null)
        root_login=$(awk 'tolower($1) == "permitrootlogin" {print $2; exit}' <<<"$conf")
        pass_auth=$(awk 'tolower($1) == "passwordauthentication" {print $2; exit}' <<<"$conf")
        ssh_port=$(awk 'tolower($1) == "port" {print $2; exit}' <<<"$conf")
    fi

    if [[ -n "$root_login$pass_auth$ssh_port" ]]; then
        case "$root_login" in
            no)                                  status_ok "Root login disabled" ;;
            prohibit-password|without-password)  status_ok "Root login: key only" ;;
            *)                                   status_warn "Root login: ${root_login:-default (yes)}" ;;
        esac
        if [[ "$pass_auth" == "no" ]]; then
            status_ok "Password authentication disabled"
        else
            status_warn "Password authentication: ${pass_auth:-default (yes)}"
        fi
        ssh_port=${ssh_port:-22}
        if [[ "$ssh_port" != "22" ]]; then
            status_ok "SSH port: $ssh_port (non-default)"
        else
            status_info "SSH port: 22 (default)"
        fi
        record "ssh_root_login" "${root_login:-default}"
        record "ssh_password_auth" "${pass_auth:-default}"
        record "ssh_port" "$ssh_port" num
    else
        status_info "sshd config not readable (not root?) — SSH audit skipped"
    fi

    # Firewall
    section "Firewall"
    local fw="none"
    if command_exists ufw; then
        if run_priv ufw status 2>/dev/null | head -1 | grep -q "active"; then
            status_ok "UFW: active"
            fw="ufw-active"
        else
            status_warn "UFW: inactive"
            fw="ufw-inactive"
        fi
    elif command_exists nft && run_priv nft list ruleset &>/dev/null; then
        local nft_rules
        nft_rules=$(run_priv nft list ruleset 2>/dev/null | grep -c '^\s*chain') || nft_rules=0
        kv "nftables chains:" "$nft_rules"
        fw="nftables-$nft_rules"
    elif command_exists iptables; then
        local rules_count
        rules_count=$(run_priv iptables -S 2>/dev/null | grep -c '^-A') || rules_count=0
        kv "iptables rules:" "$rules_count"
        fw="iptables-$rules_count"
    else
        status_info "No firewall tooling detected"
    fi
    record "firewall" "$fw"

    # Fail2ban
    section "Intrusion Prevention"
    local f2b="no"
    if command_exists fail2ban-client; then
        local jails
        jails=$(run_priv fail2ban-client status 2>/dev/null | awk -F: '/Number of jail/{gsub(/ /, "", $2); print $2}')
        if [[ -n "$jails" ]]; then
            status_ok "Fail2ban: active (${jails} jails)"
            f2b="yes"
        elif systemctl is-active fail2ban &>/dev/null; then
            status_ok "Fail2ban: active"
            f2b="yes"
        else
            status_warn "Fail2ban installed but not running"
        fi
    else
        status_warn "Fail2ban not installed"
    fi
    record "fail2ban" "$f2b"

    # Updates
    section "Pending Updates"
    if command_exists apt; then
        local updates
        updates=$(apt list --upgradable 2>/dev/null | grep -c "upgradable") || updates=0
        if [[ ${updates:-0} -gt 0 ]]; then
            status_warn "$updates packages can be updated"
        else
            status_ok "System is up to date"
        fi
        record "pending_updates" "$updates" num
    else
        status_info "Update check: apt-based systems only"
    fi
}

# ═══════════════════════════════════════════════════════════════
# DOCKER STATUS
# ═══════════════════════════════════════════════════════════════
test_docker() {
    header "DOCKER STATUS" "Running containers & resource usage"

    if ! command_exists docker; then
        status_info "Docker not installed"
        record "docker_running" "" num
        return 0
    fi
    if ! docker info &>/dev/null; then
        status_warn "Docker installed but daemon unreachable (permissions?)"
        return 0
    fi

    section "Containers"
    printf "  ${GRAY}%-28s %-18s %-14s %s${RESET}\n" "NAME" "STATUS" "PORTS" "IMAGE"
    line
    docker ps --format '{{.Names}}\t{{.Status}}\t{{.Ports}}\t{{.Image}}' 2>/dev/null \
        | while IFS=$'\t' read -r name status ports image; do
            local color="$GREEN"
            grep -qE 'unhealthy|Restarting' <<<"$status" && color="$RED"
            [[ ${#name} -gt 26 ]] && name="${name:0:23}..."
            [[ ${#image} -gt 28 ]] && image="${image:0:25}..."
            local short_ports
            short_ports=$(sed 's/0\.0\.0\.0://g; s/\[::\]:[0-9]*->[0-9]*\/[a-z]*//g; s/, *$//' <<<"$ports" | cut -c1-14)
            printf "  ${WHITE}%-28s${RESET} ${color}%-18s${RESET} %-14s ${DIM}%s${RESET}\n" \
                "$name" "$(cut -d' ' -f1-2 <<<"$status")" "$short_ports" "$image"
        done

    local total running
    total=$(docker ps -aq 2>/dev/null | wc -l | tr -d ' ')
    running=$(docker ps -q 2>/dev/null | wc -l | tr -d ' ')
    echo ""
    kv "Total containers:" "$total"
    kv "Running:" "$running" "$GREEN"
    record "docker_total" "$total" num
    record "docker_running" "$running" num

    section "Docker Disk Usage"
    docker system df 2>/dev/null | while read -r l; do
        printf "  %s\n" "$l"
    done
}

# ═══════════════════════════════════════════════════════════════
# EXTERNAL MODULES (community scripts, executed with timeout)
# ═══════════════════════════════════════════════════════════════
test_ip_check() {
    header "IP QUALITY CHECK" "IP reputation & service blocks (IP.Check.Place)"
    [[ $HIDE_IP -eq 1 ]] && status_warn "--hide-ip does not apply to external scripts — output will show the real IP"
    run_external "IP.Check.Place" 900 "https://ip.check.place" -l en \
        || status_fail "IP.Check.Place unavailable"
}

test_ip_region() {
    header "IP REGION CHECK" "What region services see from your IP (ipregion)"
    run_external "ipregion.xyz" 600 "https://ipregion.xyz" \
        || run_external "ipregion (GitHub)" 600 "https://github.com/vernette/ipregion/raw/master/ipregion.sh" \
        || status_fail "IP region check unavailable"
}

test_speed_ru() {
    header "SPEED TEST — RUSSIA" "Connectivity to Russian providers"
    run_external "bench.gig.ovh" 1800 "http://bench.gig.ovh" \
        || run_external "bench.tlab.pw" 1800 "http://bench.tlab.pw" \
        || status_fail "RU speed test unavailable"
}

test_speed_int() {
    header "SPEED TEST — INTERNATIONAL" "Global connectivity"
    run_external "bench.sh" 1800 "https://bench.sh" \
        || run_external "speed.tlab.pw" 1800 "http://speed.tlab.pw" \
        || status_fail "International speed test unavailable"
}

test_instagram() {
    header "INSTAGRAM AUDIO CHECK" "Is Instagram audio blocked on this IP"
    run_external "checker_inst" 300 "https://bench.openode.xyz/checker_inst.sh" \
        || status_fail "Instagram check unavailable"
}

test_dpi() {
    header "DPI CENSORSHIP CHECK" "DPI blocks (for Russian servers, censorcheck)"
    run_external "censorcheck" 600 "https://github.com/vernette/censorcheck/raw/master/censorcheck.sh" --mode dpi \
        || status_fail "CensorCheck unavailable"
}

test_yabs() {
    header "YABS" "fio disk + iperf3 network + Geekbench 6 (yabs.sh)"
    status_info "Full YABS run can take 15-30 minutes (Geekbench is slow on weak VPS)"
    run_external "yabs.sh" 3600 "https://yabs.sh" -4 \
        || status_fail "yabs.sh unavailable"
}

# ═══════════════════════════════════════════════════════════════
# SUMMARY
# ═══════════════════════════════════════════════════════════════
show_summary() {
    local minutes=$((SECONDS / 60)) seconds=$((SECONDS % 60))
    echo ""
    double_line
    if [[ $FAILS -eq 0 ]]; then
        printf "${BOLD}${GREEN}  ✔ All tests completed in ${minutes}m ${seconds}s${RESET}"
    else
        printf "${BOLD}${YELLOW}  ⚠ Tests completed in ${minutes}m ${seconds}s${RESET}"
    fi
    printf "${DIM}${GRAY}  (${FAILS} failed, ${WARNS} warnings)${RESET}\n"
    if [[ ${#MODULE_TIMES[@]} -gt 1 && $REPORT_MODE -eq 0 ]]; then
        local m
        for m in "${MODULE_TIMES[@]}"; do
            printf "${DIM}${GRAY}    %s${RESET}\n" "$m"
        done
    fi
    [[ -n "$REPORT_FILE" ]] && printf "  ${GRAY}Full report saved:${RESET} ${CYAN}%s${RESET}\n" "$REPORT_FILE"
    printf "${DIM}${GRAY}  Generated on $(date '+%Y-%m-%d %H:%M:%S %Z') • server-bench v${VERSION}${RESET}\n"
    double_line
    echo ""
}

# ═══════════════════════════════════════════════════════════════
# HELP
# ═══════════════════════════════════════════════════════════════
show_help() {
    show_banner
    echo "  Usage: bash server-bench.sh [options]"
    echo ""
    printf "  ${BOLD}Test modules:${RESET}\n"
    printf "    ${CYAN}--all${RESET}          Run all tests except --instagram/--dpi/--yabs (default)\n"
    printf "    ${CYAN}--quick${RESET}        Quick: info + network + security + docker (~1 min)\n"
    printf "    ${CYAN}--info${RESET}         System info + CPU bench (sysbench, steal, virt)\n"
    printf "    ${CYAN}--disk${RESET}         Disk benchmark (fio seq + 4K random; dd fallback)\n"
    printf "    ${CYAN}--network${RESET}      Ping, DNS, TCP stack (bbr/qdisc), port 25\n"
    printf "    ${CYAN}--security${RESET}     SSH audit, firewall, fail2ban, updates\n"
    printf "    ${CYAN}--docker${RESET}       Docker containers & disk usage\n"
    printf "    ${CYAN}--ip${RESET}           IP quality (IP.Check.Place) + region (ipregion)\n"
    printf "    ${CYAN}--speed${RESET}        Speed tests (RU + international)\n"
    printf "    ${CYAN}--speed-ru${RESET}     Speed test to Russian providers only\n"
    printf "    ${CYAN}--speed-int${RESET}    Speed test to international providers only\n"
    printf "    ${CYAN}--instagram${RESET}    Instagram audio block check\n"
    printf "    ${CYAN}--dpi${RESET}          DPI censorship check (RU servers)\n"
    printf "    ${CYAN}--yabs${RESET}         YABS: fio + iperf3 + Geekbench 6 (long!)\n"
    echo ""
    printf "  ${BOLD}Options:${RESET}\n"
    printf "    ${CYAN}--live${RESET}         Stream test output live (default for a single module)\n"
    printf "    ${CYAN}--report${RESET}       Progress + structured report + autosave to file\n"
    printf "                   ${DIM}(default for multi-module runs on a terminal)${RESET}\n"
    printf "    ${CYAN}--json${RESET}         JSON to stdout (local modules only), report to stderr\n"
    printf "    ${CYAN}--hide-ip${RESET}      Mask public IPs (safe to paste results publicly)\n"
    printf "    ${CYAN}--no-install${RESET}   Never install packages\n"
    printf "    ${CYAN}--no-color${RESET}     Disable colors (NO_COLOR env also works)\n"
    printf "    ${CYAN}--version${RESET}      Print version\n"
    printf "    ${CYAN}--help${RESET}         This help\n"
    echo ""
    printf "  ${DIM}Combine modules: bash server-bench.sh --info --disk --network${RESET}\n"
    printf "  ${DIM}Save a report:   bash server-bench.sh --quick 2>&1 | tee bench.txt${RESET}\n"
    echo ""
}

# ═══════════════════════════════════════════════════════════════
# MAIN
# ═══════════════════════════════════════════════════════════════
run_module() {
    # run_module function "title" — live: stream; report: capture + checklist
    local fn="$1" title="$2" t0=$SECONDS elapsed
    if [[ $REPORT_MODE -eq 1 ]]; then
        start_ticker "$title" "$DONE_MODULES" "$TOTAL_MODULES"
        "$fn" >"$(mod_log "$title")" 2>&1
        stop_ticker
        DONE_MODULES=$((DONE_MODULES + 1))
        DONE_TITLES+=("$title")
        elapsed=$((SECONDS - t0))
        printf "  ${CHECK} %-12s ${DIM}${GRAY}%dm %02ds${RESET}\n" \
            "$title" $(( elapsed / 60 )) $(( elapsed % 60 ))
    else
        "$fn"
    fi
    MODULE_TIMES+=("$(printf '%-16s %3ds' "$title" $((SECONDS - t0)))")
}

# ═══════════════════════════════════════════════════════════════
# STRUCTURED REPORT (report mode)
# ═══════════════════════════════════════════════════════════════
report_kind() {
    case "$1" in
        info|disk|network|security|docker) echo "local" ;;   # replay as-is (our clean output)
        speed-ru|speed-int)                echo "speed" ;;   # extract the speed tables
        ip-check)                          echo "ipcheck" ;; # extract key findings (output is huge)
        *)                                 echo "external" ;;# replay, CR-normalized
    esac
}

save_report() {
    # concatenate all captured logs, ANSI-stripped, into a plain-text file
    local dir="" d f title
    for d in "$PWD" "${HOME:-/root}" /tmp; do
        [[ -d "$d" && -w "$d" ]] && { dir="$d"; break; }
    done
    [[ -n "$dir" ]] || return 0
    f="${dir%/}/server-bench-$(date +%Y%m%d-%H%M%S).log"
    {
        printf 'server-bench v%s — full report — %s\n' "$VERSION" "$(date '+%Y-%m-%d %H:%M:%S %Z')"
        local title
        for title in ${DONE_TITLES[@]+"${DONE_TITLES[@]}"}; do
            [[ -s "$(mod_log "$title")" ]] && strip_ansi <"$(mod_log "$title")"
        done
    } >"$f" 2>/dev/null && REPORT_FILE="$f"
    return 0
}

final_report() {
    save_report
    local title log lines
    echo ""
    double_line
    printf "${BOLD}${WHITE}  📋 STRUCTURED REPORT${RESET}\n"
    double_line
    for title in ${DONE_TITLES[@]+"${DONE_TITLES[@]}"}; do
        log=$(mod_log "$title")
        [[ -s "$log" ]] || continue
        case "$(report_kind "$title")" in
            local)
                cat "$log"
                ;;
            external)
                sed -e 's/\r$//' -e 's/\r/\n/g' "$log"
                ;;
            speed)
                header "$(tr '[:lower:]' '[:upper:]' <<<"$title") — KEY RESULTS" "full output in the report file"
                lines=$(strip_ansi <"$log" \
                    | grep -E 'Mbit|Mbps|MB/s|Upload|Download|Latency|Node|Speedtest' \
                    | grep -vE '^[[:space:]]*$' | head -40)
                if [[ -n "$lines" ]]; then
                    printf '%s\n' "$lines"
                else
                    status_info "no speed lines captured — see the report file"
                fi
                ;;
            ipcheck)
                header "IP QUALITY — KEY FINDINGS" "full output in the report file"
                lines=$(strip_ansi <"$log" \
                    | grep -iE 'score|risk|fraud|abuse|proxy|vpn|tor|hosting|residential|native' \
                    | head -30)
                if [[ -n "$lines" ]]; then
                    printf '%s\n' "$lines"
                else
                    status_info "could not extract key lines — see the report file"
                fi
                ;;
        esac
    done
}

main() {
    local run_info=false run_disk=false run_speed_ru=false run_speed_int=false
    local run_ip=false run_ip_region=false run_instagram=false run_dpi=false
    local run_network=false run_security=false run_docker=false run_yabs=false
    local run_all=false run_quick=false want_help=false

    [[ $# -eq 0 ]] && run_all=true

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --all)        run_all=true ;;
            --info)       run_info=true ;;
            --disk)       run_disk=true ;;
            --speed)      run_speed_ru=true; run_speed_int=true ;;
            --speed-ru)   run_speed_ru=true ;;
            --speed-int)  run_speed_int=true ;;
            --ip)         run_ip=true; run_ip_region=true ;;
            --network)    run_network=true ;;
            --security)   run_security=true ;;
            --docker)     run_docker=true ;;
            --instagram)  run_instagram=true ;;
            --dpi)        run_dpi=true ;;
            --yabs)       run_yabs=true ;;
            --quick)      run_quick=true ;;
            --live)       LIVE_MODE=1 ;;
            --report)     FORCE_REPORT=1 ;;
            --json)       JSON_MODE=1 ;;
            --hide-ip)    HIDE_IP=1 ;;
            --no-install) NO_INSTALL=1 ;;
            --no-color)   USE_COLOR=0 ;;
            --version|-V) echo "server-bench v${VERSION}"; exit 0 ;;
            --help|-h)    want_help=true ;;
            *)            init_colors; echo "Unknown option: $1"; show_help; exit 1 ;;
        esac
        shift
    done

    # In JSON mode: pretty report -> stderr, JSON object -> stdout (fd 3)
    if [[ $JSON_MODE -eq 1 ]]; then
        exec 3>&1 1>&2
    else
        exec 3>&1
    fi

    init_colors

    if $want_help; then
        show_help
        exit 0
    fi

    if $run_all; then
        run_info=true; run_disk=true; run_network=true; run_security=true
        run_docker=true; run_ip=true; run_ip_region=true
        run_speed_ru=true; run_speed_int=true
    fi
    if $run_quick; then
        run_info=true; run_network=true; run_security=true; run_docker=true
    fi

    show_banner

    TMPDIR=$(mktemp -d)
    trap 'cleanup' EXIT
    trap 'echo ""; exit 130' INT TERM

    # external modules produce free-form text — they can't feed the JSON report
    if [[ $JSON_MODE -eq 1 ]]; then
        if $run_ip || $run_ip_region || $run_speed_ru || $run_speed_int \
            || $run_instagram || $run_dpi || $run_yabs; then
            status_warn "--json: external modules (ip/speed/instagram/dpi/yabs) are skipped"
        fi
        run_ip=false; run_ip_region=false; run_speed_ru=false; run_speed_int=false
        run_instagram=false; run_dpi=false; run_yabs=false
    fi

    record "version" "$VERSION"
    record "date" "$(date -Is 2>/dev/null || date)"

    # install only what the selected modules actually need
    local deps=()
    if ! command_exists curl; then deps+=("curl"); fi
    $run_info    && deps+=("sysbench")
    $run_disk    && deps+=("fio")
    $run_network && deps+=("ping" "dig")
    if [[ ${#deps[@]} -gt 0 ]]; then
        ensure_deps "${deps[@]}"
    fi
    if ! command_exists curl; then
        status_warn "curl is not available — IP detection and external modules will fail"
    fi

    local modules=()
    $run_info      && modules+=("test_system_info:info")
    $run_disk      && modules+=("test_disk:disk")
    $run_network   && modules+=("test_network:network")
    $run_security  && modules+=("test_security:security")
    $run_docker    && modules+=("test_docker:docker")
    $run_ip        && modules+=("test_ip_check:ip-check")
    $run_ip_region && modules+=("test_ip_region:ip-region")
    $run_speed_ru  && modules+=("test_speed_ru:speed-ru")
    $run_speed_int && modules+=("test_speed_int:speed-int")
    $run_instagram && modules+=("test_instagram:instagram")
    $run_dpi       && modules+=("test_dpi:dpi")
    $run_yabs      && modules+=("test_yabs:yabs")
    TOTAL_MODULES=${#modules[@]}

    # report mode: capture output, show a progress checklist, print a
    # structured report at the end. Default for multi-module terminal runs;
    # --live restores streaming, --report forces it even for one module.
    if [[ $JSON_MODE -eq 0 ]]; then
        if [[ $FORCE_REPORT -eq 1 ]]; then
            REPORT_MODE=1
        elif [[ $LIVE_MODE -eq 0 && $TOTAL_MODULES -gt 1 && -t 1 ]]; then
            REPORT_MODE=1
        fi
    fi
    if [[ $REPORT_MODE -eq 1 ]]; then
        printf "  ${BOLD}Running %d modules${RESET} ${DIM}${GRAY}(output captured — structured report at the end)${RESET}\n\n" \
            "$TOTAL_MODULES"
    fi

    local m
    for m in ${modules[@]+"${modules[@]}"}; do
        run_module "${m%%:*}" "${m##*:}"
    done

    [[ $REPORT_MODE -eq 1 ]] && final_report

    record "elapsed_s" "$SECONDS" num
    record "fails" "$FAILS" num
    record "warns" "$WARNS" num

    show_summary
    [[ $JSON_MODE -eq 1 ]] && emit_json

    exit 0
}

main "$@"
