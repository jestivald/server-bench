#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  Server Benchmark Suite v1.0                                 ║
# ║  All-in-one server diagnostics & performance testing         ║
# ╚══════════════════════════════════════════════════════════════╝
#
# Usage: bash server-bench.sh [options]
#   --all         Run all tests (default)
#   --info        System info only
#   --speed       Speed tests only (RU + international)
#   --ip          IP checks only
#   --disk        Disk benchmark only
#   --network     Network tests only
#   --instagram   Instagram audio block check
#   --dpi         DPI censorship check (for RU servers)
#   --help        Show this help
#
# Author: generated with Claude
# License: MIT

set -euo pipefail

# ═══════════════════════════════════════════════════════════════
# AUTO-INSTALL DEPENDENCIES
# ═══════════════════════════════════════════════════════════════
install_deps() {
    local needed=()
    local pkg_map=(
        "sysbench:sysbench"
        "fio:fio"
        "dig:dnsutils"
        "curl:curl"
        "wget:wget"
        "ping:iputils-ping"
        "jq:jq"
    )

    for entry in "${pkg_map[@]}"; do
        local cmd="${entry%%:*}"
        local pkg="${entry##*:}"
        if ! command -v "$cmd" &>/dev/null; then
            needed+=("$pkg")
        fi
    done

    if [[ ${#needed[@]} -gt 0 ]]; then
        echo -e "\033[0;34mℹ\033[0m Installing missing packages: ${needed[*]}"
        if command -v apt-get &>/dev/null; then
            sudo apt-get update -qq &>/dev/null
            sudo apt-get install -y -qq "${needed[@]}" &>/dev/null
        elif command -v yum &>/dev/null; then
            sudo yum install -y -q "${needed[@]}" &>/dev/null
        elif command -v dnf &>/dev/null; then
            sudo dnf install -y -q "${needed[@]}" &>/dev/null
        else
            echo -e "\033[1;33m⚠\033[0m Could not auto-install. Please install manually: ${needed[*]}"
        fi
        echo -e "\033[0;32m✔\033[0m Dependencies installed"
    fi
}

install_deps

# ═══════════════════════════════════════════════════════════════
# COLORS & FORMATTING
# ═══════════════════════════════════════════════════════════════
if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    MAGENTA='\033[0;35m'
    CYAN='\033[0;36m'
    WHITE='\033[1;37m'
    GRAY='\033[0;90m'
    BOLD='\033[1m'
    DIM='\033[2m'
    RESET='\033[0m'
    BG_BLUE='\033[44m'
    BG_GREEN='\033[42m'
    BG_RED='\033[41m'
    BG_YELLOW='\033[43m'
else
    RED='' GREEN='' YELLOW='' BLUE='' MAGENTA='' CYAN='' WHITE='' GRAY=''
    BOLD='' DIM='' RESET='' BG_BLUE='' BG_GREEN='' BG_RED='' BG_YELLOW=''
fi

# Symbols
CHECK="${GREEN}✔${RESET}"
CROSS="${RED}✘${RESET}"
ARROW="${CYAN}➜${RESET}"
STAR="${YELLOW}★${RESET}"
WARN="${YELLOW}⚠${RESET}"
INFO="${BLUE}ℹ${RESET}"
GEAR="${MAGENTA}⚙${RESET}"
GLOBE="${CYAN}🌐${RESET}"
ROCKET="${MAGENTA}🚀${RESET}"
LOCK="${RED}🔒${RESET}"
DISK_ICON="${BLUE}💾${RESET}"
CPU_ICON="${RED}🔥${RESET}"

# ═══════════════════════════════════════════════════════════════
# UTILITY FUNCTIONS
# ═══════════════════════════════════════════════════════════════

TERM_WIDTH=$(tput cols 2>/dev/null || echo 70)
[[ $TERM_WIDTH -gt 80 ]] && TERM_WIDTH=80

line() {
    printf "${GRAY}"
    printf '%.0s─' $(seq 1 "$TERM_WIDTH")
    printf "${RESET}\n"
}

double_line() {
    printf "${BLUE}"
    printf '%.0s═' $(seq 1 "$TERM_WIDTH")
    printf "${RESET}\n"
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

status_ok() {
    printf "  ${CHECK} %s\n" "$1"
}

status_fail() {
    printf "  ${CROSS} %s\n" "$1"
}

status_warn() {
    printf "  ${WARN} %s\n" "$1"
}

status_info() {
    printf "  ${INFO} %s\n" "$1"
}

spinner() {
    local pid=$1
    local msg="${2:-Working...}"
    local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    local i=0
    while kill -0 "$pid" 2>/dev/null; do
        printf "\r  ${CYAN}${frames[$i]}${RESET} ${DIM}%s${RESET}" "$msg"
        i=$(( (i + 1) % ${#frames[@]} ))
        sleep 0.1
    done
    printf "\r%-${TERM_WIDTH}s\r" " "
}

command_exists() {
    command -v "$1" &>/dev/null
}

install_if_missing() {
    local cmd="$1"
    local pkg="${2:-$1}"
    if ! command_exists "$cmd"; then
        status_info "Installing ${pkg}..."
        if command_exists apt-get; then
            sudo apt-get install -y -qq "$pkg" &>/dev/null
        elif command_exists yum; then
            sudo yum install -y -q "$pkg" &>/dev/null
        elif command_exists dnf; then
            sudo dnf install -y -q "$pkg" &>/dev/null
        fi
    fi
}

TMPDIR=$(mktemp -d)
RESULTS_FILE="$TMPDIR/results.txt"
trap 'rm -rf "$TMPDIR"' EXIT

START_TIME=$(date +%s)

# ═══════════════════════════════════════════════════════════════
# BANNER
# ═══════════════════════════════════════════════════════════════
show_banner() {
    clear 2>/dev/null || true
    echo ""
    printf "${BOLD}${CYAN}"
    cat << 'BANNER'
   ┌─────────────────────────────────────────────────┐
   │   ___                          ___              │
   │  / __| ___ _ ___ _____ _ _   | _ ) ___ _ _  __ │
   │  \__ \/ -_) '_\ V / -_) '_|  | _ \/ -_) ' \/ _|│
   │  |___/\___|_|  \_/\___|_|    |___/\___|_||_\__|│
   │                                                 │
   │         All-in-One Server Diagnostics           │
   └─────────────────────────────────────────────────┘
BANNER
    printf "${RESET}"
    printf "${DIM}${GRAY}   v1.0 • $(date '+%Y-%m-%d %H:%M:%S %Z')${RESET}\n"
    echo ""
}

# ═══════════════════════════════════════════════════════════════
# SYSTEM INFO
# ═══════════════════════════════════════════════════════════════
test_system_info() {
    header "SYSTEM INFORMATION" "Hardware, OS & network configuration"

    # OS
    section "Operating System"
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        kv "OS:" "${PRETTY_NAME:-$NAME $VERSION}" "$GREEN"
    fi
    kv "Kernel:" "$(uname -r)"
    kv "Arch:" "$(uname -m)"
    kv "Hostname:" "$(hostname)"
    kv "Uptime:" "$(uptime -p 2>/dev/null || uptime | sed 's/.*up //' | sed 's/,.*//')"

    # CPU
    section "CPU"
    local cpu_model cpu_cores cpu_freq
    cpu_model=$(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2 | sed 's/^ //' || echo "Unknown")
    cpu_cores=$(nproc 2>/dev/null || grep -c ^processor /proc/cpuinfo 2>/dev/null || echo "?")
    cpu_freq=$(grep -m1 'cpu MHz' /proc/cpuinfo 2>/dev/null | cut -d: -f2 | sed 's/^ //' | cut -d. -f1 || echo "?")
    kv "Model:" "$cpu_model" "$YELLOW"
    kv "Cores:" "$cpu_cores"
    kv "Frequency:" "${cpu_freq} MHz"

    # CPU quick bench
    if command_exists sysbench; then
        section "CPU Benchmark"
        status_info "Running sysbench CPU test (single thread)..."
        local cpu_result
        cpu_result=$(sysbench cpu run --threads=1 2>/dev/null)
        local events_per_sec
        events_per_sec=$(echo "$cpu_result" | grep "events per second" | awk '{print $NF}')
        if [[ -n "$events_per_sec" ]]; then
            kv "Events/sec:" "$events_per_sec" "$YELLOW"
            local eps_int=${events_per_sec%.*}
            if [[ $eps_int -gt 3000 ]]; then
                status_ok "Excellent CPU performance (dedicated likely)"
            elif [[ $eps_int -gt 1500 ]]; then
                status_ok "Good CPU performance"
            elif [[ $eps_int -gt 800 ]]; then
                status_warn "Average CPU (shared/throttled?)"
            else
                status_fail "Low CPU performance (heavily shared)"
            fi
        fi
    else
        status_warn "sysbench not available (auto-install failed?)"
    fi

    # Memory
    section "Memory"
    local mem_total mem_used mem_avail
    mem_total=$(free -h 2>/dev/null | awk '/^Mem:/{print $2}')
    mem_used=$(free -h 2>/dev/null | awk '/^Mem:/{print $3}')
    mem_avail=$(free -h 2>/dev/null | awk '/^Mem:/{print $7}')
    kv "Total:" "$mem_total" "$YELLOW"
    kv "Used:" "$mem_used"
    kv "Available:" "$mem_avail" "$GREEN"

    local swap_total
    swap_total=$(free -h 2>/dev/null | awk '/^Swap:/{print $2}')
    kv "Swap:" "$swap_total"

    # Disk
    section "Disk"
    printf "  ${GRAY}%-20s %-8s %-8s %-8s %-6s${RESET}\n" "MOUNT" "SIZE" "USED" "AVAIL" "USE%"
    line
    df -h --output=target,size,used,avail,pcent 2>/dev/null | grep -vE '^Mounted|tmpfs|devtmpfs|overlay|udev' | while read -r mount size used avail pct; do
        local pct_num=${pct%\%}
        local color="$GREEN"
        [[ $pct_num -gt 70 ]] && color="$YELLOW"
        [[ $pct_num -gt 90 ]] && color="$RED"
        printf "  ${WHITE}%-20s${RESET} %-8s %-8s %-8s ${color}%-6s${RESET}\n" "$mount" "$size" "$used" "$avail" "$pct"
    done

    # Network interfaces
    section "Network"
    local ipv4 ipv6
    ipv4=$(curl -4 -s --max-time 5 ifconfig.me 2>/dev/null || curl -4 -s --max-time 5 icanhazip.com 2>/dev/null || echo "N/A")
    ipv6=$(curl -6 -s --max-time 5 ifconfig.me 2>/dev/null || curl -6 -s --max-time 5 icanhazip.com 2>/dev/null || echo "N/A")
    kv "IPv4:" "$ipv4" "$YELLOW"
    kv "IPv6:" "$ipv6"

    # Geo info
    local geo
    geo=$(curl -s --max-time 5 "http://ip-api.com/line/$ipv4?fields=country,regionName,city,isp,as" 2>/dev/null)
    if [[ -n "$geo" ]]; then
        local country city isp asn
        country=$(echo "$geo" | sed -n '1p')
        city=$(echo "$geo" | sed -n '3p')
        isp=$(echo "$geo" | sed -n '4p')
        asn=$(echo "$geo" | sed -n '5p')
        kv "Location:" "$city, $country"
        kv "ISP:" "$isp"
        kv "AS:" "$asn"
    fi
}

# ═══════════════════════════════════════════════════════════════
# DISK BENCHMARK
# ═══════════════════════════════════════════════════════════════
test_disk() {
    header "DISK BENCHMARK" "Sequential read/write performance"

    local test_file="$TMPDIR/disk_bench"

    section "Write Speed"
    # Write test with dd
    local write_result
    write_result=$(dd if=/dev/zero of="$test_file" bs=1M count=512 conv=fdatasync 2>&1 | tail -1)
    local write_speed
    write_speed=$(echo "$write_result" | grep -oP '[\d.]+ [MGKT]B/s' || echo "$write_result" | awk '{print $(NF-1), $NF}')
    kv "Sequential Write:" "$write_speed" "$YELLOW"
    rm -f "$test_file"

    section "Read Speed"
    # Create test file
    dd if=/dev/zero of="$test_file" bs=1M count=512 2>/dev/null
    # Clear cache
    sync
    echo 3 | sudo tee /proc/sys/vm/drop_caches &>/dev/null 2>/dev/null || true
    local read_result
    read_result=$(dd if="$test_file" of=/dev/null bs=1M 2>&1 | tail -1)
    local read_speed
    read_speed=$(echo "$read_result" | grep -oP '[\d.]+ [MGKT]B/s' || echo "$read_result" | awk '{print $(NF-1), $NF}')
    kv "Sequential Read:" "$read_speed" "$YELLOW"
    rm -f "$test_file"

    # fio if available
    if command_exists fio; then
        section "Random I/O (fio)"
        local fio_result
        fio_result=$(fio --name=randtest --ioengine=libaio --iodepth=32 --rw=randread --bs=4k \
            --direct=1 --size=256M --numjobs=1 --runtime=10 --group_reporting \
            --filename="$test_file" 2>/dev/null)
        local iops
        iops=$(echo "$fio_result" | grep -oP 'IOPS=\K[\d.k]+' | head -1)
        kv "4K Random Read:" "${iops} IOPS" "$YELLOW"
        rm -f "$test_file"
    else
        status_warn "fio not available (auto-install failed?)"
    fi
}

# ═══════════════════════════════════════════════════════════════
# SPEED TESTS
# ═══════════════════════════════════════════════════════════════
test_speed_ru() {
    header "SPEED TEST — RUSSIA" "Testing connectivity to Russian providers"

    if command_exists curl; then
        status_info "Running bench.gig.ovh (RU providers)..."
        echo ""
        wget -qO- bench.gig.ovh 2>/dev/null | bash 2>/dev/null || {
            status_warn "bench.gig.ovh unavailable, trying bench.tlab.pw..."
            wget -qO- bench.tlab.pw 2>/dev/null | bash 2>/dev/null || status_fail "RU speed test unavailable"
        }
    fi
}

test_speed_int() {
    header "SPEED TEST — INTERNATIONAL" "Testing global connectivity"

    if command_exists curl; then
        status_info "Running bench.sh (international)..."
        echo ""
        wget -qO- bench.sh 2>/dev/null | bash 2>/dev/null || {
            status_warn "bench.sh unavailable, trying speed.tlab.pw..."
            wget -qO- speed.tlab.pw 2>/dev/null | bash 2>/dev/null || status_fail "International speed test unavailable"
        }
    fi
}

# ═══════════════════════════════════════════════════════════════
# IP CHECKS
# ═══════════════════════════════════════════════════════════════
test_ip_check() {
    header "IP QUALITY CHECK" "Checking IP reputation & blocks"

    section "IP.Check.Place"
    status_info "Running IP check (this may take a minute)..."
    echo ""
    bash <(curl -Ls IP.Check.Place) -l en 2>/dev/null || status_fail "IP.Check.Place unavailable"
}

test_ip_region() {
    header "IP REGION CHECK" "What region services see from your IP"

    section "IP Region"
    status_info "Running IP region check..."
    echo ""
    bash <(wget -qO- https://ipregion.xyz) 2>/dev/null || {
        bash <(wget -qO- https://github.com/vernette/ipregion/raw/master/ipregion.sh) 2>/dev/null || status_fail "IP region check unavailable"
    }
}

# ═══════════════════════════════════════════════════════════════
# INSTAGRAM CHECK
# ═══════════════════════════════════════════════════════════════
test_instagram() {
    header "INSTAGRAM AUDIO CHECK" "Testing if Instagram audio is blocked"

    status_info "Running Instagram audio check..."
    echo ""
    bash <(curl -L -s https://bench.openode.xyz/checker_inst.sh) 2>/dev/null || status_fail "Instagram check unavailable"
}

# ═══════════════════════════════════════════════════════════════
# DPI CHECK
# ═══════════════════════════════════════════════════════════════
test_dpi() {
    header "DPI CENSORSHIP CHECK" "Testing DPI blocks (for Russian servers)"

    status_info "Running CensorCheck..."
    echo ""
    bash <(wget -qO- https://github.com/vernette/censorcheck/raw/master/censorcheck.sh) --mode dpi 2>/dev/null || status_fail "CensorCheck unavailable"
}

# ═══════════════════════════════════════════════════════════════
# NETWORK TESTS (ping, traceroute, DNS)
# ═══════════════════════════════════════════════════════════════
test_network() {
    header "NETWORK DIAGNOSTICS" "Latency & DNS checks"

    section "Ping Latency"
    local targets=("1.1.1.1:Cloudflare" "8.8.8.8:Google" "77.88.8.8:Yandex" "208.67.222.222:OpenDNS")
    printf "  ${GRAY}%-22s %-12s %-12s %-12s${RESET}\n" "TARGET" "MIN" "AVG" "MAX"
    line

    for entry in "${targets[@]}"; do
        local ip="${entry%%:*}"
        local name="${entry##*:}"
        local ping_result
        ping_result=$(ping -c 3 -W 3 "$ip" 2>/dev/null | tail -1)
        if [[ "$ping_result" == *"min/avg/max"* ]]; then
            local stats
            stats=$(echo "$ping_result" | grep -oP '[\d.]+/[\d.]+/[\d.]+')
            local min_ms avg_ms max_ms
            min_ms=$(echo "$stats" | cut -d/ -f1)
            avg_ms=$(echo "$stats" | cut -d/ -f2)
            max_ms=$(echo "$stats" | cut -d/ -f3)
            local color="$GREEN"
            local avg_int=${avg_ms%.*}
            [[ $avg_int -gt 50 ]] && color="$YELLOW"
            [[ $avg_int -gt 150 ]] && color="$RED"
            printf "  ${WHITE}%-22s${RESET} %-12s ${color}%-12s${RESET} %-12s\n" "$name ($ip)" "${min_ms}ms" "${avg_ms}ms" "${max_ms}ms"
        else
            printf "  ${WHITE}%-22s${RESET} ${RED}%-12s${RESET}\n" "$name ($ip)" "timeout"
        fi
    done

    section "DNS Resolution"
    local dns_targets=("google.com" "youtube.com" "telegram.org" "instagram.com" "cloudflare.com")
    for domain in "${dns_targets[@]}"; do
        local start_ns end_ns dns_ms resolved
        start_ns=$(date +%s%N)
        resolved=$(dig +short "$domain" A 2>/dev/null | head -1)
        end_ns=$(date +%s%N)
        dns_ms=$(( (end_ns - start_ns) / 1000000 ))
        if [[ -n "$resolved" ]]; then
            local color="$GREEN"
            [[ $dns_ms -gt 100 ]] && color="$YELLOW"
            [[ $dns_ms -gt 500 ]] && color="$RED"
            printf "  ${CHECK} %-22s ${color}%sms${RESET}  ${DIM}→ %s${RESET}\n" "$domain" "$dns_ms" "$resolved"
        else
            printf "  ${CROSS} %-22s ${RED}FAILED${RESET}\n" "$domain"
        fi
    done
}

# ═══════════════════════════════════════════════════════════════
# SECURITY QUICK CHECK
# ═══════════════════════════════════════════════════════════════
test_security() {
    header "SECURITY QUICK CHECK" "Basic server hardening audit"

    section "SSH Configuration"
    local sshd_config="/etc/ssh/sshd_config"
    if [[ -f "$sshd_config" ]]; then
        # Root login
        local root_login
        root_login=$(grep -i "^PermitRootLogin" "$sshd_config" 2>/dev/null | awk '{print $2}' || echo "default")
        if [[ "$root_login" == "no" ]]; then
            status_ok "Root login disabled"
        elif [[ "$root_login" == "prohibit-password" || "$root_login" == "without-password" ]]; then
            status_ok "Root login: key only"
        else
            status_warn "Root login: ${root_login:-default (yes)}"
        fi

        # Password auth
        local pass_auth
        pass_auth=$(grep -i "^PasswordAuthentication" "$sshd_config" 2>/dev/null | awk '{print $2}' || echo "default")
        if [[ "$pass_auth" == "no" ]]; then
            status_ok "Password authentication disabled"
        else
            status_warn "Password authentication: ${pass_auth:-default (yes)}"
        fi

        # SSH port
        local ssh_port
        ssh_port=$(grep -i "^Port " "$sshd_config" 2>/dev/null | awk '{print $2}' || echo "22")
        if [[ "$ssh_port" != "22" ]]; then
            status_ok "SSH port: $ssh_port (non-default)"
        else
            status_info "SSH port: 22 (default)"
        fi
    fi

    # Firewall
    section "Firewall"
    if command_exists ufw; then
        local ufw_status
        ufw_status=$(sudo ufw status 2>/dev/null | head -1)
        if echo "$ufw_status" | grep -q "active"; then
            status_ok "UFW: active"
        else
            status_warn "UFW: inactive"
        fi
    elif command_exists iptables; then
        local rules_count
        rules_count=$(sudo iptables -L 2>/dev/null | grep -c -v '^Chain\|^target\|^$' || echo "0")
        kv "iptables rules:" "$rules_count"
    else
        status_info "No firewall detected"
    fi

    # Fail2ban
    section "Intrusion Prevention"
    if command_exists fail2ban-client; then
        local f2b_status
        f2b_status=$(sudo fail2ban-client status 2>/dev/null | grep "Number of jail" | awk '{print $NF}')
        status_ok "Fail2ban: active ($f2b_status jails)"
    else
        status_warn "Fail2ban not installed"
    fi

    # Updates
    section "Pending Updates"
    if command_exists apt; then
        local updates
        updates=$(apt list --upgradable 2>/dev/null | grep -c "upgradable" || echo "0")
        if [[ "$updates" -gt 0 ]]; then
            status_warn "$updates packages can be updated"
        else
            status_ok "System is up to date"
        fi
    fi
}

# ═══════════════════════════════════════════════════════════════
# DOCKER STATUS
# ═══════════════════════════════════════════════════════════════
test_docker() {
    header "DOCKER STATUS" "Running containers & resource usage"

    if ! command_exists docker; then
        status_info "Docker not installed"
        return
    fi

    section "Containers"
    printf "  ${GRAY}%-30s %-15s %-12s %s${RESET}\n" "NAME" "STATUS" "PORTS" "IMAGE"
    line
    docker ps --format '{{.Names}}\t{{.Status}}\t{{.Ports}}\t{{.Image}}' 2>/dev/null | while IFS=$'\t' read -r name status ports image; do
        local color="$GREEN"
        echo "$status" | grep -q "unhealthy" && color="$RED"
        echo "$status" | grep -q "Restarting" && color="$RED"
        # Truncate long fields
        [[ ${#name} -gt 28 ]] && name="${name:0:25}..."
        [[ ${#image} -gt 30 ]] && image="${image:0:27}..."
        local short_ports
        short_ports=$(echo "$ports" | sed 's/0.0.0.0://g' | cut -c1-12)
        printf "  ${WHITE}%-30s${RESET} ${color}%-15s${RESET} %-12s ${DIM}%s${RESET}\n" "$name" "$(echo "$status" | cut -d' ' -f1-2)" "$short_ports" "$image"
    done

    local total running
    total=$(docker ps -a --format '{{.ID}}' 2>/dev/null | wc -l)
    running=$(docker ps --format '{{.ID}}' 2>/dev/null | wc -l)
    echo ""
    kv "Total containers:" "$total"
    kv "Running:" "$running" "$GREEN"

    # Docker disk usage
    section "Docker Disk Usage"
    docker system df 2>/dev/null | while read -r line; do
        printf "  %s\n" "$line"
    done
}

# ═══════════════════════════════════════════════════════════════
# SUMMARY
# ═══════════════════════════════════════════════════════════════
show_summary() {
    local end_time=$(date +%s)
    local elapsed=$(( end_time - START_TIME ))
    local minutes=$(( elapsed / 60 ))
    local seconds=$(( elapsed % 60 ))

    echo ""
    double_line
    printf "${BOLD}${GREEN}  ✔ All tests completed in ${minutes}m ${seconds}s${RESET}\n"
    printf "${DIM}${GRAY}  Results generated on $(date '+%Y-%m-%d %H:%M:%S %Z')${RESET}\n"
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
    printf "  ${BOLD}Options:${RESET}\n"
    printf "    ${CYAN}--all${RESET}          Run all tests (default)\n"
    printf "    ${CYAN}--info${RESET}         System info + CPU bench + security check\n"
    printf "    ${CYAN}--speed${RESET}        Speed tests (RU + international)\n"
    printf "    ${CYAN}--speed-ru${RESET}     Speed test to Russian providers only\n"
    printf "    ${CYAN}--speed-int${RESET}    Speed test to international providers only\n"
    printf "    ${CYAN}--ip${RESET}           IP quality + region checks\n"
    printf "    ${CYAN}--disk${RESET}         Disk benchmark\n"
    printf "    ${CYAN}--network${RESET}      Ping & DNS tests\n"
    printf "    ${CYAN}--docker${RESET}       Docker status\n"
    printf "    ${CYAN}--security${RESET}     Security audit\n"
    printf "    ${CYAN}--instagram${RESET}    Instagram audio block check\n"
    printf "    ${CYAN}--dpi${RESET}          DPI censorship check (RU servers)\n"
    printf "    ${CYAN}--quick${RESET}        Quick: info + network + security + docker\n"
    printf "    ${CYAN}--help${RESET}         Show this help\n"
    echo ""
    printf "  ${DIM}Multiple options can be combined: bash server-bench.sh --info --disk --network${RESET}\n"
    echo ""
}

# ═══════════════════════════════════════════════════════════════
# MAIN
# ═══════════════════════════════════════════════════════════════
main() {
    local run_info=false run_disk=false run_speed_ru=false run_speed_int=false
    local run_ip=false run_ip_region=false run_instagram=false run_dpi=false
    local run_network=false run_security=false run_docker=false
    local run_all=false run_quick=false

    if [[ $# -eq 0 ]]; then
        run_all=true
    fi

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --all)       run_all=true ;;
            --info)      run_info=true ;;
            --disk)      run_disk=true ;;
            --speed)     run_speed_ru=true; run_speed_int=true ;;
            --speed-ru)  run_speed_ru=true ;;
            --speed-int) run_speed_int=true ;;
            --ip)        run_ip=true; run_ip_region=true ;;
            --network)   run_network=true ;;
            --security)  run_security=true ;;
            --docker)    run_docker=true ;;
            --instagram) run_instagram=true ;;
            --dpi)       run_dpi=true ;;
            --quick)     run_quick=true ;;
            --help|-h)   show_help; exit 0 ;;
            *)           echo "Unknown option: $1"; show_help; exit 1 ;;
        esac
        shift
    done

    if $run_all; then
        run_info=true; run_disk=true; run_network=true; run_security=true
        run_docker=true; run_ip=true; run_ip_region=true
        run_speed_ru=true; run_speed_int=true
    fi

    if $run_quick; then
        run_info=true; run_network=true; run_security=true; run_docker=true
    fi

    show_banner

    $run_info      && test_system_info
    $run_disk      && test_disk
    $run_network   && test_network
    $run_security  && test_security
    $run_docker    && test_docker
    $run_ip        && test_ip_check
    $run_ip_region && test_ip_region
    $run_speed_ru  && test_speed_ru
    $run_speed_int && test_speed_int
    $run_instagram && test_instagram
    $run_dpi       && test_dpi

    show_summary
}

main "$@"
