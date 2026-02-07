#!/bin/sh
# GL.iNet Router Toolkit
# Author: phantasm22
# License: GPL-3.0
# Version: 2026-02-07
#
# This script provides system utilities for GL.iNet routers including:
# - Hardware information display
# - AdGuardHome management
# - Zswap configuration
# - CPU stress testing and benchmarking
# - Disk I/O benchmarking
# - System configuration viewer

# -----------------------------
# Color & Emoji
# -----------------------------
RESET="\033[0m"
CYAN="\033[36m"
GREEN="\033[32m"
RED="\033[31m"
YELLOW="\033[33m"
BLUE="\033[34m"

SPLASH="
   _____ _          _ _   _      _   
  / ____| |        (_) \\ | |    | |  
 | |  __| |  ______ _|  \\| | ___| |_ 
 | | |_ | | |______| | . \` |/ _ \\ __|
 | |__| | |____    | | |\\  |  __/ |_ 
  \\_____|______|   |_|_| \\_|\\___|\\__|

         GL.iNet Router Toolkit
"

# -----------------------------
# Global Variables
# -----------------------------
SCRIPT_VERSION="2026-02-07"
AGH_CONFIG="/etc/adguardhome.yaml"
AGH_INIT="/etc/init.d/adguardhome"
BLA_BOX="┤ ┴ ├ ┬"  # spinner frames
opkg_updated=0

# -----------------------------
# Utility Functions
# -----------------------------
spinner() {
    pid=$1
    i=0
    task=$2
    while kill -0 "$pid" 2>/dev/null; do
        frame=$(printf "%s" "$BLA_BOX" | cut -d' ' -f$((i % 4 + 1)))
        printf "\r⏳  %s... %-20s" "$task" "$frame"
        if command -v usleep >/dev/null 2>&1; then
            usleep 200000
        else
            sleep 1
        fi
        i=$((i+1))
    done
    printf "\r✅  %s... Done!%-20s\n" "$task" " "
}

press_any_key() {
    printf "\nPress any key to continue..."
    read -r _ </dev/tty
}

print_header() {
    printf "\n%b\n" "${BLUE}========================================${RESET}"
    printf "%b\n" "${BLUE}$1${RESET}"
    printf "%b\n" "${BLUE}========================================${RESET}\n"
}

print_success() {
    printf "%b\n" "${GREEN}✅ $1${RESET}"
}

print_error() {
    printf "%b\n" "${RED}❌ $1${RESET}"
}

print_warning() {
    printf "%b\n" "${YELLOW}⚠️  $1${RESET}"
}

# -----------------------------
# System Detection Functions
# -----------------------------

# Install lscpu if not present
ensure_lscpu() {
    if ! command -v lscpu >/dev/null 2>&1; then
        print_warning "lscpu not found, installing..."
        if [ "$opkg_updated" -eq 0 ]; then
            opkg update >/dev/null 2>&1
            opkg_updated=1
        fi
        opkg install lscpu >/dev/null 2>&1
        if command -v lscpu >/dev/null 2>&1; then
            print_success "lscpu installed"
        else
            print_error "Failed to install lscpu"
            return 1
        fi
    fi
    return 0
}

# Parse CPU vendor/model from device-tree
get_cpu_vendor_model() {
    if [ -f /proc/device-tree/compatible ]; then
        result=$(tr '\0' '\n' < /proc/device-tree/compatible 2>/dev/null | grep -iE '^(mediatek|qcom|qca),' | head -1 | sed -E 's/^(mediatek|qcom|qca),/\1 /i; s/mt/MT/i; s/ipq/IPQ/i; s/qca/QCA/i')
        
        if [ -n "$result" ]; then
            printf "%s" "$result"
        else
            printf "Unknown"
        fi
    else
        printf "Unknown"
    fi
}

# -----------------------------
# 1) Hardware Information Display
# -----------------------------
show_hardware_info() {
    print_header "Hardware Information"
    
    # System Model
    printf "%b\n" "${CYAN}System Information:${RESET}"
    if command -v uci >/dev/null 2>&1; then
        hostname=$(uci get system.@system[0].hostname 2>/dev/null)
        [ -n "$hostname" ] && printf "Model: %b%s%b\n" "${GREEN}" "$hostname" "${RESET}"
    fi
    
    if [ -f /etc/glversion ]; then
        firmware=$(cat /etc/glversion 2>/dev/null)
        [ -n "$firmware" ] && printf "Firmware: %b%s%b\n" "${GREEN}" "$firmware" "${RESET}"
    fi
    
    if [ -f /etc/board.json ]; then
        board=$(grep -o '"model"[[:space:]]*:[[:space:]]*"[^"]*"' /etc/board.json | head -1 | cut -d'"' -f4)
        [ -n "$board" ] && printf "Board: %b%s%b\n" "${GREEN}" "$board" "${RESET}"
    fi
    printf "\n"
    
    # CPU Information
    printf "%b\n" "${CYAN}CPU:${RESET}"
    cpu_vendor_model=$(get_cpu_vendor_model)
    printf "Vendor/Model: %b%s%b\n" "${GREEN}" "$cpu_vendor_model" "${RESET}"
    
    # Try to install and use lscpu for detailed info
    if ensure_lscpu; then
        cpu_cores=$(lscpu 2>/dev/null | grep "^CPU(s):" | awk '{print $2}')
        cpu_freq=$(lscpu 2>/dev/null | grep "CPU max MHz" | awk '{print $4}')
        [ -z "$cpu_freq" ] && cpu_freq=$(lscpu 2>/dev/null | grep "CPU MHz" | awk '{print $3}')
        
        [ -n "$cpu_cores" ] && printf "Cores: %b%s%b\n" "${GREEN}" "$cpu_cores" "${RESET}"
        [ -n "$cpu_freq" ] && printf "Frequency: %b%.0f MHz%b\n" "${GREEN}" "$cpu_freq" "${RESET}"
    else
        # Fallback to /proc/cpuinfo
        cpu_cores=$(grep -c "^processor" /proc/cpuinfo 2>/dev/null)
        [ -n "$cpu_cores" ] && printf "Cores: %b%s%b\n" "${GREEN}" "$cpu_cores" "${RESET}"
    fi
    printf "\n"
    
    # Memory
    printf "%b\n" "${CYAN}Memory:${RESET}"
    if [ -f /proc/meminfo ]; then
        awk '/MemTotal/ {
            m = $2 / 1024
            est = m + 30
            rounded = (int((est + 127) / 128) * 128)
            printf "Est. Soldered RAM: '"${GREEN}"'%d MB'"${RESET}"'\n", rounded
            printf "Available RAM: '"${GREEN}"'%.0f MB'"${RESET}"'\n", m
        }' /proc/meminfo
    fi
    printf "\n"
    
    # Flash Storage
    printf "%b\n" "${CYAN}Storage:${RESET}"
    if [ -f /proc/mtd ]; then
        hex=$(awk 'NR==2 {print $2}' /proc/mtd)
        if [ -n "$hex" ]; then
            flash_total=$(printf "%d" "0x$hex" 2>/dev/null)
            flash_mib=$((flash_total / 1024 / 1024))
            printf "Total Physical Flash: %b%d MiB%b\n" "${GREEN}" "$flash_mib" "${RESET}"
        fi
    fi
    
    printf "\n%b\n" "${CYAN}Filesystem Usage:${RESET}"
    df -h | grep -E "^/dev/" | grep -v "tmpfs"
    printf "\n"
    
    # Ethernet Configuration
    printf "%b\n" "${CYAN}Ethernet Interfaces:${RESET}"
    ip -br link show 2>/dev/null | grep -E "eth|lan|wan|br-" | while read iface state rest; do
        speed=""
        if [ -f "/sys/class/net/$iface/speed" ]; then
            speed=$(cat /sys/class/net/$iface/speed 2>/dev/null)
            if [ "$speed" != "-1" ] && [ -n "$speed" ]; then
                speed=" (${speed}Mbps)"
            else
                speed=""
            fi
        fi
        printf "  %s: %s%s\n" "$iface" "$state" "$speed"
    done
    
    # Check for switch info
    if command -v swconfig >/dev/null 2>&1; then
        printf "\n%b\n" "${CYAN}Switch Configuration:${RESET}"
        swconfig list 2>/dev/null || printf "  No switch detected\n"
    fi
    printf "\n"
    
    # Wireless Information
    printf "%b\n" "${CYAN}Wireless Interfaces:${RESET}"
    if command -v iwinfo >/dev/null 2>&1; then
        for radio in $(ls /sys/class/ieee80211/ 2>/dev/null); do
            iface=$(iw dev 2>/dev/null | grep -A 1 "phy#${radio#phy}" | grep Interface | awk '{print $2}' | head -1)
            [ -z "$iface" ] && iface=$(ls /sys/class/ieee80211/$radio/device/net/ 2>/dev/null | head -1)
            
            if [ -n "$iface" ]; then
                info=$(iwinfo "$iface" info 2>/dev/null)
                if [ -n "$info" ]; then
                    hwmode=$(echo "$info" | grep "Hardware:" | cut -d: -f2- | sed 's/^[[:space:]]*//')
                    channel=$(echo "$info" | grep "Channel:" | cut -d: -f2 | awk '{print $1}')
                    
                    # Determine band from multiple sources
                    band=""
                    
                    # Method 1: Try UCI band config first
                    uci_band=$(uci get wireless.${radio}.band 2>/dev/null)
                    case "$uci_band" in
                        2g) band="2.4GHz" ;;
                        5g) band="5GHz" ;;
                        6g) band="6GHz" ;;
                    esac
                    
                    # Method 2: If no UCI band, check iw phy frequencies
                    if [ -z "$band" ]; then
                        phy_freqs=$(iw phy "$radio" info 2>/dev/null | grep -o "[0-9][0-9][0-9][0-9] MHz" | awk '{print $1}' | sort -u)
                        
                        has_2ghz=0
                        has_5ghz=0
                        has_6ghz=0
                        
                        for freq in $phy_freqs; do
                            if [ "$freq" -ge 2400 ] && [ "$freq" -le 2500 ]; then
                                has_2ghz=1
                            elif [ "$freq" -ge 5000 ] && [ "$freq" -le 6000 ]; then
                                has_5ghz=1
                            elif [ "$freq" -ge 6000 ]; then
                                has_6ghz=1
                            fi
                        done
                        
                        # Assign band based on what we found
                        if [ "$has_6ghz" -eq 1 ] && [ "$has_5ghz" -eq 1 ]; then
                            band="5GHz/6GHz"
                        elif [ "$has_6ghz" -eq 1 ]; then
                            band="6GHz"
                        elif [ "$has_5ghz" -eq 1 ]; then
                            band="5GHz"
                        elif [ "$has_2ghz" -eq 1 ]; then
                            band="2.4GHz"
                        fi
                    fi
                    
                    # Default if nothing found
                    [ -z "$band" ] && band="Unknown"
                    
                    # Try to get MIMO info from driver
                    mimo=""
                    htmode=$(uci get wireless.${radio}.htmode 2>/dev/null)
                    case "$htmode" in
                        *HE80*|*HE160*|*VHT80*|*VHT160*|*EHT160*|*EHT320*) mimo="4x4" ;;
                        *HE40*|*HE20*|*VHT40*|*VHT20*|*EHT80*) mimo="2x2" ;;
                        *) 
                            # Try to determine from phy capabilities
                            streams=$(iw phy "$radio" info 2>/dev/null | grep -m1 "RX streams:" | awk '{print $3}')
                            [ -z "$streams" ] && streams=$(iw phy "$radio" info 2>/dev/null | grep -m1 "TX streams:" | awk '{print $3}')
                            case "$streams" in
                                4) mimo="4x4" ;;
                                2) mimo="2x2" ;;
                                1) mimo="1x1" ;;
                                *) mimo="2x2" ;; # Default
                            esac
                            ;;
                    esac
                    
                    printf "  %s (%s):\n" "$iface" "$radio"
                    [ -n "$hwmode" ] && printf "    Hardware: %s\n" "$hwmode"
                    printf "    Band: %b%s%b\n" "${GREEN}" "$band" "${RESET}"
                    [ -n "$mimo" ] && printf "    MIMO: %b%s%b\n" "${GREEN}" "$mimo" "${RESET}"
                    [ -n "$channel" ] && printf "    Channel: %s\n" "$channel"
                fi
            fi
        done
    else
        iw dev 2>/dev/null | grep Interface | awk '{print "  "$2}' || printf "  No wireless interfaces detected\n"
    fi
    printf "\n"
    
    press_any_key
}

# -----------------------------
# 2) Enable UI Updates on AdGuardHome
# -----------------------------
enable_agh_ui_updates() {
    print_header "Enable AdGuardHome UI Updates"
    
    if [ ! -f "$AGH_INIT" ]; then
        print_error "AdGuardHome init script not found at $AGH_INIT"
        press_any_key
        return 1
    fi
    
    if grep -q "procd_set_param command.*--no-check-update" "$AGH_INIT"; then
        sed -i '/procd_set_param command/s/--no-check-update //g' "$AGH_INIT"
        print_success "UI updates enabled in AdGuardHome"
        
        printf "\n%b\n" "${YELLOW}⏳ Restarting AdGuardHome...${RESET}"
        /etc/init.d/adguardhome restart
        print_success "AdGuardHome restarted"
    else
        print_warning "UI updates already enabled or flag not found"
    fi
    
    press_any_key
}

# -----------------------------
# 3) Zswap Management
# -----------------------------
manage_zswap() {
    print_header "Zswap Management"
    
    printf "1️⃣  Check zswap status\n"
    printf "2️⃣  Enable zswap\n"
    printf "3️⃣  Disable zswap\n"
    printf "4️⃣  Back to main menu\n"
    printf "\nChoose [1-4]: "
    read -r zswap_choice
    printf "\n"
    
    case $zswap_choice in
        1)
            if [ -f /sys/module/zswap/parameters/enabled ]; then
                status=$(cat /sys/module/zswap/parameters/enabled)
                if [ "$status" = "Y" ] || [ "$status" = "1" ]; then
                    print_success "Zswap is ENABLED"
                    if [ -f /sys/module/zswap/parameters/compressor ]; then
                        printf "Compressor: %s\n" "$(cat /sys/module/zswap/parameters/compressor)"
                    fi
                    if [ -f /sys/module/zswap/parameters/max_pool_percent ]; then
                        printf "Max pool: %s%%\n" "$(cat /sys/module/zswap/parameters/max_pool_percent)"
                    fi
                else
                    print_warning "Zswap is DISABLED"
                fi
            else
                print_error "Zswap module not available on this system"
            fi
            ;;
        2)
            if [ -f /sys/module/zswap/parameters/enabled ]; then
                echo 1 > /sys/module/zswap/parameters/enabled
                print_success "Zswap enabled"
                
                # Make persistent
                if ! grep -q "zswap.enabled=1" /etc/sysctl.conf 2>/dev/null; then
                    printf "# Enable zswap\n" >> /etc/sysctl.conf
                    printf "vm.zswap.enabled=1\n" >> /etc/sysctl.conf
                    print_success "Added to sysctl.conf for persistence"
                fi
            else
                print_error "Zswap module not available"
            fi
            ;;
        3)
            if [ -f /sys/module/zswap/parameters/enabled ]; then
                echo 0 > /sys/module/zswap/parameters/enabled
                print_success "Zswap disabled"
                
                # Remove from sysctl.conf
                if grep -q "vm.zswap.enabled=1" /etc/sysctl.conf 2>/dev/null; then
                    sed -i '/vm.zswap.enabled=1/d' /etc/sysctl.conf
                    print_success "Removed from sysctl.conf"
                fi
            else
                print_error "Zswap module not available"
            fi
            ;;
        4)
            return
            ;;
        *)
            print_error "Invalid option"
            ;;
    esac
    
    press_any_key
}

# -----------------------------
# 4) Install Blocklists and Allowlists to AdGuardHome
# -----------------------------
install_agh_lists() {
    print_header "Install AdGuardHome Lists"
    
    if [ ! -f "$AGH_CONFIG" ]; then
        print_error "AdGuardHome config not found at $AGH_CONFIG"
        press_any_key
        return 1
    fi
    
    # Backup config
    cp "$AGH_CONFIG" "${AGH_CONFIG}.backup.$(date +%Y%m%d_%H%M%S)"
    print_success "Config backed up"
    
    # URLs for lists
    PHANTASM_BLOCKLIST="https://raw.githubusercontent.com/phantasm22/AdGuardHome-Lists/refs/heads/main/blocklist.txt"
    HAGEZI_BLOCKLIST="https://cdn.jsdelivr.net/gh/hagezi/dns-blocklists@latest/adblock/pro.plus.txt"
    PHANTASM_ALLOWLIST="https://raw.githubusercontent.com/phantasm22/AdGuardHome-Lists/refs/heads/main/allowlist.txt"
    
    printf "%b\n\n" "${YELLOW}⏳ Installing blocklists and allowlist...${RESET}"
    
    # Check if filters section exists
    if ! grep -q "^filters:" "$AGH_CONFIG"; then
        print_error "No 'filters:' section found in config"
        press_any_key
        return 1
    fi
    
    # Create temporary file with the new lists
    temp_file=$(mktemp)
    
    cat > "$temp_file" << EOF
# Blocklists
  - enabled: true
    url: $PHANTASM_BLOCKLIST
    name: Phantasm22's Blocklist
    id: $(date +%s)1
  - enabled: true
    url: $HAGEZI_BLOCKLIST
    name: HaGeZi's Pro++ Blocklist
    id: $(date +%s)2
EOF
    
    # Insert blocklists after "filters:" line
    sed -i '/^filters:/r '"$temp_file" "$AGH_CONFIG"
    
    # Now handle allowlist (whitelist_filters)
    cat > "$temp_file" << EOF
# Allowlist
  - enabled: true
    url: $PHANTASM_ALLOWLIST
    name: Phantasm22's Allow List
    id: $(date +%s)3
EOF
    
    if grep -q "^whitelist_filters:" "$AGH_CONFIG"; then
        sed -i '/^whitelist_filters:/r '"$temp_file" "$AGH_CONFIG"
    else
        # Add whitelist_filters section if it doesn't exist
        printf "\n" >> "$AGH_CONFIG"
        printf "whitelist_filters:\n" >> "$AGH_CONFIG"
        cat "$temp_file" >> "$AGH_CONFIG"
    fi
    
    rm "$temp_file"
    
    print_success "Phantasm22's Blocklist added"
    print_success "HaGeZi's Pro++ Blocklist added"
    print_success "Phantasm22's Allow List added"
    
    printf "\n%b\n" "${YELLOW}⏳ Restarting AdGuardHome to apply changes...${RESET}"
    /etc/init.d/adguardhome restart
    sleep 2
    print_success "AdGuardHome restarted"
    
    printf "\n%b\n" "${GREEN}✅ Lists installed! Check AdGuardHome UI to update filters.${RESET}"
    
    press_any_key
}

# -----------------------------
# 5) CPU & Disk Benchmarks
# -----------------------------
benchmark_system() {
    print_header "System Benchmarks"
    
    printf "1️⃣  CPU Stress Test (requires 'stress' package)\n"
    printf "2️⃣  CPU Benchmark (OpenSSL)\n"
    printf "3️⃣  Disk I/O Benchmark\n"
    printf "4️⃣  Back to main menu\n"
    printf "\nChoose [1-4]: "
    read -r bench_choice
    printf "\n"
    
    case $bench_choice in
        1)
            if ! command -v stress >/dev/null 2>&1; then
                print_warning "stress not found, installing..."
                if [ "$opkg_updated" -eq 0 ]; then
                    opkg update >/dev/null 2>&1
                    opkg_updated=1
                fi
                opkg install stress >/dev/null 2>&1
                if ! command -v stress >/dev/null 2>&1; then
                    print_error "Failed to install stress"
                    press_any_key
                    return 1
                fi
            fi
            
            cpu_cores=$(grep -c "^processor" /proc/cpuinfo 2>/dev/null)
            [ -z "$cpu_cores" ] && cpu_cores=1
            
            printf "\n%b\n" "${YELLOW}⏳ Running stress test on $cpu_cores cores for 60 seconds...${RESET}"
            printf "%b\n\n" "${YELLOW}💡 Monitor with 'top' in another session${RESET}"
            
            stress --cpu "$cpu_cores" --timeout 60s --verbose
            
            printf "\n"
            print_success "Stress test completed"
            ;;
        2)
            if ! command -v openssl >/dev/null 2>&1; then
                print_error "OpenSSL not found"
                press_any_key
                return 1
            fi
            
            printf "\n%b\n" "${CYAN}🔧 Running OpenSSL speed benchmark...${RESET}"
            printf "%b\n\n" "${YELLOW}⏳ This will take a minute...${RESET}"
            
            # Single-threaded benchmark
            printf "%b\n" "${CYAN}Single-threaded AES-256-GCM:${RESET}"
            openssl speed -elapsed -evp aes-256-gcm 2>&1 | tail -3
            
            printf "\n%b\n" "${CYAN}Single-threaded SHA256:${RESET}"
            openssl speed -elapsed sha256 2>&1 | tail -3
            
            printf "\n%b\n" "${CYAN}RSA 2048-bit signing:${RESET}"
            openssl speed -elapsed rsa2048 2>&1 | tail -5
            
            printf "\n"
            print_success "Benchmark completed"
            ;;
        3)
            printf "%b\n" "${CYAN}🔧 Disk I/O Benchmark${RESET}\n"
            
            # Check available space
            available_kb=$(df -k . | awk 'NR==2 {print $4}')
            required_kb=$((1000 * 1024))  # 1000MB = ~1GB
            
            if [ "$available_kb" -lt "$required_kb" ]; then
                print_error "Not enough disk space. Need ~1GB free for benchmark."
                printf "Available: %d MB\n" $((available_kb / 1024))
                press_any_key
                return 1
            fi
            
            print_success "Sufficient disk space available"
            
            # Write test
            printf "\n%b\n" "${YELLOW}⏳ Running write test (1GB)...${RESET}"
            sync
            write_start=$(date +%s)
            dd if=/dev/zero of=./testfile bs=1M count=1000 conv=fsync 2>&1 | tail -3
            write_end=$(date +%s)
            write_time=$((write_end - write_start))
            
            if [ -f ./testfile ]; then
                write_speed=$((1000 / write_time))
                printf "%b\n" "${GREEN}✅ Write speed: ~${write_speed} MB/s${RESET}"
            fi
            
            # Read test
            printf "\n%b\n" "${YELLOW}⏳ Running read test (1GB)...${RESET}"
            sync
            echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true
            read_start=$(date +%s)
            dd if=./testfile of=/dev/null bs=1M 2>&1 | tail -3
            read_end=$(date +%s)
            read_time=$((read_end - read_start))
            
            read_speed=$((1000 / read_time))
            printf "%b\n" "${GREEN}✅ Read speed: ~${read_speed} MB/s${RESET}"
            
            # Cleanup
            rm -f ./testfile
            printf "\n"
            print_success "Disk benchmark completed"
            ;;
        4)
            return
            ;;
        *)
            print_error "Invalid option"
            ;;
    esac
    
    press_any_key
}

# -----------------------------
# 6) UCI Configuration Viewer
# -----------------------------
view_uci_config() {
    print_header "System Configuration Viewer"
    
    printf "1️⃣  Wireless Networks (SSIDs & Passwords)\n"
    printf "2️⃣  Network Configuration\n"
    printf "3️⃣  VPN Configuration\n"
    printf "4️⃣  System Settings\n"
    printf "5️⃣  Back to main menu\n"
    printf "\nChoose [1-5]: "
    read -r config_choice
    printf "\n"
    
    case $config_choice in
        1)
            print_header "Wireless Networks"
            
            # List all wireless interfaces with SSIDs and passwords
            for iface in $(uci show wireless | grep "wifi-iface" | cut -d'.' -f2 | cut -d'=' -f1 | sort -u); do
                ssid=$(uci get wireless.${iface}.ssid 2>/dev/null)
                key=$(uci get wireless.${iface}.key 2>/dev/null)
                encryption=$(uci get wireless.${iface}.encryption 2>/dev/null)
                disabled=$(uci get wireless.${iface}.disabled 2>/dev/null)
                device=$(uci get wireless.${iface}.device 2>/dev/null)
                
                # Get band from device
                band=$(uci get wireless.${device}.band 2>/dev/null)
                case "$band" in
                    2g) band_name="2.4GHz" ;;
                    5g) band_name="5GHz" ;;
                    6g) band_name="6GHz" ;;
                    *) band_name="Unknown" ;;
                esac
                
                if [ -n "$ssid" ]; then
                    printf "%b\n" "${CYAN}Interface: $iface ($band_name)${RESET}"
                    printf "  SSID: %b%s%b\n" "${GREEN}" "$ssid" "${RESET}"
                    [ -n "$key" ] && printf "  Password: %b%s%b\n" "${YELLOW}" "$key" "${RESET}"
                    [ -n "$encryption" ] && printf "  Encryption: %s\n" "$encryption"
                    if [ "$disabled" = "1" ]; then
                        printf "  Status: %b%s%b\n" "${RED}" "Disabled" "${RESET}"
                    else
                        printf "  Status: %b%s%b\n" "${GREEN}" "Enabled" "${RESET}"
                    fi
                    printf "\n"
                fi
            done
            ;;
        2)
            print_header "Network Configuration"
            
            printf "%b\n" "${CYAN}WAN Configuration:${RESET}"
            wan_proto=$(uci get network.wan.proto 2>/dev/null)
            wan_ipaddr=$(uci get network.wan.ipaddr 2>/dev/null)
            wan_netmask=$(uci get network.wan.netmask 2>/dev/null)
            wan_gateway=$(uci get network.wan.gateway 2>/dev/null)
            wan_dns=$(uci get network.wan.dns 2>/dev/null)
            
            [ -n "$wan_proto" ] && printf "  Protocol: %s\n" "$wan_proto"
            [ -n "$wan_ipaddr" ] && printf "  IP Address: %b%s%b\n" "${GREEN}" "$wan_ipaddr" "${RESET}"
            [ -n "$wan_netmask" ] && printf "  Netmask: %s\n" "$wan_netmask"
            [ -n "$wan_gateway" ] && printf "  Gateway: %s\n" "$wan_gateway"
            [ -n "$wan_dns" ] && printf "  DNS: %s\n" "$wan_dns"
            
            printf "\n%b\n" "${CYAN}LAN Configuration:${RESET}"
            lan_ipaddr=$(uci get network.lan.ipaddr 2>/dev/null)
            lan_netmask=$(uci get network.lan.netmask 2>/dev/null)
            lan_proto=$(uci get network.lan.proto 2>/dev/null)
            
            [ -n "$lan_proto" ] && printf "  Protocol: %s\n" "$lan_proto"
            [ -n "$lan_ipaddr" ] && printf "  IP Address: %b%s%b\n" "${GREEN}" "$lan_ipaddr" "${RESET}"
            [ -n "$lan_netmask" ] && printf "  Netmask: %s\n" "$lan_netmask"
            
            printf "\n%b\n" "${CYAN}DHCP Server:${RESET}"
            dhcp_start=$(uci get dhcp.lan.start 2>/dev/null)
            dhcp_limit=$(uci get dhcp.lan.limit 2>/dev/null)
            dhcp_leasetime=$(uci get dhcp.lan.leasetime 2>/dev/null)
            
            [ -n "$dhcp_start" ] && printf "  Start: %s\n" "$dhcp_start"
            [ -n "$dhcp_limit" ] && printf "  Limit: %s\n" "$dhcp_limit"
            [ -n "$dhcp_leasetime" ] && printf "  Lease Time: %s\n" "$dhcp_leasetime"
            printf "\n"
            ;;
        3)
            print_header "VPN Configuration"
            
            # Check for WireGuard
            if uci show network 2>/dev/null | grep -q "wireguard"; then
                printf "%b\n" "${CYAN}WireGuard Interfaces:${RESET}"
                for iface in $(uci show network | grep "proto='wireguard'" | cut -d'.' -f2 | cut -d'=' -f1); do
                    private_key=$(uci get network.${iface}.private_key 2>/dev/null)
                    listen_port=$(uci get network.${iface}.listen_port 2>/dev/null)
                    addresses=$(uci get network.${iface}.addresses 2>/dev/null)
                    
                    printf "  Interface: %b%s%b\n" "${GREEN}" "$iface" "${RESET}"
                    [ -n "$listen_port" ] && printf "    Listen Port: %s\n" "$listen_port"
                    [ -n "$addresses" ] && printf "    Addresses: %s\n" "$addresses"
                    [ -n "$private_key" ] && printf "    Private Key: %b[configured]%b\n" "${YELLOW}" "${RESET}"
                    printf "\n"
                done
            fi
            
            # Check for OpenVPN
            if [ -f /etc/config/openvpn ] && uci show openvpn 2>/dev/null | grep -q "enabled='1'"; then
                printf "%b\n" "${CYAN}OpenVPN Instances:${RESET}"
                for instance in $(uci show openvpn | grep "enabled='1'" | cut -d'.' -f2 | cut -d'=' -f1); do
                    config=$(uci get openvpn.${instance}.config 2>/dev/null)
                    proto=$(uci get openvpn.${instance}.proto 2>/dev/null)
                    port=$(uci get openvpn.${instance}.port 2>/dev/null)
                    
                    printf "  Instance: %b%s%b\n" "${GREEN}" "$instance" "${RESET}"
                    [ -n "$config" ] && printf "    Config: %s\n" "$config"
                    [ -n "$proto" ] && printf "    Protocol: %s\n" "$proto"
                    [ -n "$port" ] && printf "    Port: %s\n" "$port"
                    printf "\n"
                done
            fi
            
            # Check for other VPN configs
            if ! uci show network 2>/dev/null | grep -q "wireguard" && \
               ! ([ -f /etc/config/openvpn ] && uci show openvpn 2>/dev/null | grep -q "enabled='1'"); then
                print_warning "No active VPN configurations found"
            fi
            printf "\n"
            ;;
        4)
            print_header "System Settings"
            
            printf "%b\n" "${CYAN}System Information:${RESET}"
            hostname=$(uci get system.@system[0].hostname 2>/dev/null)
            timezone=$(uci get system.@system[0].timezone 2>/dev/null)
            zonename=$(uci get system.@system[0].zonename 2>/dev/null)
            
            [ -n "$hostname" ] && printf "  Hostname: %b%s%b\n" "${GREEN}" "$hostname" "${RESET}"
            [ -n "$zonename" ] && printf "  Timezone: %s\n" "$zonename"
            [ -n "$timezone" ] && printf "  TZ String: %s\n" "$timezone"
            
            printf "\n%b\n" "${CYAN}Root Access:${RESET}"
            if grep -q "^root:[^\*!]" /etc/shadow 2>/dev/null; then
                printf "  Root Password: %b%s%b\n" "${GREEN}" "Set" "${RESET}"
            else
                printf "  Root Password: %b%s%b\n" "${RED}" "Not Set" "${RESET}"
            fi
            
            # Check SSH config
            ssh_port=$(uci get dropbear.@dropbear[0].Port 2>/dev/null)
            ssh_interface=$(uci get dropbear.@dropbear[0].Interface 2>/dev/null)
            ssh_pass=$(uci get dropbear.@dropbear[0].PasswordAuth 2>/dev/null)
            ssh_root=$(uci get dropbear.@dropbear[0].RootPasswordAuth 2>/dev/null)
            
            printf "\n%b\n" "${CYAN}SSH Configuration:${RESET}"
            [ -n "$ssh_port" ] && printf "  Port: %s\n" "$ssh_port" || printf "  Port: 22 (default)\n"
            [ -n "$ssh_interface" ] && printf "  Interface: %s\n" "$ssh_interface"
            
            if [ "$ssh_pass" = "0" ]; then
                printf "  Password Auth: %b%s%b\n" "${RED}" "Disabled" "${RESET}"
            else
                printf "  Password Auth: %b%s%b\n" "${GREEN}" "Enabled" "${RESET}"
            fi
            
            if [ "$ssh_root" = "0" ]; then
                printf "  Root Login: %b%s%b\n" "${RED}" "Disabled" "${RESET}"
            else
                printf "  Root Login: %b%s%b\n" "${GREEN}" "Enabled" "${RESET}"
            fi
            printf "\n"
            ;;
        5)
            return
            ;;
        *)
            print_error "Invalid option"
            ;;
    esac
    
    press_any_key
}

# -----------------------------
# Main Menu
# -----------------------------
show_menu() {
    clear
    printf "%b\n" "$SPLASH"
    printf "%b\n" "${CYAN}Please select an option:${RESET}\n"
    printf "1️⃣  Show Hardware Information\n"
    printf "2️⃣  Enable AdGuardHome UI Updates\n"
    printf "3️⃣  Manage Zswap\n"
    printf "4️⃣  Install AdGuardHome Blocklists & Allowlist\n"
    printf "5️⃣  System Benchmarks (CPU & Disk)\n"
    printf "6️⃣  View System Configuration (UCI)\n"
    printf "7️⃣  Exit\n"
    printf "\nChoose [1-7]: "
    read opt
    printf "\n"
    case $opt in
        1) show_hardware_info ;;
        2) enable_agh_ui_updates ;;
        3) manage_zswap ;;
        4) install_agh_lists ;;
        5) benchmark_system ;;
        6) view_uci_config ;;
        7) printf "\n%b\n\n" "${GREEN}✅ Thanks for using GL.iNet Toolkit!${RESET}"; exit 0 ;;
        *) print_error "Invalid option"; sleep 1; show_menu ;;
    esac
    show_menu
}

# -----------------------------
# Start
# -----------------------------
show_menu
