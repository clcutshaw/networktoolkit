#!/bin/bash

#########################################
# Global Variables
#########################################

LOGFILE="./toolkit.log"

#########################################
# Helper Functions
#########################################

log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOGFILE"
}

pause() {
    read -rp "Press Enter to continue..."
}

print_header() {
    clear
    echo "===================================="
    echo " $1"
    echo "===================================="
    echo
}

print_section() {
    echo "$1"
    echo "------------------------------------"
}

confirm_action() {
    local response

    read -rp "Apply this configuration? (y/N): " response
    [[ "$response" =~ ^[Yy]$ ]]
}

detect_os() {

    if [[ -f /etc/os-release ]]; then
        source /etc/os-release

        OS_NAME="$NAME"
        OS_ID="$ID"
        OS_VERSION="$VERSION_ID"
    else
        OS_NAME="Unknown"
        OS_ID="unknown"
        OS_VERSION="unknown"
    fi
}

read_default_route() {

    local route
    local index
    local -a route_fields

    INTERFACE=""
    CURRENT_GATEWAY=""

    route=$(ip -4 route show default 2>/dev/null)
    route=${route%%$'\n'*}

    [[ -n "$route" ]] || return 1

    read -ra route_fields <<< "$route"

    for ((index = 0; index < ${#route_fields[@]}; index++)); do
        case "${route_fields[index]}" in
            via)
                CURRENT_GATEWAY="${route_fields[index + 1]:-}"
                ;;
            dev)
                INTERFACE="${route_fields[index + 1]:-}"
                ;;
        esac
    done

    [[ -n "$INTERFACE" ]]
}

detect_interface() {

    if ! read_default_route; then
        INTERFACE="Not Detected"
    fi
}

detect_network_manager() {

    if [[ -f /etc/network/interfaces ]]; then
        NETWORK_MANAGER="ifupdown"
        return
    fi

    if systemctl is-active --quiet NetworkManager; then
        NETWORK_MANAGER="NetworkManager"
        return
    fi

    if systemctl is-active --quiet systemd-networkd; then
        NETWORK_MANAGER="systemd-networkd"
        return
    fi

    NETWORK_MANAGER="unknown"
}

collect_network_state() {

    local address_output
    local address_line
    local address_cidr=""
    local directive
    local value
    local index
    local -a address_fields

    CURRENT_IP=""
    CURRENT_PREFIX=""
    CURRENT_DNS=""

    detect_interface

    [[ "$INTERFACE" != "Not Detected" ]] || return 1

    address_output=$(ip -o -4 addr show dev "$INTERFACE" scope global 2>/dev/null)
    address_line=${address_output%%$'\n'*}

    read -ra address_fields <<< "$address_line"

    for ((index = 0; index < ${#address_fields[@]}; index++)); do
        if [[ "${address_fields[index]}" == "inet" ]]; then
            address_cidr="${address_fields[index + 1]:-}"
            break
        fi
    done

    [[ "$address_cidr" == */* ]] || return 1

    CURRENT_IP=${address_cidr%/*}
    CURRENT_PREFIX=${address_cidr#*/}

    if [[ -r /etc/resolv.conf ]]; then
        while read -r directive value _; do
            if [[ "$directive" == "nameserver" ]]; then
                CURRENT_DNS="$value"
                break
            fi
        done < /etc/resolv.conf
    fi

    return 0
}

print_network_config() {

    printf "%-15s %s\n" "IP Address:" "$1"
    printf "%-15s %s\n" "Prefix:" "$2"
    printf "%-15s %s\n" "Gateway:" "$3"
    printf "%-15s %s\n" "DNS:" "$4"
}

backup_network_config() {

    local timestamp
    local backup_path

    timestamp=$(date +%F-%H%M%S)

    if ! mkdir -p backups || ! chmod 700 backups; then
        return 1
    fi

    case "$NETWORK_MANAGER" in

        NetworkManager)
            backup_path="./backups/nm-$timestamp"
            cp -a \
                /etc/NetworkManager/system-connections \
                "$backup_path" || return 1
            ;;

        ifupdown)
            backup_path="./backups/interfaces-$timestamp"
            cp -a \
                /etc/network/interfaces \
                "$backup_path" || return 1
            ;;

        *)
            return 1
            ;;

    esac

    log_message "Backed up network configuration to $backup_path"
    return 0
}

#########################################
# Feature Functions
#########################################

show_network_status() {

    if ! collect_network_state; then
        print_header "Network Status"
        echo "Unable to detect an active IPv4 network interface."
        echo
        pause
        return
    fi

    print_header "Network Status"

    echo "OS:"
    echo "$OS_NAME $OS_VERSION"
    echo

    echo "Network Manager:"
    echo "$NETWORK_MANAGER"
    echo

    echo "Interface:"
    echo "$INTERFACE"
    echo

    print_section "Current Configuration"
    print_network_config \
        "$CURRENT_IP" \
        "$CURRENT_PREFIX" \
        "$CURRENT_GATEWAY" \
        "$CURRENT_DNS"
    echo

    pause
}

set_static_ip() {

    if ! collect_network_state; then
        print_header "Set Static IP"
        echo "Unable to detect an active IPv4 network interface."
        echo
        pause
        return
    fi

    print_header "Set Static IP"

    echo "Interface: $INTERFACE"
    echo

    print_section "Current Configuration"
    print_network_config \
        "$CURRENT_IP" \
        "$CURRENT_PREFIX" \
        "$CURRENT_GATEWAY" \
        "$CURRENT_DNS"
    echo

    print_section "Configuration Changes"
    echo "Press Enter to keep the current value."
    echo

    read -rp "IP Address [$CURRENT_IP]: " IP
    read -rp "Prefix Length [$CURRENT_PREFIX]: " PREFIX
    read -rp "Gateway [$CURRENT_GATEWAY]: " GATEWAY
    read -rp "DNS Server [$CURRENT_DNS]: " DNS

    [[ -z "$IP" ]] && IP="$CURRENT_IP"
    [[ -z "$PREFIX" ]] && PREFIX="$CURRENT_PREFIX"
    [[ -z "$GATEWAY" ]] && GATEWAY="$CURRENT_GATEWAY"
    [[ -z "$DNS" ]] && DNS="$CURRENT_DNS"

    echo
    print_section "Current Configuration"
    print_network_config \
        "$CURRENT_IP" \
        "$CURRENT_PREFIX" \
        "$CURRENT_GATEWAY" \
        "$CURRENT_DNS"

    echo
    print_section "New Configuration"
    print_network_config \
        "$IP" \
        "$PREFIX" \
        "$GATEWAY" \
        "$DNS"
    echo

    if ! confirm_action; then
        echo
        echo "Cancelled."
        pause
        return
    fi

    if ! backup_network_config; then
        echo
        echo "Unable to back up the current network configuration."
        pause
        return
    fi

    case "$NETWORK_MANAGER" in

        NetworkManager)

            CONNECTION=$(nmcli -t -f NAME,DEVICE connection show |
                grep ":$INTERFACE$" |
                head -n1 |
                cut -d: -f1)

            if [[ -z "$CONNECTION" ]]; then
                echo
                echo "Unable to find NetworkManager connection."
                pause
                return
            fi

            nmcli connection modify "$CONNECTION" \
                ipv4.method manual \
                ipv4.addresses "$IP/$PREFIX" \
                ipv4.gateway "$GATEWAY" \
                ipv4.dns "$DNS"

            nmcli connection down "$CONNECTION"
            nmcli connection up "$CONNECTION"

            ;;

        ifupdown)

            cat > /etc/network/interfaces << EOF
auto lo
iface lo inet loopback

auto $INTERFACE
iface $INTERFACE inet static
    address $IP/$PREFIX
    gateway $GATEWAY
    dns-nameservers $DNS
EOF

            systemctl restart networking || true

            ;;

        *)

            echo
            echo "Unsupported network manager."
            pause
            return
            ;;

    esac

    log_message "Configured static IP $IP/$PREFIX on $INTERFACE"

    echo
    echo "Static IP configuration applied."
    echo

    pause
}

set_dhcp() {

    if ! collect_network_state; then
        print_header "Return To DHCP"
        echo "Unable to detect an active IPv4 network interface."
        echo
        pause
        return
    fi

    print_header "Return To DHCP"

    echo "Interface: $INTERFACE"
    echo

    print_section "Current Configuration"
    print_network_config \
        "$CURRENT_IP" \
        "$CURRENT_PREFIX" \
        "$CURRENT_GATEWAY" \
        "$CURRENT_DNS"

    echo
    print_section "Proposed Configuration"
    echo "IPv4 Method:    DHCP"
    echo

    if ! confirm_action; then
        echo
        echo "Cancelled."
        echo
        pause
        return
    fi

    if ! backup_network_config; then
        echo
        echo "Unable to back up the current network configuration."
        pause
        return
    fi

    case "$NETWORK_MANAGER" in

        NetworkManager)

            CONNECTION=$(nmcli -t -f NAME,DEVICE connection show |
                grep ":$INTERFACE$" |
                head -n1 |
                cut -d: -f1)

            if [[ -z "$CONNECTION" ]]; then
                echo
                echo "Unable to find NetworkManager connection."
                pause
                return
            fi

            if ! nmcli connection modify "$CONNECTION" \
                ipv4.method auto \
                ipv4.addresses "" \
                ipv4.gateway "" \
                ipv4.dns ""; then
                echo
                echo "Unable to update NetworkManager connection."
                pause
                return
            fi

            if ! nmcli connection down "$CONNECTION" ||
                ! nmcli connection up "$CONNECTION"; then
                echo
                echo "Unable to reactivate NetworkManager connection."
                pause
                return
            fi

            ;;

        ifupdown)

            if ! cat > /etc/network/interfaces << EOF
auto lo
iface lo inet loopback

auto $INTERFACE
iface $INTERFACE inet dhcp
EOF
            then
                echo
                echo "Unable to update /etc/network/interfaces."
                pause
                return
            fi

            if ! systemctl restart networking; then
                echo
                echo "Unable to restart networking."
                pause
                return
            fi

            ;;

        *)

            echo
            echo "DHCP configuration is not yet implemented for $NETWORK_MANAGER."
            pause
            return
            ;;

    esac

    log_message "Configured DHCP on $INTERFACE using $NETWORK_MANAGER"

    echo
    echo "DHCP configuration applied."
    echo

    pause
}

update_system() {
    print_header "System Update"

    case "$OS_ID" in

        debian|ubuntu|raspbian)

            apt update
            apt upgrade -y
            apt autoremove -y
            ;;

        rocky|rhel|almalinux|fedora)

            dnf upgrade -y
            ;;

        arch)

            pacman -Syu --noconfirm
            ;;

        *)

            echo "Unsupported operating system."
            pause
            return
            ;;
    esac

    log_message "System updated"

    echo
    echo "System update complete."
    echo

    pause
}

#########################################
# Initialization
#########################################

if [[ $EUID -ne 0 ]]; then
    echo "Please run with sudo."
    exit 1
fi

detect_os
detect_network_manager

#########################################
# Main Menu
#########################################

while true
do

    detect_interface

    print_header "Network Toolkit"
    echo "OS: $OS_NAME $OS_VERSION"
    echo "Network Manager: $NETWORK_MANAGER"
    echo "Interface: $INTERFACE"
    echo
    echo "1) Show Network Status"
    echo "2) Set Static IP"
    echo "3) Return To DHCP"
    echo "7) Update System"
    echo "0) Exit"
    echo

    read -rp "Select Option: " CHOICE

    case "$CHOICE" in

        1)
            show_network_status
            ;;

        2)
            set_static_ip
            ;;

        3)
            set_dhcp
            ;;

        7)
            update_system
            ;;

        0)
            echo
            echo "Goodbye."
            echo
            exit 0
            ;;

        *)
            echo
            echo "Invalid selection."
            sleep 2
            ;;

    esac

done
