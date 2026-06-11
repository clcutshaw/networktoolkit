#!/bin/bash

#########################################
# Global Variables
#########################################

LOGFILE="./toolkit.log"

#########################################
# Helper Functions
#########################################

log_message() {
    ...
}

pause() {
    ...
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
    ip -4 addr show "$INTERFACE" | grep inet
    echo

    echo "Gateway:"
    ip route | grep default
    echo

    echo "DNS:"
    grep nameserver /etc/resolv.conf
    echo

    pause
}
set_static_ip() {
    ...
}

set_dhcp() {
    ...
}

update_system() {

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

    pause
}

#########################################
# Initialization
#########################################

detect_os
detect_network_manager
detect_interface

#########################################
# Main Menu
#########################################

while true
do
    ...
done
