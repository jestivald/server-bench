#!/usr/bin/env bash
# shellcheck disable=SC2059,SC2317,SC2329,SC1091
# ╔══════════════════════════════════════════════════════════════╗
# ║  Server Benchmark Suite v2.3                                 ║
# ║  All-in-one server diagnostics & performance testing        ║
# ╚══════════════════════════════════════════════════════════════╝
#
# Usage: bash server-bench.sh [options]
#   --all         Run all tests (default)
#   --quick       Quick: info + network + security + docker
#   --menu        Choose modules interactively, with time estimates
#   --list        List modules without running tests
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
#   --geoblock    Check service geoblocks (censorcheck)
#   --yabs        YABS (fio + iperf3 + Geekbench 6)
#   --live        Stream test output live (default for single-module runs)
#   --report      Progress checklist + structured report at the end
#                 (default for multi-module runs on a terminal)
#   --json        Machine-readable output (built-in modules)
#   --hide-ip     Mask public IPs in output (for public pastes)
#   --no-install  Never install packages, degrade gracefully
#   --no-color    Disable colored output (also honors NO_COLOR)
#   --version     Print version
#   --help        Show help
#
# Author: jestivald (generated with Claude)
# License: MIT

VERSION="2.3.0"

if (( BASH_VERSINFO[0] < 4 )); then
    printf 'server-bench requires Bash 4 or newer.\n' >&2
    exit 2
fi

set -u

# ═══════════════════════════════════════════════════════════════
# GLOBAL STATE
# ═══════════════════════════════════════════════════════════════
FAILS=0
WARNS=0
SKIPS=0
JSON_MODE=0
HIDE_IP=0
NO_INSTALL=0
USE_COLOR=1
APT_UPDATED=0
WORK_DIR=""
DISK_FILE=""
ACTIVE_PID=""
declare -a PROBE_PIDS=()
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

# One catalog for CLI selection, the menu, execution and dependency planning.
MODULE_IDS=(info disk network security docker ip-check ip-region speed-ru speed-int geoblock instagram dpi yabs)
MODULE_FUNCTIONS=(test_system_info test_disk test_network test_security test_docker test_ip_check test_ip_region test_speed_ru test_speed_int test_geoblock test_instagram test_dpi test_yabs)
MODULE_LABELS=("System + CPU" "Disk I/O" "Network + DNS" "Security" "Docker" "IP reputation" "IP region" "Russia iPerf3" "International speed" "Service geoblocks" "Instagram audio" "DPI censorship" "YABS + Geekbench")
MODULE_ESTIMATES=(30 60 15 10 5 180 120 120 300 120 30 60 1200)
MODULE_SCOPES=(local local local local local external external local external external external external external)
SELECTED_MODULES=(0 0 0 0 0 0 0 0 0 0 0 0 0)

# Color vars (filled by init_colors)
RED='' GREEN='' YELLOW='' BLUE='' CYAN='' WHITE='' GRAY=''
BOLD='' DIM='' RESET=''
CHECK='✔' CROSS='✘' WARN_S='⚠' INFO_S='ℹ'
TERM_WIDTH=70

# ═══════════════════════════════════════════════════════════════
# PRIVILEGE HANDLING (root / passwordless sudo / interactive sudo)
# ═══════════════════════════════════════════════════════════════
declare -a SUDO_CMD=()
init_privileges() {
    if [[ ${EUID:-$(id -u)} -ne 0 ]] && command -v sudo &>/dev/null; then
        if sudo -n true 2>/dev/null; then
            SUDO_CMD=(sudo -n)
        elif [[ -t 0 && -t 1 ]] && sudo -v; then
            # Authenticate before any command's output is captured.
            SUDO_CMD=(sudo -n)
        fi
    fi
    return 0
}

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
status_skip() { printf "  ${INFO_S} Skipped: %s\n" "$1"; SKIPS=$((SKIPS + 1)); }

# Run a command silently with a spinner; output captured to a file.
# usage: run_quiet "message" /path/outfile cmd [args...]
run_quiet() {
    local msg="$1" out="$2"
    shift 2
    "$@" >"$out" 2>&1 &
    local pid=$!
    ACTIVE_PID=$pid
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
    fi
    local rc=0
    wait "$pid" 2>/dev/null
    rc=$?
    ACTIVE_PID=""
    return "$rc"
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
# JSON OUTPUT (--json, built-in modules)
# ═══════════════════════════════════════════════════════════════
declare -a REC_KEYS=()
declare -a REC_VALS=()

record() {
    # record key value [num] — kept for the scorecard, mirrored to --json
    local k="$1" v="${2:-}" t="${3:-str}"
    REC_KEYS+=("$k")
    REC_VALS+=("$v")
    [[ $JSON_MODE -eq 1 ]] || return 0
    if [[ "$t" == "num" ]]; then
        if [[ "$v" =~ ^-?(0|[1-9][0-9]*)([.][0-9]+)?([eE][+-]?[0-9]+)?$ ]]; then
            JSON_KV+=("\"$k\":$v")
        else
            JSON_KV+=("\"$k\":null")
        fi
    else
        v=$(json_escape "$v")
        JSON_KV+=("\"$k\":\"$v\"")
    fi
}

json_escape() {
    local value="$1" char escaped result="" i
    for (( i = 0; i < ${#value}; i++ )); do
        char=${value:i:1}
        case "$char" in
            \\) result+="\\\\" ;;
            \") result+='\"' ;;
            [[:cntrl:]])
                printf -v escaped '\\u%04x' "'$char"
                result+="$escaped" ;;
            *) result+="$char" ;;
        esac
    done
    printf '%s' "$result"
}

emit_json() {
    local IFS=','
    printf '{%s}\n' "${JSON_KV[*]-}" >&3
}

rec_get() {
    # last recorded value for a key (empty + rc 1 when absent)
    local i
    for (( i = ${#REC_KEYS[@]} - 1; i >= 0; i-- )); do
        if [[ "${REC_KEYS[$i]}" == "$1" ]]; then
            printf '%s' "${REC_VALS[$i]}"
            return 0
        fi
    done
    return 1
}

# ═══════════════════════════════════════════════════════════════
# MISC HELPERS
# ═══════════════════════════════════════════════════════════════
command_exists() {
    command -v "$1" &>/dev/null
}

cleanup() {
    stop_ticker
    local pid
    for pid in ${PROBE_PIDS[@]+"${PROBE_PIDS[@]}"} ${ACTIVE_PID:+"$ACTIVE_PID"}; do
        kill "$pid" 2>/dev/null || true
        wait "$pid" 2>/dev/null || true
    done
    [[ -n "$WORK_DIR" ]] && rm -rf -- "$WORK_DIR"
    [[ -n "$DISK_FILE" ]] && rm -f "$DISK_FILE"
    return 0
}

strip_ansi() {
    # strip colors + emulate the terminal for \r progress spinners:
    # of every \r-overwritten chain keep only the final visible text
    sed -e $'s/\x1b\\[[0-9;]*[a-zA-Z]//g' \
        | awk '{
            n = split($0, a, "\r"); out = ""
            for (i = 1; i <= n; i++) if (a[i] != "") out = a[i]
            print out
        }'
}

mod_log() {
    printf '%s/mod_%s.log' "$WORK_DIR" "$1"
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
                timeout) echo "coreutils" ;;
                *)    echo "$c" ;;
            esac ;;
        dnf|yum)
            case "$c" in
                dig)  echo "bind-utils" ;;
                ping) echo "iputils" ;;
                timeout) echo "coreutils" ;;
                *)    echo "$c" ;;
            esac ;;
        *) echo "$c" ;;
    esac
}

pm_install() {
    case "$PM" in
        apt-get)
            run_priv env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "$@" ;;
        dnf) run_priv dnf install -y -q "$@" ;;
        yum) run_priv yum install -y -q "$@" ;;
        *)   return 1 ;;
    esac
}

ensure_deps() {
    # ensure_deps cmd [cmd...] — install what's missing, warn on failure
    local missing=() packages=() c pkg
    for c in "$@"; do
        if ! command_exists "$c" && [[ " ${missing[*]-} " != *" $c "* ]]; then
            missing+=("$c")
        fi
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
        pkg=$(pkg_for "$c")
        [[ " ${packages[*]-} " == *" $pkg "* ]] || packages+=("$pkg")
    done
    if [[ "$PM" == "apt-get" && $APT_UPDATED -eq 0 ]]; then
        # Set state in the parent shell, not inside run_quiet's background job.
        APT_UPDATED=1
        run_quiet "Updating package list..." "$WORK_DIR/apt.log" \
            run_priv env DEBIAN_FRONTEND=noninteractive apt-get update -qq \
            || status_warn "Package list update failed; trying the existing cache"
    fi
    run_quiet "Installing ${packages[*]}..." "$WORK_DIR/install.log" pm_install "${packages[@]}" || true
    for c in "${missing[@]}"; do
        pkg=$(pkg_for "$c")
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
    # Interactive prompts are auto-answered "y" (some scripts ask before
    # installing speedtest binaries). Returns 1 when the script could not be
    # fetched OR died within seconds (caller may try a mirror); a timed-out
    # or long partial run is reported but not retried.
    local label="$1" tmo="$2" url="$3"
    shift 3
    if [[ $NO_INSTALL -eq 1 || $HIDE_IP -eq 1 ]]; then
        status_skip "${label}: external scripts cannot enforce --no-install/--hide-ip"
        return 0
    fi
    local script t0 rc
    script=$(mktemp "$WORK_DIR/upstream.XXXXXXXX") || return 1
    status_info "Fetching ${label}..."
    if ! curl -fsSL --connect-timeout 10 --max-time 60 "$url" -o "$script" 2>/dev/null || [[ ! -s "$script" ]]; then
        status_warn "${label}: could not fetch script"
        return 1
    fi
    if grep -qiE '^[[:space:]]*<(!doctype|html)' "$script" || ! bash -n "$script" 2>/dev/null; then
        status_warn "${label}: endpoint did not return a valid Bash script"
        return 1
    fi
    echo ""
    t0=$SECONDS
    # The timeout owns a process group so its deadline also stops child jobs.
    yes y 2>/dev/null | timeout -k 15 "$tmo" bash "$script" "$@" &
    ACTIVE_PID=$!
    wait "$ACTIVE_PID"
    rc=$?
    ACTIVE_PID=""
    case $rc in
        0) return 0 ;;
        124|137)
            status_fail "${label}: timed out after ${tmo}s"
            return 0 ;;
        *)
            if [[ $((SECONDS - t0)) -lt 10 ]]; then
                status_warn "${label}: died right after start (code ${rc}) — trying a mirror if available"
                return 1
            fi
            status_fail "${label}: exited with code ${rc}"
            return 0 ;;
    esac
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
detect_public_ip() {
    local family="$1" url ip
    for url in https://ifconfig.me https://icanhazip.com; do
        ip=$(curl "-$family" -fsS --connect-timeout 3 --max-time 5 "$url" 2>/dev/null) || continue
        ip=${ip//[[:space:]]/}
        if [[ $family -eq 4 && "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] \
            || [[ $family -eq 6 && "$ip" == *:* && "$ip" =~ ^[0-9a-fA-F:]+$ ]]; then
            printf '%s' "$ip"
            return 0
        fi
    done
    printf 'N/A'
}

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
    if [[ $HIDE_IP -eq 1 ]]; then
        kv "Hostname:" "[hidden]"
    else
        kv "Hostname:" "$(hostname 2>/dev/null || echo "${HOSTNAME:-?}")"
    fi
    kv "Uptime:" "$(uptime -p 2>/dev/null || uptime 2>/dev/null | sed 's/.*up //; s/,.*//')"

    local virt="unknown"
    if command_exists systemd-detect-virt; then
        virt=$(systemd-detect-virt 2>/dev/null) || virt="none"
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
        read -r t1 s1 < <(awk '/^cpu /{printf "%.0f %.0f\n", $2+$3+$4+$5+$6+$7+$8+$9, $9}' /proc/stat)
        sleep 1
        read -r t2 s2 < <(awk '/^cpu /{printf "%.0f %.0f\n", $2+$3+$4+$5+$6+$7+$8+$9, $9}' /proc/stat)
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
        run_quiet "Running sysbench CPU test (1 thread, 10s)..." "$WORK_DIR/sb1.log" \
            timeout -k 5 20 sysbench cpu run --threads=1 --time=10
        eps_1t=$(awk '/events per second/{print $NF}' "$WORK_DIR/sb1.log")
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
            run_quiet "Running sysbench CPU test (${cpu_cores} threads, 10s)..." "$WORK_DIR/sbn.log" \
                timeout -k 5 20 sysbench cpu run --threads="$cpu_cores" --time=10
            eps_mt=$(awk '/events per second/{print $NF}' "$WORK_DIR/sbn.log")
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
    df -h --output=target,fstype,size,used,avail,pcent 2>/dev/null \
        | awk 'NR == 1 {next}
               $2 ~ /^(tmpfs|devtmpfs|ramfs|squashfs|efivarfs|vfat)$/ {next}
               $1 ~ /^\/(dev|run|sys|proc)(\/|$)/ {next}
               $1 ~ /^\/var\/lib\/docker\// {next}
               $1 ~ /^\/snap(\/|$)/ {next}
               {print $1, $3, $4, $5, $6}' \
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
    detect_public_ip 4 >"$WORK_DIR/ipv4" &
    PROBE_PIDS+=("$!")
    detect_public_ip 6 >"$WORK_DIR/ipv6" &
    PROBE_PIDS+=("$!")
    wait_probes
    ipv4=$(cat "$WORK_DIR/ipv4")
    ipv6=$(cat "$WORK_DIR/ipv6")
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
        if [[ $HIDE_IP -eq 0 ]] && command_exists dig; then
            local rdns
            rdns=$(dig +short +time=3 +tries=1 -x "$ipv4" 2>/dev/null | head -1)
            [[ -n "$rdns" ]] && kv "rDNS:" "$rdns" && record "rdns" "$rdns"
        fi
    fi
    return 0
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
            ""|tmpfs|devtmpfs|ramfs) continue ;;
        esac
        avail_kb=$(df --output=avail "$d" 2>/dev/null | tail -1 | tr -d ' ')
        [[ "${avail_kb:-0}" =~ ^[0-9]+$ ]] || continue
        [[ $avail_kb -ge $((350 * 1024)) ]] || continue
        printf '%s\t%s\t%s\n' "$d" "$fstype" "$avail_kb"
        return 0
    done
    return 1
}

terse_field() {
    # terse_field N file — field N of the last terse v3 line
    awk -F';' -v n="$1" '$1 == "3" {value=$n} END{print value}' "$2" 2>/dev/null
}

kb_to_mb() {
    awk -v k="${1:-0}" 'BEGIN{printf "%.1f", k / 1024}'
}

fmt_iops() {
    awk -v i="${1:-0}" 'BEGIN{if (i >= 1000) printf "%.1fk", i / 1000; else printf "%.0f", i}'
}

fio_job() {
    # A terse record is also emitted on errors: require both exit success
    # and error=0 (field 5). Never present page-cache throughput as disk I/O.
    local msg="$1" out="$2"
    shift 2
    run_quiet "$msg" "$out" timeout -k 5 90 fio --output-format=terse --terse-version=3 \
        --name=bench --filename="$DISK_FILE" --direct=1 --ioengine="$FIO_ENG" "$@" || return 1
    awk -F';' '$1 == "3" {
        seen=1
        if (NF < 49 || $5 != "0") bad=1
        for (i=7; i<=8; i++) if ($i !~ /^[0-9]+([.][0-9]+)?$/) bad=1
        for (i=48; i<=49; i++) if ($i !~ /^[0-9]+([.][0-9]+)?$/) bad=1
    } END {exit !(seen && !bad)}' "$out"
}

test_disk() {
    header "DISK BENCHMARK" "Sequential & random I/O performance"

    local pick dir fstype avail_kb size_mb=512
    if ! pick=$(pick_disk_dir); then
        status_fail "No writable disk-backed directory with at least 350MB free — disk test skipped"
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

    DISK_FILE=$(mktemp "${dir%/}/.server-bench-fio.XXXXXXXX") || {
        status_fail "Could not create a disk test file in ${dir}"
        return 0
    }
    kv "Test path:" "${dir} (${fstype}, ${size_mb}MB file)"
    record "disk_test_path" "$dir"
    record "disk_test_fs" "$fstype"

    if command_exists fio; then
        FIO_ENG="psync"
        fio --enghelp 2>/dev/null | grep -qw libaio && FIO_ENG="libaio"
        record "disk_io_engine" "$FIO_ENG"
        record "disk_direct" "1" num
        local seq_depth=1 rand_depth=1
        if [[ "$FIO_ENG" == "libaio" ]]; then seq_depth=8; rand_depth=32; fi

        section "Sequential (fio, 1M blocks)"
        local bw
        if fio_job "Sequential write (${size_mb}MB)..." "$WORK_DIR/fio_sw.log" \
                --rw=write --bs=1M --iodepth="$seq_depth" --size="${size_mb}M" --runtime=60; then
            bw=$(terse_field 48 "$WORK_DIR/fio_sw.log")
            kv "Sequential Write:" "$(kb_to_mb "$bw") MB/s" "$YELLOW"
            record "disk_seq_write_mbs" "$(kb_to_mb "$bw")" num
        else
            status_fail "fio sequential write failed (direct I/O required); remaining disk tests skipped"
            rm -f -- "$DISK_FILE"
            DISK_FILE=""
            return 0
        fi
        if fio_job "Sequential read (${size_mb}MB)..." "$WORK_DIR/fio_sr.log" \
                --rw=read --bs=1M --iodepth="$seq_depth" --size="${size_mb}M" --runtime=30; then
            bw=$(terse_field 7 "$WORK_DIR/fio_sr.log")
            kv "Sequential Read:" "$(kb_to_mb "$bw") MB/s" "$YELLOW"
            record "disk_seq_read_mbs" "$(kb_to_mb "$bw")" num
        else
            status_fail "fio sequential read failed"
        fi

        section "Random 4K (fio, iodepth ${rand_depth}, 10s each)"
        local iops
        if fio_job "4K random read..." "$WORK_DIR/fio_rr.log" \
                --rw=randread --bs=4k --iodepth="$rand_depth" --size="${size_mb}M" --time_based --runtime=10; then
            iops=$(terse_field 8 "$WORK_DIR/fio_rr.log")
            bw=$(terse_field 7 "$WORK_DIR/fio_rr.log")
            kv "4K Random Read:" "$(fmt_iops "$iops") IOPS ($(kb_to_mb "$bw") MB/s)" "$YELLOW"
            record "disk_rand_read_iops" "${iops%%.*}" num
        else
            status_fail "fio random read failed"
        fi
        if fio_job "4K random write..." "$WORK_DIR/fio_rw.log" \
                --rw=randwrite --bs=4k --iodepth="$rand_depth" --size="${size_mb}M" --time_based --runtime=10; then
            iops=$(terse_field 49 "$WORK_DIR/fio_rw.log")
            bw=$(terse_field 48 "$WORK_DIR/fio_rw.log")
            kv "4K Random Write:" "$(fmt_iops "$iops") IOPS ($(kb_to_mb "$bw") MB/s)" "$YELLOW"
            record "disk_rand_write_iops" "${iops%%.*}" num
        else
            status_fail "fio random write failed"
        fi
    else
        # dd fallback: /dev/zero is compressible — take results with a grain
        # of salt on ZFS/thin-provisioned storage
        section "Sequential (dd fallback — install fio for accurate numbers)"
        status_warn "dd is an approximate fallback; buffered retries may include page-cache effects"
        local out speed
        if run_quiet "Writing ${size_mb}MB (direct I/O)..." "$WORK_DIR/dd_w.log" \
                env LC_ALL=C dd if=/dev/zero of="$DISK_FILE" bs=1M count="$size_mb" oflag=direct conv=fdatasync \
            || run_quiet "Writing ${size_mb}MB (fdatasync)..." "$WORK_DIR/dd_w.log" \
                env LC_ALL=C dd if=/dev/zero of="$DISK_FILE" bs=1M count="$size_mb" conv=fdatasync; then
            speed=$(tail -n1 "$WORK_DIR/dd_w.log" | awk '{print $(NF-1), $NF}')
            kv "Sequential Write:" "$speed" "$YELLOW"
        else
            status_fail "dd write test failed"
            rm -f -- "$DISK_FILE"
            DISK_FILE=""
            return 0
        fi
        if [[ -f "$DISK_FILE" ]]; then
            if run_quiet "Reading ${size_mb}MB (direct I/O)..." "$WORK_DIR/dd_r.log" \
                    env LC_ALL=C dd if="$DISK_FILE" of=/dev/null bs=1M iflag=direct \
                || run_quiet "Reading ${size_mb}MB..." "$WORK_DIR/dd_r.log" \
                    env LC_ALL=C dd if="$DISK_FILE" of=/dev/null bs=1M; then
                speed=$(tail -n1 "$WORK_DIR/dd_r.log" | awk '{print $(NF-1), $NF}')
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
wait_probes() {
    local pid
    for pid in ${PROBE_PIDS[@]+"${PROBE_PIDS[@]}"}; do
        wait "$pid" 2>/dev/null || true
    done
    PROBE_PIDS=()
}

dns_probe() {
    local domain="$1" resolved="" dns_ms="" out start_ns end_ns
    if command_exists dig; then
        out=$(timeout -k 1 5 dig +tries=1 +time=3 +noall +answer +stats "$domain" A 2>/dev/null)
        resolved=$(awk '$4 == "A" {print $5; exit}' <<<"$out")
        dns_ms=$(sed -n 's/.*Query time: \([0-9]*\) msec.*/\1/p' <<<"$out" | head -1)
    fi
    if [[ -z "$resolved" ]] && command_exists getent; then
        start_ns=$(date +%s%N)
        out=$(timeout -k 1 4 getent ahostsv4 "$domain" 2>/dev/null)
        resolved=$(awk 'NR == 1 {print $1}' <<<"$out")
        end_ns=$(date +%s%N)
        if [[ "$start_ns" =~ ^[0-9]+$ && "$end_ns" =~ ^[0-9]+$ ]]; then
            dns_ms=$(( (end_ns - start_ns) / 1000000 ))
        else
            dns_ms=""
        fi
    fi
    printf '%s|%s\n' "$resolved" "$dns_ms"
}

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
        local entry ip name out stats min_ms avg_ms max_ms loss key perm_hint=0 i=0
        # Low-traffic probes can run together; results still print in order.
        for entry in "${targets[@]}"; do
            timeout -k 1 8 ping -c 3 -W 2 -w 7 "${entry%%:*}" >"$WORK_DIR/ping_$i.log" 2>&1 &
            PROBE_PIDS+=("$!")
            i=$((i + 1))
        done
        wait_probes
        i=0
        for entry in "${targets[@]}"; do
            ip="${entry%%:*}"
            name="${entry##*:}"
            out=$(cat "$WORK_DIR/ping_$i.log")
            i=$((i + 1))
            key=${name,,}
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
                record "ping_${key}_avg_ms" "$avg_ms" num
            else
                printf "  ${WHITE}%-22s${RESET} ${RED}%s${RESET}\n" "$name ($ip)" "unreachable"
                record "ping_${key}_avg_ms" "" num
            fi
            record "ping_${key}_loss_pct" "$loss" num
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
        dns_probe "$domain" >"$WORK_DIR/dns_$domain.log" &
        PROBE_PIDS+=("$!")
    done
    wait_probes
    for domain in "${dns_targets[@]}"; do
        resolved="" dns_ms=""
        IFS='|' read -r resolved dns_ms <"$WORK_DIR/dns_$domain.log"
        if [[ -n "$resolved" ]]; then
            local color="$GREEN" dns_disp="${dns_ms:-?}"
            [[ ${dns_ms:-0} -gt 100 ]] 2>/dev/null && color="$YELLOW"
            [[ ${dns_ms:-0} -gt 500 ]] 2>/dev/null && color="$RED"
            [[ "$dns_ms" == "0" ]] && dns_disp="<1"
            printf "  ${CHECK} %-22s ${color}%sms${RESET}  ${DIM}→ %s${RESET}\n" "$domain" "$dns_disp" "$resolved"
            record "dns_${domain//./_}_ms" "$dns_ms" num
        else
            printf "  ${CROSS} %-22s ${RED}FAILED${RESET}\n" "$domain"
            FAILS=$((FAILS + 1))
            record "dns_${domain//./_}_ms" "" num
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
        status_warn "Effective sshd config unavailable — SSH settings unknown (root/sudo may be needed)"
    fi

    # Firewall
    section "Firewall"
    local fw="none" ufw_output
    if command_exists ufw; then
        ufw_output=$(run_priv ufw status 2>/dev/null) || ufw_output=""
        if grep -qE '^Status: active[[:space:]]*$' <<<"$ufw_output"; then
            status_ok "UFW: active"
            fw="ufw-active"
        elif grep -qE '^Status: inactive[[:space:]]*$' <<<"$ufw_output"; then
            status_warn "UFW: inactive"
            fw="ufw-inactive"
        else
            status_warn "UFW status unavailable (permissions?)"
            fw="unknown"
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
        local updates update_list
        if ! update_list=$(timeout -k 2 30 apt list --upgradable 2>/dev/null); then
            status_warn "Could not read the package update list"
            record "pending_updates" "" num
        else
            updates=$(grep -c 'upgradable' <<<"$update_list") || updates=0
            if [[ $updates -gt 0 ]]; then
                status_warn "$updates packages can be updated (cached package lists)"
            else
                status_info "No pending updates in cached package lists"
            fi
            record "pending_updates" "$updates" num
        fi
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
        status_skip "Docker not installed"
        record "docker_running" "" num
        return 0
    fi
    if ! timeout -k 2 15 docker info &>/dev/null; then
        status_warn "Docker installed but daemon unreachable (permissions?)"
        return 0
    fi

    local containers usage total=0 running=0 name status ports image state
    if ! containers=$(timeout -k 2 15 docker ps -a --format '{{.Names}}|{{.Status}}|{{.Ports}}|{{.Image}}|{{.State}}' 2>/dev/null); then
        status_warn "Could not read the Docker container list"
        return 0
    fi
    section "Containers"
    printf '  %-28s %-22s %-14s %s\n' "NAME" "STATUS" "PORTS" "IMAGE"
    line
    while IFS='|' read -r name status ports image state; do
        [[ -n "$name" ]] || continue
        total=$((total + 1))
        [[ "$state" == running ]] && running=$((running + 1))
        local color="$GREEN" short_ports
        if [[ "$status" == *unhealthy* || "$state" == restarting ]]; then
            color="$RED"
        elif [[ "$state" != running ]]; then
            color="$GRAY"
        fi
        [[ ${#name} -gt 26 ]] && name="${name:0:23}..."
        [[ ${#image} -gt 28 ]] && image="${image:0:25}..."
        short_ports=$(sed -E 's/[0-9.]+:([0-9]+)->/\1->/g; s/\[[^]]*\]:([0-9]+)->/\1->/g' <<<"$ports" | cut -c1-14)
        printf "  ${WHITE}%-28s${RESET} ${color}%-22s${RESET} %-14s ${DIM}%s${RESET}\n" \
            "$name" "$status" "$short_ports" "$image"
    done <<<"$containers"
    echo ""
    kv "Total containers:" "$total"
    kv "Running:" "$running" "$GREEN"
    record "docker_total" "$total" num
    record "docker_running" "$running" num

    section "Docker Disk Usage"
    if usage=$(timeout -k 2 30 docker system df 2>/dev/null); then
        while IFS= read -r line; do printf '  %s\n' "$line"; done <<<"$usage"
    else
        status_warn "Could not read Docker disk usage"
    fi
    return 0

}

# ═══════════════════════════════════════════════════════════════
# EXTERNAL MODULES (community scripts, executed with timeout)
# ═══════════════════════════════════════════════════════════════
test_ip_check() {
    header "IP QUALITY CHECK" "IP reputation & service blocks (IP.Check.Place)"
    # -y: auto-confirm dependency install; -p: privacy mode — do NOT upload
    # the report to upload.check.place / generate a public share link
    run_external "IP.Check.Place" 900 "https://ip.check.place" -l en -y -p \
        || status_fail "IP.Check.Place unavailable"
}

test_ip_region() {
    header "IP REGION CHECK" "What region services see from your IP (ipregion)"
    run_external "ipregion.xyz" 600 "https://ipregion.xyz" \
        || run_external "ipregion (GitHub)" 600 "https://github.com/vernette/ipregion/raw/master/ipregion.sh" \
        || status_fail "IP region check unavailable"
}

iperf_sample() {
    local host="$1" port="$2" direction="$3" out="$4" bps
    local args=(-c "$host" -p "$port" -t 5 -P 4 --connect-timeout 3000 --json)
    [[ "$direction" == "download" ]] && args+=(-R)
    IPERF_MBPS=""
    run_quiet "${host}:${port} ${direction} (5s)..." "$out" \
        timeout -k 2 15 iperf3 "${args[@]}" || return 1
    # Receiver throughput is the delivered rate. For download the receiver
    # is this VPS because -R reverses the actual traffic direction.
    bps=$(jq -er 'select(.error == null) | .end.sum_received.bits_per_second |
        select(type == "number" and . > 0)' "$out" 2>/dev/null) || return 1
    IPERF_MBPS=$(awk -v bps="$bps" 'BEGIN {printf "%.2f", bps / 1000000}')
}

test_speed_ru() {
    header "SPEED TEST — RUSSIA" "iPerf3: separate upload and download, 4 streams, 5s per direction"
    local dep
    for dep in iperf3 jq; do
        if ! command_exists "$dep"; then
            status_skip "RU speed test requires ${dep}"
            return 0
        fi
    done

    # Public endpoints listed by itdoginfo/russian-iperf3-servers.
    # Our runner tests both directions and bounds retries on busy servers.
    local targets=(
        "moscow|Moscow|spd-rudp.hostkey.ru"
        "saint_petersburg|Saint Petersburg|st.spb.ertelecom.ru"
        "nizhny_novgorod|Nizhny Novgorod|st.nn.ertelecom.ru"
        "chelyabinsk|Chelyabinsk|st.chel.ertelecom.ru"
        "tyumen|Tyumen|st.tmn.ertelecom.ru"
    )
    local entry id city host port used_port upload download completed=0
    local rows=()
    for entry in "${targets[@]}"; do
        IFS='|' read -r id city host <<<"$entry"
        upload="" download="" used_port=""
        for port in 5201 5202 5203; do
            if iperf_sample "$host" "$port" upload "$WORK_DIR/iperf_${id}_up.json"; then
                upload=$IPERF_MBPS
                used_port=$port
                break
            fi
        done
        if [[ -n "$used_port" ]]; then
            if iperf_sample "$host" "$used_port" download "$WORK_DIR/iperf_${id}_down.json"; then
                download=$IPERF_MBPS
                completed=$((completed + 1))
            else
                status_warn "${city}: reverse/download test unavailable"
            fi
        else
            status_warn "${city}: no available iPerf3 endpoint (busy, unreachable or filtered)"
        fi
        record "speed_ru_${id}_host" "$host"
        record "speed_ru_${id}_port" "$used_port" num
        record "speed_ru_${id}_upload_mbps" "$upload" num
        record "speed_ru_${id}_download_mbps" "$download" num
        rows+=("$(printf '  %-20s %-16s %s' "$city" "${upload:-N/A}" "${download:-N/A}")")
    done
    section "Russia — throughput from this server"
    printf '  %-20s %-16s %s\n' "CITY" "UPLOAD Mbps" "DOWNLOAD Mbps"
    line
    printf '%s\n' "${rows[@]}"
    record "speed_ru_completed" "$completed" num
    [[ $completed -gt 0 ]] || status_fail "No complete RU speed measurements; results do not establish a link speed"
    return 0
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

test_geoblock() {
    header "SERVICE GEOBLOCKS" "Access restrictions by region (censorcheck)"
    run_external "censorcheck geoblock" 600 "https://raw.githubusercontent.com/vernette/censorcheck/master/censorcheck.sh" --mode geoblock \
        || status_fail "Geoblock check unavailable"
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
    printf "${DIM}${GRAY}  (${FAILS} failed, ${WARNS} warnings, ${SKIPS} skipped)${RESET}\n"
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
    printf "    ${CYAN}--all${RESET}          Default suite; geoblock/instagram/dpi/yabs are opt-in\n"
    printf "    ${CYAN}--quick${RESET}        Quick: info + network + security + docker (~1 min)\n"
    printf "    ${CYAN}--menu${RESET}         Select modules interactively with time estimates\n"
    printf "    ${CYAN}--list${RESET}         List modules, durations and required tools\n"
    printf "    ${CYAN}--info${RESET}         System info + CPU bench (sysbench, steal, virt)\n"
    printf "    ${CYAN}--disk${RESET}         Disk benchmark (fio seq + 4K random; dd fallback)\n"
    printf "    ${CYAN}--network${RESET}      Ping, DNS, TCP stack (bbr/qdisc), port 25\n"
    printf "    ${CYAN}--security${RESET}     SSH audit, firewall, fail2ban, updates\n"
    printf "    ${CYAN}--docker${RESET}       Docker containers & disk usage\n"
    printf "    ${CYAN}--ip${RESET}           IP quality (IP.Check.Place) + region (ipregion)\n"
    printf "    ${CYAN}--speed${RESET}        Speed tests (RU + international)\n"
    printf "    ${CYAN}--speed-ru${RESET}     Native iPerf3 upload + download to five Russian cities\n"
    printf "    ${CYAN}--speed-int${RESET}    Speed test to international providers only\n"
    printf "    ${CYAN}--instagram${RESET}    Instagram audio block check\n"
    printf "    ${CYAN}--dpi${RESET}          DPI censorship check (RU servers)\n"
    printf "    ${CYAN}--geoblock${RESET}     Service geoblocks (censorcheck)\n"
    printf "    ${CYAN}--yabs${RESET}         YABS: fio + iperf3 + Geekbench 6 (long!)\n"
    echo ""
    printf "  ${BOLD}Options:${RESET}\n"
    printf "    ${CYAN}--live${RESET}         Stream test output live (default for a single module)\n"
    printf "    ${CYAN}--report${RESET}       Progress + structured report + autosave to file\n"
    printf "                   ${DIM}(default for multi-module runs on a terminal)${RESET}\n"
    printf "    ${CYAN}--json${RESET}         JSON to stdout (built-in modules), report to stderr\n"
    printf "    ${CYAN}--hide-ip${RESET}      Hide server IPs/hostname/rDNS; skip external scripts\n"
    printf "    ${CYAN}--no-install${RESET}   Never install packages; skip external scripts\n"
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
    local fn="$1" title="$2" t0=$SECONDS elapsed rc
    local fails_before=$FAILS warns_before=$WARNS skips_before=$SKIPS result="ok" icon="$CHECK"
    if [[ $REPORT_MODE -eq 1 ]]; then
        start_ticker "$title" "$DONE_MODULES" "$TOTAL_MODULES"
        "$fn" >"$(mod_log "$title")" 2>&1
        rc=$?
        stop_ticker
        DONE_MODULES=$((DONE_MODULES + 1))
        DONE_TITLES+=("$title")
    else
        "$fn"
        rc=$?
    fi
    if [[ $rc -ne 0 && $FAILS -eq $fails_before ]]; then
        if [[ $REPORT_MODE -eq 1 ]]; then
            status_fail "${title}: exited with code ${rc}" >>"$(mod_log "$title")"
        else
            status_fail "${title}: exited with code ${rc}"
        fi
    fi
    elapsed=$((SECONDS - t0))
    if (( FAILS > fails_before )); then result="failed"; icon="$CROSS"
    elif (( WARNS > warns_before )); then result="warning"; icon="$WARN_S"
    elif (( SKIPS > skips_before )); then result="skipped"; icon="$INFO_S"
    fi
    record "module_${title//-/_}_status" "$result"
    record "module_${title//-/_}_elapsed_s" "$elapsed" num
    if [[ $REPORT_MODE -eq 1 ]]; then
        printf '  %s %-12s %-8s %dm %02ds\n' "$icon" "$title" "$result" $(( elapsed / 60 )) $(( elapsed % 60 ))
    fi
    MODULE_TIMES+=("$(printf '%-16s %3ds' "$title" $((SECONDS - t0)))")
}

# ═══════════════════════════════════════════════════════════════
# STRUCTURED REPORT (report mode)
# ═══════════════════════════════════════════════════════════════
report_kind() {
    case "$1" in
        info|disk|network|security|docker|speed-ru) echo "local" ;; # replay our own output
        speed-int)                        echo "speed" ;;   # extract the speed tables
        ip-check)                          echo "ipcheck" ;; # extract key findings (output is huge)
        *)                                 echo "external" ;;# replay, CR-normalized
    esac
}

scorecard() {
    # at-a-glance summary assembled from recorded metrics
    header "⚡ SCORECARD" "the server at a glance"
    local v line city country

    line=""
    v=$(rec_get cpu_model) && [[ -n "$v" ]] && line="$v"
    v=$(rec_get cpu_cores) && [[ -n "$v" ]] && line="${line:+$line · }${v} core(s)"
    v=$(rec_get cpu_eps_1t) && [[ -n "$v" ]] && line="${line:+$line · }${v%%.*} eps"
    v=$(rec_get cpu_steal_pct) && [[ -n "$v" ]] && line="${line:+$line · }steal ${v}%"
    [[ -n "$line" ]] && kv "CPU:" "$line" "$YELLOW"

    v=$(rec_get mem_total_mb)
    if [[ "$v" =~ ^[0-9]+$ ]]; then
        local avail
        avail=$(rec_get mem_avail_mb) || avail=0
        kv "Memory:" "$(awk -v t="$v" -v a="${avail:-0}" \
            'BEGIN{printf "%.1fG total · %.1fG available", t / 1024, a / 1024}')"
    fi

    line=""
    v=$(rec_get disk_seq_write_mbs) && [[ -n "$v" ]] && line="W ${v} MB/s"
    v=$(rec_get disk_seq_read_mbs) && [[ -n "$v" ]] && line="${line:+$line · }R ${v} MB/s"
    v=$(rec_get disk_rand_read_iops) && [[ -n "$v" ]] && line="${line:+$line · }4K $(fmt_iops "$v") IOPS"
    [[ -n "$line" ]] && kv "Disk:" "$line" "$YELLOW"

    line=""
    v=$(rec_get tcp_cc) && [[ -n "$v" ]] && line="$v"
    v=$(rec_get qdisc) && [[ -n "$v" ]] && line="${line:+$line+}$v"
    v=$(rec_get ping_cloudflare_avg_ms) && [[ -n "$v" ]] && line="${line:+$line · }CF ${v}ms"
    v=$(rec_get ping_yandex_avg_ms) && [[ -n "$v" ]] && line="${line:+$line · }Yandex ${v}ms"
    [[ -n "$line" ]] && kv "Network:" "$line" "$GREEN"

    line=""
    city=$(rec_get geo_city) || city=""
    country=$(rec_get geo_country) || country=""
    v=$(rec_get ipv4) && [[ -n "$v" && "$v" != "N/A" ]] && line="$v"
    v=$(rec_get isp) && [[ -n "$v" ]] && line="${line:+$line · }$v"
    [[ -n "$city$country" ]] && line="${line:+$line · }${city:-?}, ${country:-?}"
    [[ -n "$line" ]] && kv "IP:" "$line" "$CYAN"

    line=""
    v=$(rec_get ssh_root_login) && [[ -n "$v" ]] && line="root: $v"
    v=$(rec_get ssh_password_auth) && [[ -n "$v" ]] && line="${line:+$line · }passwords: $v"
    v=$(rec_get fail2ban) && [[ -n "$v" ]] && line="${line:+$line · }fail2ban: $v"
    v=$(rec_get pending_updates) && [[ -n "$v" ]] && line="${line:+$line · }updates: $v"
    [[ -n "$line" ]] && kv "Security:" "$line"

    local dr dt
    dr=$(rec_get docker_running) || dr=""
    dt=$(rec_get docker_total) || dt=""
    [[ -n "$dr" && -n "$dt" ]] && kv "Docker:" "${dr}/${dt} running"
    return 0
}

save_report() {
    # concatenate all captured logs, ANSI-stripped, into a plain-text file
    local dir="" d f title
    for d in "$PWD" "${HOME:-/root}" /tmp; do
        [[ -d "$d" && -w "$d" ]] && { dir="$d"; break; }
    done
    [[ -n "$dir" ]] || { status_warn "No writable directory for the report"; return 0; }
    REPORT_FILE=""
    f=$(mktemp "${dir%/}/server-bench-$(date +%Y%m%d-%H%M%S).log.XXXXXXXX") || {
        status_warn "Could not create a report file"
        return 0
    }
    {
        printf 'server-bench v%s — full report — %s\n' "$VERSION" "$(date '+%Y-%m-%d %H:%M:%S %Z')"
        [[ -s "$WORK_DIR/scorecard.txt" ]] && strip_ansi <"$WORK_DIR/scorecard.txt"
        for title in ${DONE_TITLES[@]+"${DONE_TITLES[@]}"}; do
            [[ -s "$(mod_log "$title")" ]] && strip_ansi <"$(mod_log "$title")"
        done
        printf '\nResults: %s failed, %s warnings, %s skipped; elapsed %ss\n' "$FAILS" "$WARNS" "$SKIPS" "$SECONDS"
    } >"$f" 2>/dev/null && REPORT_FILE="$f"
    [[ -n "$REPORT_FILE" ]] || status_warn "Could not write the report to $f"
    return 0
}

final_report() {
    if [[ ${#REC_KEYS[@]} -gt 0 ]]; then
        scorecard >"$WORK_DIR/scorecard.txt"
    else
        : >"$WORK_DIR/scorecard.txt"
    fi
    save_report
    local title log lines
    echo ""
    double_line
    printf "${BOLD}${WHITE}  📋 STRUCTURED REPORT${RESET}\n"
    double_line
    [[ -s "$WORK_DIR/scorecard.txt" ]] && cat "$WORK_DIR/scorecard.txt"
    for title in ${DONE_TITLES[@]+"${DONE_TITLES[@]}"}; do
        log=$(mod_log "$title")
        [[ -s "$log" ]] || continue
        if [[ $(rec_get "module_${title//-/_}_status") == skipped ]]; then
            cat "$log"
            continue
        fi
        case "$(report_kind "$title")" in
            local)
                cat "$log"
                ;;
            external)
                strip_ansi <"$log"
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

module_deps() {
    case "$1" in
        info) echo "timeout curl sysbench dig" ;;
        disk) echo "timeout fio" ;;
        network) echo "timeout ping dig" ;;
        speed-ru) echo "timeout iperf3 jq" ;;
        security|docker) echo "timeout" ;;
        *) echo "timeout curl" ;;
    esac
}

select_modules() {
    local id i
    for id in "$@"; do
        for (( i = 0; i < ${#MODULE_IDS[@]}; i++ )); do
            [[ "${MODULE_IDS[$i]}" == "$id" ]] && SELECTED_MODULES[i]=1
        done
    done
    return 0
}

select_preset() {
    case "$1" in
        quick) select_modules info network security docker ;;
        all) select_modules info disk network security docker ip-check ip-region speed-ru speed-int ;;
    esac
}

selected_count() {
    local n=0 selected
    for selected in "${SELECTED_MODULES[@]}"; do n=$((n + selected)); done
    printf '%s' "$n"
}

time_estimate() {
    if (( $1 < 60 )); then printf '~%ss' "$1"
    else printf '~%dm' "$(( ($1 + 59) / 60 ))"
    fi
}

show_catalog() {
    local i marker
    printf '\n  %-3s %-3s %-14s %-24s %-6s %s\n' '#' '' 'MODULE' 'CHECK' 'TIME' 'TOOLS / SOURCE'
    for (( i = 0; i < ${#MODULE_IDS[@]}; i++ )); do
        marker='[ ]'
        [[ ${SELECTED_MODULES[$i]} -eq 1 ]] && marker='[x]'
        printf '  %-3s %-3s %-14s %-24s %-6s %s%s\n' "$((i + 1))" "$marker" \
            "${MODULE_IDS[$i]}" "${MODULE_LABELS[$i]}" "$(time_estimate "${MODULE_ESTIMATES[$i]}")" \
            "$(module_deps "${MODULE_IDS[$i]}")" \
            "$([[ ${MODULE_SCOPES[$i]} == external ]] && printf ' + upstream dependencies')"
    done
    printf '\n  Times are estimates; busy endpoints and package installs can take longer.\n'
}

parse_menu_selection() {
    local input="${1//,/ }" token first last i
    local tokens=() next=(0 0 0 0 0 0 0 0 0 0 0 0 0)
    read -r -a tokens <<<"$input"
    [[ ${#tokens[@]} -gt 0 ]] || return 1
    for token in "${tokens[@]}"; do
        [[ "$token" =~ ^([0-9]{1,2})(-([0-9]{1,2}))?$ ]] || return 1
        first=$((10#${BASH_REMATCH[1]}))
        last=$first
        [[ -n "${BASH_REMATCH[3]:-}" ]] && last=$((10#${BASH_REMATCH[3]}))
        (( first >= 1 && last <= ${#MODULE_IDS[@]} && first <= last )) || return 1
        for (( i = first; i <= last; i++ )); do next[i - 1]=1; done
    done
    SELECTED_MODULES=("${next[@]}")
}

choose_modules() {
    if [[ ! -t 0 || ! -t 1 ]]; then
        printf '%s\n' '--menu requires an interactive terminal; use --list and module flags for automation.' >&2
        return 2
    fi
    [[ $(selected_count) -gt 0 ]] || select_preset quick
    local input i seconds
    while :; do
        show_catalog
        seconds=0
        for (( i = 0; i < ${#MODULE_IDS[@]}; i++ )); do
            (( seconds += SELECTED_MODULES[i] * MODULE_ESTIMATES[i] ))
        done
        printf '\n  Selected: %s modules, %s total.\n' "$(selected_count)" "$(time_estimate "$seconds")"
        printf '  Numbers/ranges (1,3-5), quick, all; Enter runs selection; q quits.\n  > '
        IFS= read -r input || return 130
        case "$input" in
            '') return 0 ;;
            q|Q) return 130 ;;
            quick|all)
                SELECTED_MODULES=(0 0 0 0 0 0 0 0 0 0 0 0 0)
                select_preset "$input" ;;
            *) parse_menu_selection "$input" || printf '  Invalid selection; use numbers 1-%s.\n' "${#MODULE_IDS[@]}" ;;
        esac
    done
}

skip_external() {
    status_skip "External scripts are disabled by --json, --no-install or --hide-ip"
}

main() {
    local want_help=0 want_list=0 want_menu=0 i dep
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --all) select_preset all ;;
            --quick) select_preset quick ;;
            --info|--disk|--network|--security|--docker|--speed-ru|--speed-int|--instagram|--dpi|--geoblock|--yabs)
                select_modules "${1#--}" ;;
            --ip) select_modules ip-check ip-region ;;
            --ip-check|--ip-region) select_modules "${1#--}" ;;
            --speed) select_modules speed-ru speed-int ;;
            --menu) want_menu=1 ;;
            --list) want_list=1 ;;
            --live) LIVE_MODE=1; FORCE_REPORT=0 ;;
            --report) FORCE_REPORT=1; LIVE_MODE=0 ;;
            --json) JSON_MODE=1 ;;
            --hide-ip) HIDE_IP=1 ;;
            --no-install) NO_INSTALL=1 ;;
            --no-color) USE_COLOR=0 ;;
            --version|-V) printf 'server-bench v%s\n' "$VERSION"; return 0 ;;
            --help|-h) want_help=1 ;;
            *) printf 'Unknown option: %s (see --help)\n' "$1" >&2; return 2 ;;
        esac
        shift
    done
    init_colors
    if [[ $want_help -eq 1 ]]; then show_help; return 0; fi
    if [[ $want_list -eq 1 ]]; then show_catalog; return 0; fi
    if [[ $want_menu -eq 1 ]]; then
        if [[ $JSON_MODE -eq 1 ]]; then
            printf '%s\n' '--menu cannot be combined with --json; select modules with flags.' >&2
            return 2
        fi
        choose_modules || return $?
    fi
    # Output/control flags by themselves use the same default as no flags.
    [[ $(selected_count) -gt 0 ]] || select_preset all
    if [[ $(uname -s) != Linux ]]; then
        printf 'server-bench diagnostics require Linux. Use --help or --list to inspect the CLI.\n' >&2
        return 1
    fi
    export LC_ALL=C
    SECONDS=0
    if [[ $JSON_MODE -eq 1 ]]; then exec 3>&1 1>&2; else exec 3>&1; fi
    init_privileges
    show_banner

    WORK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/server-bench.XXXXXXXX") || {
        status_fail "Could not create a temporary work directory"
        return 1
    }
    trap cleanup EXIT
    trap 'echo ""; exit 130' INT
    trap 'echo ""; exit 143' TERM
    record "version" "$VERSION"
    record "date" "$(date -Is)"

    local deps=() restricted=0
    [[ $JSON_MODE -eq 1 || $NO_INSTALL -eq 1 || $HIDE_IP -eq 1 ]] && restricted=1
    for (( i = 0; i < ${#MODULE_IDS[@]}; i++ )); do
        [[ ${SELECTED_MODULES[$i]} -eq 1 ]] || continue
        [[ $restricted -eq 1 && ${MODULE_SCOPES[$i]} == external ]] && continue
        for dep in $(module_deps "${MODULE_IDS[$i]}"); do deps+=("$dep"); done
    done
    if [[ ${#deps[@]} -gt 0 ]]; then ensure_deps "${deps[@]}"; fi
    if [[ ${#deps[@]} -gt 0 ]] && ! command_exists timeout; then
        status_fail "GNU timeout (coreutils) is required to bound diagnostic commands"
        return 1
    fi

    TOTAL_MODULES=$(selected_count)
    if [[ $JSON_MODE -eq 0 ]]; then
        if [[ $FORCE_REPORT -eq 1 || ( $LIVE_MODE -eq 0 && $TOTAL_MODULES -gt 1 && -t 1 ) ]]; then
            REPORT_MODE=1
        fi
    fi
    if [[ $REPORT_MODE -eq 1 ]]; then
        printf '  Running %d modules (structured report at the end)\n\n' "$TOTAL_MODULES"
    fi
    for (( i = 0; i < ${#MODULE_IDS[@]}; i++ )); do
        [[ ${SELECTED_MODULES[$i]} -eq 1 ]] || continue
        if [[ $restricted -eq 1 && ${MODULE_SCOPES[$i]} == external ]]; then
            run_module skip_external "${MODULE_IDS[$i]}"
        else
            run_module "${MODULE_FUNCTIONS[$i]}" "${MODULE_IDS[$i]}"
        fi
    done
    [[ $REPORT_MODE -eq 1 ]] && final_report
    record "elapsed_s" "$SECONDS" num
    record "fails" "$FAILS" num
    record "warns" "$WARNS" num
    record "skips" "$SKIPS" num
    show_summary
    [[ $JSON_MODE -eq 1 ]] && emit_json
    return 0
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
