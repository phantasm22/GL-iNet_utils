#!/bin/sh
# GL.iNet Router Toolkit
# Author: phantasm22
# License: GPL-3.0
# Version: 2026-02-08
#
# This script provides system utilities for GL.iNet routers including:
# - Hardware information display with pagination
# - AdGuardHome management (UI updates, storage limits, lists)
# - Zram swap configuration
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
GREY="\033[90m"
BOLD="\033[1m"

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
AGH_INIT="/etc/init.d/adguardhome"
BLA_BOX="┤ ┴ ├ ┬"
opkg_updated=0
SCRIPT_URL="https://raw.githubusercontent.com/phantasm22/GL-iNet_utils/refs/heads/main/glinet_utils.sh"
TMP_NEW_SCRIPT="/tmp/glinet_utils_new.sh"
SCRIPT_PATH="$0"
[ "${SCRIPT_PATH#*/}" != "$SCRIPT_PATH" ] || SCRIPT_PATH="$(pwd)/$SCRIPT_PATH"

# -----------------------------
# Cleanup any previous updates
# -----------------------------
case "$0" in
    *.new)
        ORIGINAL="${0%.new}"
        printf "🧹 Applying update...\n"
        mv -f "$0" "$ORIGINAL" && chmod +x "$ORIGINAL"
        printf "✅ Update applied. Restarting main script...\n"
        sleep 3
        exec "$ORIGINAL" "$@"
        ;;
esac

# -----------------------------
# Utility Functions
# -----------------------------
press_any_key() {
    printf "\nPress any key to continue... "
    read -rsn1
    printf "\n"
}

read_single_char() {
    read -rsn1 char
    printf "%s" "$char"
}

print_centered_header() {
    title="$1"
    width=48
    title_display_len=${#title}
    case "$title" in
        *[🖥️📡🌐🔒⚙️💾📊🛡️📋☁️]*) title_display_len=$((title_display_len - 2)) ;;
    esac
    
    padding=$(((width - title_display_len) / 2))
    padding_right=$((width - padding - title_display_len))
    
    printf "\n%b\n" "${CYAN}┌────────────────────────────────────────────────┐${RESET}"
    printf "%b" "${CYAN}│"
    printf "%*s" $padding ""
    printf "%s" "$title"
    printf "%*s" $padding_right ""
    printf "%b\n" "│${RESET}"
    printf "%b\n\n" "${CYAN}└────────────────────────────────────────────────┘${RESET}"
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
# Self-update function
# -----------------------------
check_self_update() {
    printf "\n🔍 Checking for script updates...\n"

    LOCAL_VERSION="$(grep -m1 '^# Version:' "$SCRIPT_PATH" | awk '{print $3}' | tr -d '\r')"
    [ -z "$LOCAL_VERSION" ] && LOCAL_VERSION="0000-00-00"

    if ! wget -q -O "$TMP_NEW_SCRIPT" "$SCRIPT_URL"; then
        printf "⚠️  Unable to check for updates (network or GitHub issue).\n"
        return 1
    fi

    REMOTE_VERSION="$(grep -m1 '^# Version:' "$TMP_NEW_SCRIPT" | awk '{print $3}' | tr -d '\r')"
    [ -z "$REMOTE_VERSION" ] && REMOTE_VERSION="0000-00-00"

    printf "📦 Current version: %s\n" "$LOCAL_VERSION"
    printf "🌐 Latest version:  %s\n" "$REMOTE_VERSION"

    if [ "$REMOTE_VERSION" \> "$LOCAL_VERSION" ]; then
        printf "\nA new version is available. Update now? [y/N]: "
        read -r ans
        case "$ans" in
            y|Y)
                printf "⬆️  Updating...\n"
                cp "$TMP_NEW_SCRIPT" "$SCRIPT_PATH.new" && chmod +x "$SCRIPT_PATH.new"
                printf "✅ Upgrade complete. Restarting script...\n"
                exec "$SCRIPT_PATH.new" "$@"
                ;;
            *)
                printf "⏭️  Skipping update. Continuing with current version.\n"
                ;;
        esac
    else
        printf "✅ You are already running the latest version.\n"
    fi

    rm -f "$TMP_NEW_SCRIPT" >/dev/null 2>&1
    printf "\n"
}

# -----------------------------
# System Detection Functions
# -----------------------------
ensure_lscpu() {
    if ! command -v lscpu >/dev/null 2>&1; then
        if [ "$opkg_updated" -eq 0 ]; then
            opkg update >/dev/null 2>&1
            opkg_updated=1
        fi
        opkg install lscpu >/dev/null 2>&1
    fi
}

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

get_agh_config() {
    if [ ! -f "$AGH_INIT" ]; then
        return 1
    fi
    
    config_path=$(grep -o '\-c [^ ]*' "$AGH_INIT" | awk '{print $2}')
    if [ -n "$config_path" ] && [ -f "$config_path" ]; then
        printf "%s" "$config_path"
        return 0
    fi
    
    return 1
}

get_agh_workdir() {
    if [ ! -f "$AGH_INIT" ]; then
        return 1
    fi
    
    workdir=$(grep -o '\-w [^ ]*' "$AGH_INIT" | awk '{print $2}')
    if [ -n "$workdir" ] && [ -d "$workdir" ]; then
        printf "%s" "$workdir"
        return 0
    fi
    
    return 1
}

is_agh_running() {
    pidof AdGuardHome >/dev/null 2>&1
    return $?
}

# -----------------------------
# 1) Hardware Information Display
# -----------------------------
show_hardware_info() {
    page=1
    total_pages=4
    
    while true; do
        clear
        print_centered_header "Hardware Information"
        
        case $page in
            1)
                printf "%b%bPage 1 of $total_pages: System Overview%b\n\n" "${BOLD}" "${CYAN}" "${RESET}"
                
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
                
                printf "%b\n" "${CYAN}CPU:${RESET}"
                cpu_vendor_model=$(get_cpu_vendor_model)
                printf "Vendor/Model: %b%s%b\n" "${GREEN}" "$cpu_vendor_model" "${RESET}"
                
                ensure_lscpu
                if command -v lscpu >/dev/null 2>&1; then
                    cpu_cores=$(lscpu 2>/dev/null | grep "^CPU(s):" | awk '{print $2}')
                    cpu_freq=$(lscpu 2>/dev/null | grep "CPU max MHz" | awk '{print $4}')
                    [ -z "$cpu_freq" ] && cpu_freq=$(lscpu 2>/dev/null | grep "CPU MHz" | awk '{print $3}')
                    
                    [ -n "$cpu_cores" ] && printf "Cores: %b%s%b\n" "${GREEN}" "$cpu_cores" "${RESET}"
                    [ -n "$cpu_freq" ] && printf "Frequency: %b%.0f MHz%b\n" "${GREEN}" "$cpu_freq" "${RESET}"
                else
                    cpu_cores=$(grep -c "^processor" /proc/cpuinfo 2>/dev/null)
                    [ -n "$cpu_cores" ] && printf "Cores: %b%s%b\n" "${GREEN}" "$cpu_cores" "${RESET}"
                fi
                
                fan_speed=$(cat /sys/class/hwmon/hwmon*/fan*_input 2>/dev/null | head -1)
                if [ -n "$fan_speed" ]; then
                    printf "Fan Speed: %b%s RPM%b\n" "${GREEN}" "$fan_speed" "${RESET}"
                fi
                printf "\n"
                
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
                df -h | head -1
                df -h | grep -E "^/dev/" | grep -v "tmpfs" | head -3
                ;;
                
            2)
                printf "%b%bPage 2 of $total_pages: Hardware Crypto Acceleration%b\n\n" "${BOLD}" "${CYAN}" "${RESET}"
                
                cpu_features=$(cat /proc/cpuinfo | grep Features | head -1 | grep -o "aes\|sha1\|sha2\|pmull\|neon" | tr '\n' ' ')
                [ -n "$cpu_features" ] && printf "CPU Features: %b%s%b\n\n" "${GREEN}" "$cpu_features" "${RESET}"
                
                aes_accel="NO"
                chacha_accel="NO"
                poly_accel="NO"
                sha_accel="NO"
                
                if [ -f /proc/crypto ]; then
                    grep -q 'aes-ce\|cbc-aes-ce\|gcm-aes-ce' /proc/crypto && aes_accel="YES"
                    grep -q 'chacha20-neon' /proc/crypto && chacha_accel="YES"
                    grep -q 'poly1305-neon' /proc/crypto && poly_accel="YES"
                    grep -q 'sha256-ce\|sha1-ce' /proc/crypto && sha_accel="YES"
                fi
                
                printf "%b\n" "${CYAN}Hardware-Accelerated Algorithms:${RESET}"
                printf "  AES (CBC/GCM/CTR): %b%s%b\n" "$([ "$aes_accel" = "YES" ] && echo "$GREEN" || echo "$RED")" "$aes_accel" "${RESET}"
                printf "  ChaCha20 (WireGuard): %b%s%b\n" "$([ "$chacha_accel" = "YES" ] && echo "$GREEN" || echo "$RED")" "$chacha_accel" "${RESET}"
                printf "  Poly1305 (WireGuard): %b%s%b\n" "$([ "$poly_accel" = "YES" ] && echo "$GREEN" || echo "$RED")" "$poly_accel" "${RESET}"
                printf "  SHA256/SHA1: %b%s%b\n" "$([ "$sha_accel" = "YES" ] && echo "$GREEN" || echo "$RED")" "$sha_accel" "${RESET}"
                
                printf "\n%b\n" "${CYAN}VPN Performance Assessment:${RESET}"
                if [ "$aes_accel" = "YES" ] && [ "$chacha_accel" = "YES" ] && [ "$poly_accel" = "YES" ]; then
                    printf "%b%s%b\n" "${GREEN}" "✅ Both OpenVPN (AES) and WireGuard (ChaCha20+Poly1305)" "${RESET}"
                    printf "%b%s%b\n" "${GREEN}" "   have hardware acceleration" "${RESET}"
                elif [ "$chacha_accel" = "YES" ] && [ "$poly_accel" = "YES" ]; then
                    printf "%b%s%b\n" "${YELLOW}" "⚠️  WireGuard has HW acceleration, OpenVPN AES does not" "${RESET}"
                else
                    printf "%b%s%b\n" "${YELLOW}" "⚠️  Partial acceleration detected" "${RESET}"
                fi
                ;;
                
            3)
                printf "%b%bPage 3 of $total_pages: Network Interfaces%b\n\n" "${BOLD}" "${CYAN}" "${RESET}"
                
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
                
                if command -v swconfig >/dev/null 2>&1; then
                    printf "\n%b\n" "${CYAN}Switch Configuration:${RESET}"
                    switch_info=$(swconfig list 2>/dev/null)
                    if [ -n "$switch_info" ]; then
                        printf "%s\n" "$switch_info"
                    else
                        printf "  No switch detected\n"
                    fi
                fi
                ;;
                
            4)
                printf "%b%bPage 4 of $total_pages: Wireless Interfaces%b\n\n" "${BOLD}" "${CYAN}" "${RESET}"
                
                if ! command -v iwinfo >/dev/null 2>&1 && ! command -v iw >/dev/null 2>&1; then
                    printf "Neither iwinfo nor iw found - limited wireless info available.\n"
                fi
                
                radio_count=0
                
                if [ -d /sys/class/ieee80211/ ]; then
                for radio in $(ls /sys/class/ieee80211/ 2>/dev/null | sort); do
                    radio_count=$((radio_count + 1))
                    
                    iface=$(iw dev 2>/dev/null | grep -A 1 "phy#${radio#phy}" | grep Interface | awk '{print $2}' | head -1)
                    [ -z "$iface" ] && iface=$(ls /sys/class/ieee80211/$radio/device/net/ 2>/dev/null | head -1)
                    
                    if [ -n "$iface" ] && command -v iwinfo >/dev/null 2>&1; then
                        info=$(iwinfo "$iface" info 2>/dev/null)
                        if [ -n "$info" ]; then
                            hwmode=$(echo "$info" | grep "Hardware:" | cut -d: -f2- | sed 's/^[[:space:]]*//')
                            channel=$(echo "$info" | grep "Channel:" | cut -d: -f2 | awk '{print $1}')
                            
                            band=""
                            uci_band=$(uci get wireless.${radio}.band 2>/dev/null)
                            case "$uci_band" in
                                2g) band="2.4GHz" ;;
                                5g) band="5GHz" ;;
                                6g) band="6GHz" ;;
                            esac
                            
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
                            
                            [ -z "$band" ] && band="Unknown"
                            
                            mimo=""
                            htmode=$(uci get wireless.${radio}.htmode 2>/dev/null)
                            case "$htmode" in
                                *HE80*|*HE160*|*VHT80*|*VHT160*|*EHT160*|*EHT320*) mimo="4x4" ;;
                                *HE40*|*HE20*|*VHT40*|*VHT20*|*EHT80*) mimo="2x2" ;;
                                *) 
                                    streams=$(iw phy "$radio" info 2>/dev/null | grep -m1 "RX streams:" | awk '{print $3}')
                                    [ -z "$streams" ] && streams=$(iw phy "$radio" info 2>/dev/null | grep -m1 "TX streams:" | awk '{print $3}')
                                    case "$streams" in
                                        4) mimo="4x4" ;;
                                        2) mimo="2x2" ;;
                                        1) mimo="1x1" ;;
                                        *) mimo="2x2" ;;
                                    esac
                                    ;;
                            esac
                            
                            printf "%bRadio %d: %s%b\n" "${CYAN}" "$radio_count" "$radio" "${RESET}"
                            printf "  Interface: %s\n" "$iface"
                            [ -n "$hwmode" ] && printf "  Hardware/Mode: %s\n" "$hwmode"
                            printf "  Band: %b%s%b\n" "${GREEN}" "$band" "${RESET}"
                            [ -n "$mimo" ] && printf "  MIMO: %b%s%b\n" "${GREEN}" "$mimo" "${RESET}"
                            [ -n "$channel" ] && printf "  Channel: %s\n" "$channel"
                            printf "\n"
                        fi
                    fi
                    
                    if [ $radio_count -ge 2 ]; then
                        command -v usleep >/dev/null 2>&1 && usleep 400000
                    fi
                done
                fi

                if [ $radio_count -eq 0 ]; then
                   for iface in $(ls /sys/class/net/ 2>/dev/null | grep -E '^(ra|rai|rax|wlan)[0-9]*$' | grep -v '1$' | sort); do
                        radio_count=$((radio_count + 1))
                        
                        # Determine band from interface name
                        band="Unknown"
                        case "$iface" in
                           ra[0-9]*) band="2.4GHz" ;;
                           rai[0-9]*|rax[0-9]*) band="5GHz" ;;
                        esac
                       
                        # Find the wifi-iface section that uses this $iface
                        iface_section=""
                        for s in $(uci show wireless | grep '=wifi-iface' | cut -d. -f2 | cut -d= -f1 | grep -v '^guest'); do
                           if uci get wireless.${s}.ifname 2>/dev/null | grep -q "^${iface}$"; then
                              iface_section="$s"
                              break
                           fi
                        done

                        if [ -n "$iface_section" ]; then
                           radio_section=$(uci get wireless.${iface_section}.device 2>/dev/null)
                           if [ -n "$radio_section" ]; then
                              htmode=$(uci get wireless.${radio_section}.htmode 2>/dev/null)
                              channel=$(uci get wireless.${radio_section}.channel 2>/dev/null)
                              if [ -n "$htmode" ]; then
                                 hwmode="$htmode"
                              else
                                 info=$(iwinfo "$iface" info 2>/dev/null)
                                 htmode=$(echo "$info" | grep "HT Mode:" | sed 's/.*HT Mode: //' | awk '{print $1}')
                                 hwmode="${htmode:-Unknown}"
                              fi

                              uci_band=$(uci get wireless.${radio_section}.band 2>/dev/null)
                                 case "$uci_band" in
                                    2g) band="2.4GHz" ;;
                                    5g) band="5GHz" ;;
                                    6g) band="6GHz" ;;
                                 esac
                               
                                 # MIMO from htmode
                                 case "$htmode" in
                                    *HE80*|*HE160*|*VHT80*|*VHT160*|*EHT160*|*EHT320*) mimo="4x4" ;;
                                    *HE40*|*HE20*|*VHT40*|*VHT20*|*EHT80*) mimo="2x2" ;;
                                    *) mimo="2x2" ;;
                                 esac
                           fi
                        fi

                        if [ -z "$channel" ] && command -v iwinfo >/dev/null 2>&1; then
                           info=$(iwinfo "$iface" info 2>/dev/null)
                           [ -n "$info" ] && channel=$(echo "$info" | grep "Channel:" | cut -d: -f2 | awk '{print $1}')
                           [ -n "$info" ] && hwmode=$(echo "$info" | grep "Hardware:" | cut -d: -f2- | sed 's/^[[:space:]]*//')
                           if echo "$info" | grep -q "2.4 GHz"; then band="2.4GHz"; fi
                           if echo "$info" | grep -q "5 GHz"; then band="5GHz"; fi
                        fi

                        printf "%bRadio %d: %s%b\n" "${CYAN}" "$radio_count" "$iface" "${RESET}"
                        printf "  Interface: %s\n" "$iface"
                        [ -n "$hwmode" ] && printf "  Hardware/Mode: %s\n" "$hwmode"
                        printf "  Band: %b%s%b\n" "${GREEN}" "$band" "${RESET}"
                        [ -n "$mimo" ] && [ "$mimo" != "Unknown" ] && printf "  MIMO: %b%s%b\n" "${GREEN}" "$mimo" "${RESET}"
                        [ -n "$channel" ] && printf "  Channel: %s\n" "$channel"
                        printf "\n"
                        
                       if [ $radio_count -ge 2 ]; then
                           command -v usleep >/dev/null 2>&1 && usleep 400000
                       fi
                    done
                fi
                
                if [ $radio_count -eq 0 ]; then
                    printf "No wireless radios/interfaces detected.\n"
                    printf "  (This device may use non-standard drivers. Try 'iwinfo' manually.)\n"
                fi
                ;;
        esac
        
        printf "\n[B]ack | "
        i=1
        while [ $i -le $total_pages ]; do
            if [ $i -eq $page ]; then
                printf "%b[%d]%b " "${BOLD}" "$i" "${RESET}"
            else
                printf "%b[%d]%b " "${GREY}" "$i" "${RESET}"
            fi
            i=$((i + 1))
        done
        printf "| [N]ext | [M]ain menu\n"
        
        nav_choice=$(read_single_char)
        
        case "$nav_choice" in
            b|B) [ $page -gt 1 ] && page=$((page - 1)) ;;
            n|N) [ $page -lt $total_pages ] && page=$((page + 1)) ;;
            1|2|3|4) 
                if [ "$nav_choice" -ge 1 ] 2>/dev/null && [ "$nav_choice" -le $total_pages ]; then
                    page=$nav_choice
                fi
                ;;
            m|M) return ;;
        esac
    done
}

# -----------------------------
# 2) AdGuardHome UI Updates Management
# -----------------------------
show_agh_ui_help() {
    clear
    print_centered_header "AdGuardHome UI Updates - Help"
    
    cat << 'HELPEOF'
What does this setting control?
───────────────────────────────
This option controls whether AdGuardHome is allowed to automatically check for and 
download new versions of its web interface (UI) directly from the AdGuard servers.

Two modes:
• ENABLED  → AdGuardHome can update its own UI automatically when a new version is released
• DISABLED → UI updates are blocked (the --no-check-update flag is added)

Why would you want to disable UI updates?
─────────────────────────────────────────
On GL.iNet routers, the recommended approach is often to **disable automatic UI updates** because:

• GL.iNet provides their own pre-packaged, tested version of AdGuardHome
• Auto-updating the UI can sometimes cause compatibility issues with GL.iNet's custom firmware
• It may overwrite GL.iNet-specific patches or branding
• Manual updates through GL.iNet's firmware or opkg are usually safer and better integrated

When should you enable UI updates?
──────────────────────────────────
• You are running a standalone/community-installed AdGuardHome (not the GL.iNet version)
• You want the very latest UI features and fixes as soon as they are released
• You are comfortable troubleshooting potential compatibility problems

Quick recommendation for most GL.iNet users:
• Keep UI Updates **DISABLED** (default safe choice on GL firmware)
• Only enable if you specifically need a newer UI feature and understand the risks

In this menu you can:
1. Enable UI Updates (remove --no-check-update flag + restart AdGuardHome)
2. Disable UI Updates (add --no-check-update flag + restart AdGuardHome)
3. Return to main menu

Note: Changing this setting restarts AdGuardHome automatically. Your filtering rules and stats are preserved.
HELPEOF
    
    press_any_key
}

manage_agh_ui_updates() {
    while true; do
        clear
        print_centered_header "AdGuardHome UI Updates Management"
        
        if ! is_agh_running; then
            print_error "AdGuardHome is not running"
            printf "\n"
            press_any_key
            return
        fi
        
        agh_pid=$(pidof AdGuardHome)
        printf "%b\n" "${CYAN}Current Status:${RESET}"
        printf "  Running: %bYES%b (PID: %s)\n" "${GREEN}" "${RESET}" "$agh_pid"
        
        if grep -q -- "--no-check-update" "$AGH_INIT"; then
            printf "  UI Updates: %bDISABLED%b\n\n" "${RED}" "${RESET}"
        else
            printf "  UI Updates: %bENABLED%b\n\n" "${GREEN}" "${RESET}"
        fi
        
        printf "1️⃣  Enable UI Updates\n"
        printf "2️⃣  Disable UI Updates\n"
        printf "0️⃣  Main menu\n"
        printf "❓ Help\n"
        printf "\nChoose [1-2/0/?]: "
        read -r agh_choice
        printf "\n"
        
        case $agh_choice in
            1)
                if grep -q -- "--no-check-update" "$AGH_INIT"; then
                    sed -i 's/ --no-check-update//g' "$AGH_INIT"
                    print_success "UI updates enabled in AdGuardHome"
                    
                    /etc/init.d/adguardhome restart >/dev/null 2>&1
                    if [ $? -eq 0 ]; then
                        print_success "AdGuardHome restarted successfully"
                    else
                        print_error "Failed to restart AdGuardHome"
                    fi
                else
                    print_warning "UI updates are already enabled"
                fi
                press_any_key
                ;;
            2)
                if ! grep -q -- "--no-check-update" "$AGH_INIT"; then
                    sed -i '/procd_set_param command/ s/ -c/ --no-check-update -c/' "$AGH_INIT"
                    print_success "UI updates disabled in AdGuardHome"
                    
                    /etc/init.d/adguardhome restart >/dev/null 2>&1
                    if [ $? -eq 0 ]; then
                        print_success "AdGuardHome restarted successfully"
                    else
                        print_error "Failed to restart AdGuardHome"
                    fi
                else
                    print_warning "UI updates are already disabled"
                fi
                press_any_key
                ;;
            \?|h|H|❓)
                show_agh_ui_help
                ;;
            m|M|0)
                return
                ;;
            *)
                print_error "Invalid option"
                sleep 1
                ;;
        esac
    done
}

# -----------------------------
# 3) AdGuardHome Storage Management
# -----------------------------
show_agh_storage_help() {
    clear
    print_centered_header "AdGuardHome Filter Size Limit - Help"
    
    cat << 'HELPEOF'
AdGuardHome Filter Size Limit – BE3600 & Similar Models

Why the limit exists
────────────────────
On 512MB RAM routers (MT3600BE, some newer GL models), GL.iNet creates a 10MB file 
and mounts it as /etc/AdGuardHome/data/filters. This caps filter cache size to 
prevent AdGuardHome from consuming too much RAM and crashing the router.

Removing this limit lets you use bigger blocklists (e.g. HaGeZi Pro++, multi-list setups), 
but significantly increases RAM usage when filters are loaded/updated.

Risks if you remove it without mitigation
─────────────────────────────────────────
• High RAM pressure → router slowdown, OOM killer, or crashes
• Especially bad with many clients, VPN, or heavy filtering

Strong recommendation
─────────────────────
Enable **zram swap** first (Toolkit → option 4: Manage Zram Swap → Install & Enable).  
Zram gives fast compressed swap in RAM, greatly reduces memory pressure, 
and is safe for most GL.iNet 512MB devices.

Only remove the 10MB limit after zram is active.
HELPEOF
    
    press_any_key
}

manage_agh_storage() {
    while true; do
        clear
        print_centered_header "AdGuardHome Storage Management"
        
        if ! is_agh_running; then
            print_error "AdGuardHome is not running"
            printf "\n"
            press_any_key
            return
        fi
        
        AGH_WORKDIR=$(get_agh_workdir)
        if [ -z "$AGH_WORKDIR" ]; then
            print_error "Could not find AdGuardHome working directory"
            printf "\n"
            press_any_key
            return
        fi
        
        printf "%b\n" "${CYAN}Current Storage Status:${RESET}"
        printf "Working Directory: %b%s%b\n\n" "${GREEN}" "$AGH_WORKDIR" "${RESET}"
        
        if [ -d "$AGH_WORKDIR/data/filters" ]; then
            printf "%b\n" "${CYAN}Filters Directory:${RESET}"
            df -h "$AGH_WORKDIR/data/filters" 2>/dev/null | tail -1 | awk '{printf "  Total: %s | Used: %s | Free: %s\n", $2, $3, $4}'
        fi
        
        if [ -d "$AGH_WORKDIR/data" ]; then
            printf "\n%b\n" "${CYAN}Data Directory:${RESET}"
            df -h "$AGH_WORKDIR/data" 2>/dev/null | tail -1 | awk '{printf "  Total: %s | Used: %s | Free: %s\n", $2, $3, $4}'
        fi
        
        limit_active=0
        if grep -q "mount_filter_img" "$AGH_INIT" 2>/dev/null && ! grep -q "^[[:space:]]*#.*mount_filter_img" "$AGH_INIT" 2>/dev/null; then
            limit_active=1
            printf "\n  Filter Size Limit: %bACTIVE (10MB)%b\n" "${YELLOW}" "${RESET}"
        else
            printf "\n  Filter Size Limit: %bINACTIVE%b\n" "${GREEN}" "${RESET}"
        fi
        
        printf "\n1️⃣  Remove Filter Size Limitation\n"
        printf "2️⃣  Re-enable Filter Size Limitation\n"
        printf "0️⃣  Main menu\n"
        printf "❓ Help\n"
        printf "\nChoose [1-2/0/?]: "
        read -r storage_choice
        printf "\n"
        
        case $storage_choice in
            1)
                if [ $limit_active -eq 0 ]; then
                    print_warning "Filter size limitation is already removed"
                    press_any_key
                    continue
                fi
                
                cat << 'WARNEOF'
GL.iNet (MT3600BE & similar models) limits AdGuardHome filter cache to 10MB 
by creating a small tmpfs/loop-mounted partition at /etc/AdGuardHome/data/filters.

Removing this limit allows larger/more filter lists, but may cause high RAM usage 
and instability on 512MB devices when filters are big or many are enabled.
WARNEOF
                
                if ! swapon -s 2>/dev/null | grep -q zram; then
                    printf "\n%b\n" "${YELLOW}⚠️  WARNING: Zram swap is NOT enabled!${RESET}"
                    printf "%b\n\n" "${YELLOW}Strongly recommended: Enable zram swap first (in menu option 4)${RESET}"
                    printf "%b\n" "${YELLOW}→ it gives fast compressed swap in RAM and protects flash.${RESET}"
                fi
                
                printf "\n%b" "${YELLOW}Remove the 10MB limit anyway? [y/N]: ${RESET}"
                read -r confirm
                if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
                    printf "Operation cancelled.\n"
                    press_any_key
                    continue
                fi
                
                /etc/init.d/adguardhome stop >/dev/null 2>&1
                
                loop_dev=$(mount | grep "$AGH_WORKDIR/data/filters" | awk '{print $1}')
                if [ -n "$loop_dev" ]; then
                    umount "$loop_dev" 2>/dev/null
                    print_success "Unmounted filter partition"
                fi
                
                if [ -f "$AGH_WORKDIR/data.img" ]; then
                    rm -f "$AGH_WORKDIR/data.img"
                    print_success "Removed data.img file"
                fi
                
                sed -i '/mount_filter_img/s/^/# /' "$AGH_INIT"
                print_success "Disabled mount_filter_img in init script"
                
                /etc/init.d/adguardhome start >/dev/null 2>&1
                if [ $? -eq 0 ]; then
                    print_success "AdGuardHome restarted successfully"
                    printf "\n%b\n" "${GREEN}✅ Filter size limit removed!${RESET}"
                else
                    print_error "Failed to restart AdGuardHome"
                fi
                
                press_any_key
                ;;
            2)
                if ! grep -q "mount_filter_img" "$AGH_INIT"; then
                    print_warning "Filter size limitation feature (mount_filter_img) does not exist on this device/firmware."
                    printf "   No changes possible — your AdGuardHome is not restricted by the 10MB filter limit.\n"
                    press_any_key
                    continue
                fi

                if ! grep -q "^#.*mount_filter_img" "$AGH_INIT"; then
                    print_warning "Filter size limitation is already active (mount_filter_img is not commented out)."
                    press_any_key
                    continue
                fi
                
                /etc/init.d/adguardhome stop >/dev/null 2>&1
                
                sed -i '/mount_filter_img/s/^# //' "$AGH_INIT"
                print_success "Re-enabled mount_filter_img in init script"
                
                /etc/init.d/adguardhome start >/dev/null 2>&1
                if [ $? -eq 0 ]; then
                    print_success "AdGuardHome restarted successfully"
                    printf "\n%b\n" "${GREEN}✅ Filter size limit re-enabled!${RESET}"
                else
                    print_error "Failed to restart AdGuardHome"
                fi
                
                press_any_key
                ;;
            \?|h|H|❓)
                show_agh_storage_help
                ;;
            m|M|0)
                return
                ;;
            *)
                print_error "Invalid option"
                sleep 1
                ;;
        esac
    done
}

# -----------------------------
# 4) AdGuardHome Lists Management
# -----------------------------
show_agh_lists_help() {
    clear
    print_centered_header "AdGuardHome Lists - Help"
    
    cat << 'HELPEOF'
What are these lists?
─────────────────────
This option installs custom DNS filter lists for AdGuardHome to enhance ad blocking and streaming compatibility:

- **Phantasm22's Blocklist** (from https://github.com/phantasm22/AdGuardHome-Lists/blocklist.txt):  
  Blocks all Amazon Echo Show ads. It's derived from HaGeZi's Pro++ Blocklist for broad ad/tracking protection, curated for optimal performance on GL.iNet routers and Echo devices. Key features: Auto-updates, GPL-3.0 licensed, maintained by phantasm22 (last update Nov 2025).

- **Phantasm22's Allow List** (from https://github.com/phantasm22/AdGuardHome-Lists/allowlist.txt):  
  Unblocks essential domains for video streaming and apps like Roku, Apple TV, NBC Sports, Peacock, Hulu, Disney+, YouTube, Prime Video, HBO Max, Philo, and Tubi. Prevents false positives that could break functionality.

- **HaGeZi's Pro++ Blocklist**:  
  An aggressive DNS blocklist that sweeps away ads, affiliates, tracking, metrics, telemetry, phishing, malware, scams, fake sites, and more. It's a "maximum protection" version of HaGeZi's Multi series (Light/Normal/Pro/Pro++/Ultimate), with 229,928+ entries (as of 2024 data). More strict than Pro, it may include rare false positives limiting some app/website functions—best for experienced users who can whitelist as needed.

Why HaGeZi's Pro++ as the default base?
────────────────────────────────────────
It's actively maintained, provides comprehensive all-round protection, and strikes a strong balance between aggressive blocking and usability. Facts: Users report it blocks ~2x more than alternatives like OISD (e.g., 15%+ network-wide blocks) with minimal false positives; praised on Reddit, NextDNS, and Pi-hole forums for privacy gains without excessive whitelisting. Chosen here as the foundation for Phantasm22's list to ensure robust ad-free experience on routers.

These lists auto-update in AdGuardHome. Install only if you want enhanced blocking—monitor for any rare streaming breaks and whitelist via AdGuardHome UI.
HELPEOF
    
    press_any_key
}

manage_agh_lists() {
    while true; do
        clear
        print_centered_header "AdGuardHome Lists Manager"

        if ! is_agh_running; then
            print_error "AdGuardHome is not running"
            printf "\n"
            press_any_key
            return
        fi

        AGH_CONFIG=$(get_agh_config)
        if [ -z "$AGH_CONFIG" ]; then
            print_error "Could not find AdGuardHome config file"
            printf "\n"
            press_any_key
            return
        fi

        agh_pid=$(pidof AdGuardHome)
        printf "%bRunning: YES (PID: %s)%b\n" "${GREEN}" "$agh_pid" "${RESET}"
        printf "Config: %b%s%b\n\n" "${GREEN}" "$AGH_CONFIG" "${RESET}"

        # Recommended lists
        PHANTASM_BLOCKLIST="https://raw.githubusercontent.com/phantasm22/AdGuardHome-Lists/refs/heads/main/blocklist.txt"
        HAGEZI_BLOCKLIST="https://cdn.jsdelivr.net/gh/hagezi/dns-blocklists@latest/adblock/pro.plus.txt"
        PHANTASM_ALLOWLIST="https://raw.githubusercontent.com/phantasm22/AdGuardHome-Lists/refs/heads/main/allowlist.txt"

        LISTS_DATA=$(mktemp)

        # Recommended entries (status detected from config)
        printf "1|Phantasm22's Blocklist|Blocklist|%d|1|1\n" \
            "$(grep -c "Phantasm22's Blocklist" "$AGH_CONFIG")" >> "$LISTS_DATA"
        printf "2|HaGeZi's Pro++ Blocklist|Blocklist|%d|1|1\n" \
            "$(grep -c "HaGeZi's Pro++ Blocklist" "$AGH_CONFIG")" >> "$LISTS_DATA"
        printf "3|Phantasm22's Allow List|Allowlist|%d|1|1\n" \
            "$(grep -c "Phantasm22's Allow List" "$AGH_CONFIG")" >> "$LISTS_DATA"

        idx=3
        current_section=""
        name=""

        # ---- SAFE YAML PARSER (no subshells, no phantom rows) ----
        while IFS= read -r line; do
            case "$line" in
                "filters:"|"whitelist_filters:")
                    current_section="$line"
                    ;;
                *"- enabled:"*)
                    name=""
                    ;;
                *"name:"*)
                    name=$(printf "%s\n" "$line" \
                        | sed 's/^[[:space:]]*name:[[:space:]]*//; s/^"//; s/"$//')
                    ;;
                *"id:"*)
                    [ -z "$name" ] && continue

                    case "$current_section" in
                        "filters:")           type="Blocklist" ;;
                        "whitelist_filters:") type="Allowlist" ;;
                        *) continue ;;
                    esac

                    case "$name" in
                        "Phantasm22's Blocklist"|"HaGeZi's Pro++ Blocklist"|"Phantasm22's Allow List")
                            continue
                            ;;
                    esac

                    idx=$((idx + 1))
                    printf "%d|%s|%s|1|0|0\n" "$idx" "$name" "$type" >> "$LISTS_DATA"
                    ;;
            esac
        done < "$AGH_CONFIG"
        # ----------------------------------------------------------

        total_lists=$(wc -l < "$LISTS_DATA")

        while true; do
            clear
            print_centered_header "AdGuardHome Lists Manager"

            printf "%-5s %-12s %-50s %s\n" "Sel." "Type" "Name" "Status"
            printf "────────────────────────────────────────────────────────────────────────────────\n"

            while IFS='|' read -r idx name type status selected recommended; do
                sel_char="[ ]"
                [ "$selected" -eq 1 ] && sel_char="[✓]"

                name_display="${idx}. ${name}"
                [ "$recommended" -eq 1 ] && name_display="$name_display ★"

                name_pad=$(printf "%-50s" "$name_display")

                status_text="Installed"
                [ "$status" -eq 0 ] && status_text="Missing"

                printf "%-5s %-12s %s %s\n" "$sel_char" "$type" "$name_pad" "$status_text"
            done < "$LISTS_DATA"

            printf "────────────────────────────────────────────────────────────────────────────────\n"
            printf "[A] All   [N] None   [T#] Toggle (e.g. T1 T3)   [C] Confirm   [0] Back   [?] Help\n\n"
            printf "Default: Recommended lists (★) selected for install/reinstall, others unselected for removal\n"
            printf "Enter command: "
            read -r input

            case "$input" in
                [aA])
                    tmp=$(mktemp)
                    while IFS='|' read -r a b c d e f; do
                        printf "%s|%s|%s|%s|1|%s\n" "$a" "$b" "$c" "$d" "$f" >> "$tmp"
                    done < "$LISTS_DATA"
                    mv "$tmp" "$LISTS_DATA"
                    ;;
                [nN])
                    tmp=$(mktemp)
                    while IFS='|' read -r a b c d e f; do
                        printf "%s|%s|%s|%s|0|%s\n" "$a" "$b" "$c" "$d" "$f" >> "$tmp"
                    done < "$LISTS_DATA"
                    mv "$tmp" "$LISTS_DATA"
                    ;;
                [tT]*)
                    nums=$(printf "%s\n" "$input" | sed 's/[tT ]//g' | grep -o '[0-9]\+')
                    for num in $nums; do
                        tmp=$(mktemp)
                        while IFS='|' read -r a b c d e f; do
                            if [ "$a" -eq "$num" ]; then
                                e=$((1 - e))
                            fi
                            printf "%s|%s|%s|%s|%s|%s\n" "$a" "$b" "$c" "$d" "$e" "$f" >> "$tmp"
                        done < "$LISTS_DATA"
                        mv "$tmp" "$LISTS_DATA"
                    done
                    ;;
                [0]|[mM]|"")
                    rm -f "$LISTS_DATA"
                    return
                    ;;
                [?]|[\?]|❓)
                    show_agh_lists_help
                    ;;
                *)
                    print_error "Invalid command"
                    sleep 1
                    ;;
            esac
        done
    done
}


# -----------------------------
# 5) Zram Swap Management
# -----------------------------
show_zram_help() {
    clear
    print_centered_header "Zram Swap - Help"
    
    cat << 'HELPEOF'
Zram Swap – Quick Help

What is zram swap?
──────────────────
Zram creates a compressed block device in your router's RAM and uses it as swap space. 
Instead of writing swap data to slow flash storage (which wears it out quickly), zram 
compresses the data and keeps it in RAM. This is much faster and protects your NAND/eMMC.

Main benefits on GL.iNet routers:
• Greatly improves performance when RAM is low (e.g. heavy VPN, AdGuardHome, many clients)
• Reduces lag and stuttering under memory pressure
• Significantly extends the lifespan of your router's flash storage
• Uses very little CPU overhead on modern router SoCs

Typical recommendations:
• 25–50% of total RAM is a good starting size (e.g. 128–256 MB on a 512 MB router)
• Most GL.iNet users enable it if they run AdGuardHome + VPN or have ≥10–15 devices connected

When should you use it?
Yes → if your router frequently runs out of RAM or you notice slowdowns
No  → if you have 1 GB+ RAM and very light usage

Important notes:
• Zram uses some CPU to compress/decompress → not ideal on very old/slow CPUs
• Data in zram is lost on reboot (normal for swap)
• Routers with 512MiB flash or less will have a forced limit for AdGuardHome allow/block lists.
  See Option 3 - Manage AdGuardHome Storage

In this menu you can:
1. Install & enable zram swap
2. Disable it (stops and disables on boot)
3. Completely uninstall the package
HELPEOF
    
    press_any_key
}

manage_zram() {
    while true; do
        clear
        print_centered_header "Zram Swap Management"
        
        printf "%b\n" "${CYAN}Current Status:${RESET}"
        if command -v zram >/dev/null 2>&1 || [ -f /etc/init.d/zram ]; then
            if /etc/init.d/zram enabled 2>/dev/null; then
                printf "  Zram Swap: %bENABLED%b\n" "${GREEN}" "${RESET}"
                
                if [ -f /sys/block/zram0/disksize ]; then
                    disksize=$(cat /sys/block/zram0/disksize 2>/dev/null)
                    disksize_mb=$((disksize / 1024 / 1024))
                    printf "  Disk Size: %d MB\n" "$disksize_mb"
                fi
                
                if swapon -s 2>/dev/null | grep -q zram; then
                    printf "  Status: %bACTIVE%b\n" "${GREEN}" "${RESET}"
                else
                    printf "  Status: %bINACTIVE%b\n" "${YELLOW}" "${RESET}"
                fi
            else
                printf "  Zram Swap: %bDISABLED%b\n" "${YELLOW}" "${RESET}"
            fi
        else
            printf "  Zram Swap: %bNOT INSTALLED%b\n" "${RED}" "${RESET}"
        fi
        
        printf "\n1️⃣  Install and Enable\n"
        printf "2️⃣  Disable\n"
        printf "3️⃣  Uninstall Package\n"
        printf "0️⃣  Main menu\n"
        printf "❓ Help\n"
        printf "\nChoose [1-3/0/?]: "
        read -r zram_choice
        printf "\n"
        
        case $zram_choice in
            1)
                if ! opkg list-installed | grep -q "^zram-swap"; then
                    print_warning "zram-swap not installed, installing..."
                    if [ "$opkg_updated" -eq 0 ]; then
                        printf "Updating package lists...\n"
                        opkg update >/dev/null 2>&1
                        opkg_updated=1
                    fi
                    opkg install zram-swap >/dev/null 2>&1
                    if opkg list-installed | grep -q "^zram-swap"; then
                        print_success "zram-swap package installed"
                    else
                        print_error "Failed to install zram-swap"
                        press_any_key
                        continue
                    fi
                fi
                
                if [ -f /etc/init.d/zram ]; then
                    /etc/init.d/zram enable >/dev/null 2>&1
                    /etc/init.d/zram start >/dev/null 2>&1
                    print_success "Zram swap enabled and started"
                    
                    sleep 2
                    if swapon -s 2>/dev/null | grep -q zram; then
                        print_success "Zram swap is working correctly"
                    else
                        print_warning "Zram swap may not be working properly"
                    fi
                else
                    print_error "Zram init script not found"
                fi
                press_any_key
                ;;
            2)
                if [ -f /etc/init.d/zram ]; then
                    /etc/init.d/zram stop >/dev/null 2>&1
                    /etc/init.d/zram disable >/dev/null 2>&1
                    print_success "Zram swap disabled and stopped"
                else
                    print_warning "Zram swap is not installed"
                fi
                press_any_key
                ;;
            3)
                if opkg list-installed | grep -q "^zram-swap"; then
                    printf "%b" "${YELLOW}Remove zram-swap package? [y/N]: ${RESET}"
                    read -r confirm
                    if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
                        [ -f /etc/init.d/zram ] && /etc/init.d/zram stop >/dev/null 2>&1
                        opkg remove zram-swap >/dev/null 2>&1
                        print_success "zram-swap package removed"
                    else
                        printf "Removal cancelled.\n"
                    fi
                else
                    print_warning "zram-swap package is not installed"
                fi
                press_any_key
                ;;
            \?|h|H)
                show_zram_help
                ;;
            m|M|0)
                return
                ;;
            *)
                print_error "Invalid option"
                sleep 1
                ;;
        esac
    done
}

# -----------------------------
# 6) CPU & Disk Benchmarks
# -----------------------------
benchmark_system() {
    while true; do
        clear
        print_centered_header "System Benchmarks"
        
        printf "1️⃣  CPU Stress Test\n"
        printf "2️⃣  CPU Benchmark (OpenSSL)\n"
        printf "3️⃣  Disk I/O Benchmark\n"
        printf "0️⃣  Back to main menu\n"
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
                        continue
                    fi
                fi
                
                cpu_cores=$(grep -c "^processor" /proc/cpuinfo 2>/dev/null)
                [ -z "$cpu_cores" ] && cpu_cores=1
                
                printf "\nHow many seconds to run stress test? [default: 60]: "
                read -r duration
                [ -z "$duration" ] && duration=60
                
                case "$duration" in
                    ''|*[!0-9]*) duration=60 ;;
                esac
                
                printf "\n%b\n" "${YELLOW}⏳ Running stress test on $cpu_cores cores for $duration seconds...${RESET}"
                printf "%b\n\n" "${YELLOW}💡 Monitor with 'top' in another session${RESET}"
                
                stress --cpu "$cpu_cores" --timeout "${duration}s" --verbose
                
                printf "\n"
                print_success "Stress test completed"
                press_any_key
                ;;
            2)
                if ! command -v openssl >/dev/null 2>&1; then
                    print_error "OpenSSL not found"
                    press_any_key
                    continue
                fi
                
                printf "\n%b\n" "${CYAN}🔧 Running OpenSSL speed benchmark...${RESET}"
                printf "%b\n\n" "${YELLOW}⏳ This will take a minute...${RESET}"
                
                printf "%b\n" "${CYAN}Single-threaded AES-256-GCM:${RESET}"
                openssl speed -elapsed -evp aes-256-gcm 2>&1 | tail -3
                
                printf "\n%b\n" "${CYAN}Single-threaded SHA256:${RESET}"
                openssl speed -elapsed sha256 2>&1 | tail -3
                
                printf "\n%b\n" "${CYAN}RSA 2048-bit signing:${RESET}"
                openssl speed -elapsed rsa2048 2>&1 | tail -5
                
                printf "\n"
                print_success "Benchmark completed"
                press_any_key
                ;;
            3)
                printf "%b\n" "${CYAN}🔧 Disk I/O Benchmark${RESET}\n"
                
                available_kb=$(df -k . | awk 'NR==2 {print $4}')
                
                test_size=0
                test_name=""
                if [ "$available_kb" -ge $((1000 * 1024)) ]; then
                    test_size=1000
                    test_name="1GB"
                elif [ "$available_kb" -ge $((500 * 1024)) ]; then
                    test_size=500
                    test_name="500MB"
                elif [ "$available_kb" -ge $((250 * 1024)) ]; then
                    test_size=250
                    test_name="250MB"
                elif [ "$available_kb" -ge $((125 * 1024)) ]; then
                    test_size=125
                    test_name="125MB"
                elif [ "$available_kb" -ge $((62 * 1024)) ]; then
                    test_size=62
                    test_name="62MB"
                elif [ "$available_kb" -ge $((31 * 1024)) ]; then
                    test_size=31
                    test_name="31MB"
                else
                    print_error "Not enough disk space (need at least 31MB)"
                    printf "Available: %d MB\n" $((available_kb / 1024))
                    press_any_key
                    continue
                fi
                
                printf "Test size: %b%s%b\n" "${GREEN}" "$test_name" "${RESET}"
                print_success "Sufficient disk space available"
                
                printf "\n%b\n" "${YELLOW}⏳ Running write test ($test_name)...${RESET}"
                sync
                write_start=$(date +%s)
                dd if=/dev/zero of=./testfile bs=1M count=$test_size conv=fsync 2>&1 | tail -3
                write_end=$(date +%s)
                write_time=$((write_end - write_start))
                [ "$write_time" -eq 0 ] && write_time=1
                
                if [ -f ./testfile ]; then
                    write_speed=$((test_size / write_time))
                    printf "%b\n" "${GREEN}✅ Write speed: ~${write_speed} MB/s${RESET}"
                fi
                
                printf "\n%b\n" "${YELLOW}⏳ Running read test ($test_name)...${RESET}"
                sync
                echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true
                read_start=$(date +%s)
                dd if=./testfile of=/dev/null bs=1M 2>&1 | tail -3
                read_end=$(date +%s)
                read_time=$((read_end - read_start))
                [ "$read_time" -eq 0 ] && read_time=1
                
                read_speed=$((test_size / read_time))
                printf "%b\n" "${GREEN}✅ Read speed: ~${read_speed} MB/s${RESET}"
                
                rm -f ./testfile
                printf "\n"
                print_success "Disk benchmark completed"
                press_any_key
                ;;
            m|M|0)
                return
                ;;
            *)
                print_error "Invalid option"
                sleep 1
                ;;
        esac
    done
}

# -----------------------------
# 7) UCI Configuration Viewer
# -----------------------------
view_uci_config() {
    while true; do
        clear
        print_centered_header "System Configuration Viewer"
        
        printf "1️⃣  Wireless Networks\n"
        printf "2️⃣  Network Configuration\n"
        printf "3️⃣  VPN Configuration\n"
        printf "4️⃣  System Settings\n"
        printf "5️⃣  Cloud Services\n"
        printf "0️⃣  Back to main menu\n"
        printf "\nChoose [1-5/0]: "
        read -r config_choice
        printf "\n"
        
        case $config_choice in
            1)
                clear
                print_centered_header "Wireless Networks"
                
                all_ifaces=""
                for iface in $(uci show wireless 2>/dev/null | grep "wifi-iface" | cut -d'.' -f2 | cut -d'=' -f1 | sort -u); do
                    ssid=$(uci get wireless.${iface}.ssid 2>/dev/null)
                    [ -n "$ssid" ] && all_ifaces="$all_ifaces $iface"
                done
                
                mlo_ifaces=""
                five_ifaces=""
                two_ifaces=""
                
                for iface in $all_ifaces; do
                    device=$(uci get wireless.${iface}.device 2>/dev/null)
                    band=$(uci get wireless.${device}.band 2>/dev/null)
                    
                    if uci get wireless.${iface}.mlo 2>/dev/null | grep -q "1"; then
                        mlo_ifaces="$mlo_ifaces $iface"
                    elif [ "$band" = "5g" ] || [ "$band" = "6g" ]; then
                        five_ifaces="$five_ifaces $iface"
                    elif [ "$band" = "2g" ]; then
                        two_ifaces="$two_ifaces $iface"
                    else
                        two_ifaces="$two_ifaces $iface"
                    fi
                done
                
                count=0
                for iface in $mlo_ifaces $five_ifaces $two_ifaces; do

                    if [ $((count % 2)) -eq 0 ] && [ $count -gt 0 ]; then
                       press_any_key
                       clear
                       print_centered_header "Wireless Networks"
                    fi
                    
                    ssid=$(uci get wireless.${iface}.ssid 2>/dev/null)
                    key=$(uci get wireless.${iface}.key 2>/dev/null)
                    encryption=$(uci get wireless.${iface}.encryption 2>/dev/null)
                    disabled=$(uci get wireless.${iface}.disabled 2>/dev/null)
                    hidden=$(uci get wireless.${iface}.hidden 2>/dev/null)
                    device=$(uci get wireless.${iface}.device 2>/dev/null)
                    mode=$(uci get wireless.${iface}.mode 2>/dev/null)
                    
                    band=$(uci get wireless.${device}.band 2>/dev/null)
                    htmode=$(uci get wireless.${device}.htmode 2>/dev/null)
                    channel=$(uci get wireless.${device}.channel 2>/dev/null)
                    
                    case "$band" in
                        2g) band_name="2.4GHz" ;;
                        5g) band_name="5GHz" ;;
                        6g) band_name="6GHz" ;;
                        *) band_name="Unknown" ;;
                    esac
                    
                    if uci get wireless.${iface}.mlo 2>/dev/null | grep -q "1"; then
                        band_name="MLO (Multi-Link)"
                    fi
                    
                    printf "%b\n" "${CYAN}Interface: $iface ($band_name)${RESET}"
                    printf "  SSID: %b%s%b\n" "${GREEN}" "$ssid" "${RESET}"
                    [ -n "$key" ] && printf "  Password: %b%s%b\n" "${YELLOW}" "$key" "${RESET}"
                    [ -n "$encryption" ] && printf "  Encryption: %s\n" "$encryption"
                    
                    if [ "$hidden" = "1" ]; then
                        printf "  Visibility: %bHidden%b\n" "${YELLOW}" "${RESET}"
                    else
                        printf "  Visibility: %bVisible%b\n" "${GREEN}" "${RESET}"
                    fi
                    
                    [ -n "$mode" ] && printf "  Mode: %s\n" "$mode"
                    [ -n "$htmode" ] && printf "  Bandwidth: %s\n" "$htmode"
                    [ -n "$channel" ] && printf "  Channel: %s\n" "$channel"
                    
                    if [ "$disabled" = "1" ]; then
                        printf "  Status: %bDisabled%b\n" "${RED}" "${RESET}"
                    else
                        printf "  Status: %bEnabled%b\n" "${GREEN}" "${RESET}"
                    fi
                    printf "\n"
                    count=$((count + 1))
                done
                
                press_any_key
                ;;
            2)
                clear
                print_centered_header "Network Configuration"
                
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
                
                press_any_key
                ;;
            3)
                clear
                print_centered_header "VPN Configuration"
                
                found_vpn=0
                
                if uci show network 2>/dev/null | grep -q "proto='wireguard'"; then
                    printf "%b\n" "${CYAN}WireGuard Servers:${RESET}"
                    for iface in $(uci show network | grep "proto='wireguard'" | cut -d'.' -f2 | cut -d'=' -f1); do
                        private_key=$(uci get network.${iface}.private_key 2>/dev/null)
                        listen_port=$(uci get network.${iface}.listen_port 2>/dev/null)
                        addresses=$(uci get network.${iface}.addresses 2>/dev/null)
                        
                        printf "  Interface: %b%s%b\n" "${GREEN}" "$iface" "${RESET}"
                        [ -n "$listen_port" ] && printf "    Listen Port: %s\n" "$listen_port"
                        [ -n "$addresses" ] && printf "    Addresses: %s\n" "$addresses"
                        [ -n "$private_key" ] && printf "    Private Key: %b[configured]%b\n" "${YELLOW}" "${RESET}"
                        printf "\n"
                        found_vpn=1
                    done
                fi
                
                if uci show wireguard 2>/dev/null | grep -q "=peers"; then
                    printf "%b\n" "${CYAN}WireGuard Clients:${RESET}"
                    for peer in $(uci show wireguard 2>/dev/null | grep "=peers" | cut -d'.' -f2 | cut -d'=' -f1); do
                        name=$(uci get wireguard.${peer}.name 2>/dev/null)
                        endpoint=$(uci get wireguard.${peer}.end_point 2>/dev/null)
                        addr_v4=$(uci get wireguard.${peer}.address_v4 2>/dev/null)
                        allowed=$(uci get wireguard.${peer}.allowed_ips 2>/dev/null)
                        keepalive=$(uci get wireguard.${peer}.persistent_keepalive 2>/dev/null)
                        
                        printf "  Peer: %b%s%b\n" "${GREEN}" "${name:-$peer}" "${RESET}"
                        [ -n "$endpoint" ] && printf "    Endpoint: %s\n" "$endpoint"
                        [ -n "$addr_v4" ] && printf "    Address: %s\n" "$addr_v4"
                        [ -n "$allowed" ] && printf "    Allowed IPs: %s\n" "$allowed"
                        [ -n "$keepalive" ] && printf "    Keepalive: %s sec\n" "$keepalive"
                        printf "\n"
                        found_vpn=1
                    done
                fi
                
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
                        found_vpn=1
                    done
                fi
                
                if [ "$found_vpn" -eq 0 ]; then
                    print_warning "No active VPN configurations found"
                    printf "\n"
                fi
                
                press_any_key
                ;;
            4)
                clear
                print_centered_header "System Settings"
                
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
                
                press_any_key
                ;;
            5)
                clear
                print_centered_header "☁️  Cloud Services"
                
                printf "%b\n" "${CYAN}GoodCloud:${RESET}"
                if [ -f /etc/config/gl-cloud ]; then
                    gc_enable=$(uci get gl-cloud.@cloud[0].enable 2>/dev/null)
                    gc_deviceid=$(uci get gl-cloud.@cloud[0].token 2>/dev/null)
                    gc_server=$(uci get gl-cloud.@cloud[0].server 2>/dev/null)
                    gc_email=$(uci get gl-cloud.@cloud[0].email 2>/dev/null)
                    
                    if [ "$gc_enable" = "1" ]; then
                        printf "  Status: %bENABLED%b\n" "${GREEN}" "${RESET}"
                    else
                        printf "  Status: %bDISABLED%b\n" "${RED}" "${RESET}"
                    fi
                    
                    [ -n "$gc_email" ] && printf "  Account: %b%s%b\n" "${GREEN}" "$gc_email" "${RESET}"
                    [ -n "$gc_server" ] && printf "  Server: %s\n" "$gc_server"
                    [ -n "$gc_deviceid" ] && printf "  Token: %s\n" "${gc_deviceid:0:16}..."
                else
                    print_warning "GoodCloud not configured"
                fi
                
                printf "\n%b\n" "${CYAN}AstroWarp:${RESET}"
                if ip link show mptun0 >/dev/null 2>&1 && ip -4 addr show mptun0 | grep -q 'inet '; then
                    printf "  Status: %bACTIVE%b\n" "${GREEN}" "${RESET}"
                    mptun_ip=$(ip -4 addr show mptun0 | grep 'inet ' | awk '{print $2}')
                    [ -n "$mptun_ip" ] && printf "  Interface: mptun0 (%s)\n" "$mptun_ip"
                else
                    printf "  Status: %bNOT ACTIVE%b\n" "${RED}" "${RESET}"
                    printf "  (No mptun0 interface or no IP assigned)\n"
                fi
                
                printf "\n"
                press_any_key
                ;;
            m|M|0)
                return
                ;;
            *)
                print_error "Invalid option"
                sleep 1
                ;;
        esac
    done
}

# -----------------------------
# Check for updates on start
# -----------------------------
command -v clear >/dev/null 2>&1 && clear
printf "%b\n" "$SPLASH"
check_self_update "$@"

# -----------------------------
# Main Menu
# -----------------------------
show_menu() {
    while true; do
        clear
        printf "%b\n" "$SPLASH"
        printf "%b\n" "${CYAN}Please select an option:${RESET}\n"
        printf "1️⃣  Show Hardware Information\n"
        printf "2️⃣  Manage AdGuardHome UI Updates\n"
        printf "3️⃣  Manage AdGuardHome Storage\n"
        printf "4️⃣  Manage AdGuardHome Lists\n"
        printf "5️⃣  Manage Zram Swap\n"
        printf "6️⃣  System Benchmarks (CPU & Disk)\n"
        printf "7️⃣  View System Configuration (UCI)\n"
        printf "8️⃣  Check for Update\n"
        printf "0️⃣  Exit\n"
        printf "\nChoose [1-8/0]: "
        read opt
        
        case $opt in
            1) show_hardware_info ;;
            2) manage_agh_ui_updates ;;
            3) manage_agh_storage ;;
            4) manage_agh_lists ;;
            5) manage_zram ;;
            6) benchmark_system ;;
            7) view_uci_config ;;
            8) check_self_update "$@"; press_any_key ;;
            0) clear; printf "\n%b\n\n" "${GREEN}✅ Thanks for using GL.iNet Toolkit!${RESET}"; exit 0 ;;
            *) print_error "Invalid option"; sleep 1 ;;
        esac
    done
}

# -----------------------------
# Start
# -----------------------------
show_menu
