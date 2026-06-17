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

detect_interface() {

    INTERFACE=$(ip route |
        grep default |
        awk '{print $5}' |
        head -n1)

    if [[ -z "$INTERFACE" ]]; then
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

#########################################
# Feature Functions
#########################################

show_network_status() {

    clear

    detect_interface

    echo "===================================="
    echo " Network Status"
    echo "===================================="
    echo

    echo "OS:"
    echo "$OS_NAME $OS_VERSION"
    echo

    echo "Network Manager:"
    echo "$NETWORK_MANAGER"
    echo

    echo "Interface:"
    echo "$INTERFACE"
    echo

    echo "IPv4 Address:"
    ip -4 addr show "$INTERFACE" 2>/dev/null | grep inet
    echo

    echo "Gateway:"
    ip route | grep default
    echo

    echo "DNS:"
    grep nameserver /etc/resolv.conf 2>/dev/null
    echo

    pause
}

set_static_ip() {

    clear

    detect_interface

    echo "===================================="
    echo " Set Static IP"
    echo "===================================="
    echo

    echo "Interface: $INTERFACE"
    echo

    echo "Current Address:"
    ip -4 addr show "$INTERFACE" | grep inet
    echo

    read -rp "IP Address: " IP
    read -rp "Prefix Length (24): " PREFIX
    read -rp "Gateway: " GATEWAY
    read -rp "DNS Server: " DNS

    echo
    echo "New Configuration"
    echo "-----------------"
    echo "IP:      $IP/$PREFIX"
    echo "Gateway: $GATEWAY"
    echo "DNS:     $DNS"
    echo

    read -rp "Apply changes? (y/N): " CONFIRM

    if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
        echo
        echo "Cancelled."
        pause
        return
    fi

    case "$NETWORK_MANAGER" in

        NetworkManager)

            mkdir -p backups

            cp -r \
                /etc/NetworkManager/system-connections \
                "./backups/nm-$(date +%F-%H%M%S)" \
                2>/dev/null

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

            mkdir -p backups

            cp \
                /etc/network/interfaces \
                "./backups/interfaces-$(date +%F-%H%M%S)"

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

    clear

    echo "===================================="
    echo " Return To DHCP"
    echo "===================================="
    echo

    echo "Feature not yet implemented."
    echo

    pause
}

update_system() {

    clear

    echo "===================================="
    echo " System Update"
    echo "===================================="
    echo

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
detect_interface

#########################################
# Main Menu
#########################################

while true
do

    detect_interface

    clear

    echo "===================================="
    echo " Network Toolkit"
    echo "===================================="
    echo
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
