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

detect_network_manager() {

    if command -v nmcli >/dev/null 2>&1; then
        NETWORK_MANAGER="NetworkManager"

    elif [[ -f /etc/network/interfaces ]]; then
        NETWORK_MANAGER="ifupdown"

    else
        NETWORK_MANAGER="unknown"
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

    echo "===================================="
    echo " Set Static IP"
    echo "===================================="
    echo

    echo "Feature not yet implemented."
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
