#!/bin/bash

err="\033[1;31m[!]\033[m"
msg="\033[1;32m[+]\033[m"
info="\033[0;36m[:]\033[m"
ask="\033[0;35m[?]\033[m"

# Function to check the Linux distribution
detect_distro() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        case "$ID" in
            debian|ubuntu)
                DISTRO="debian"
                ;;
            fedora)
                DISTRO="fedora"
                ;;
            arch)
                DISTRO="arch"
                ;;
            *)
                echo -e "${err} Unsupported distribution: $ID"
                exit 1
                ;;
        esac
    else
        echo -e "${err} Cannot detect the distribution."
        exit 1
    fi
}

# Check if Docker is installed
is_docker_installed() {
    if command -v docker &>/dev/null; then
        return 0
    else
        return 1
    fi
}

# Ensure the script is run as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${err} This script must be run as root."
        exit 1
    fi
}

# Remove old and incompatible packages
remove_old_packages() {
    echo -e "${info} Removing old and incompatible packages..."
    case "$DISTRO" in
        debian)
            for pkg in docker.io docker-doc docker-compose podman-docker containerd runc; do
                apt-get remove -y $pkg >/dev/null
            done
            ;;
        fedora)
            for pkg in docker docker-client docker-client-latest docker-common docker-latest docker-latest-logrotate docker-logrotate docker-selinux docker-engine-selinux docker-engine; do
                dnf remove -y $pkg >/dev/null
            done
            ;;
        arch)
            for pkg in docker docker-compose containerd runc; do
                pacman -Rns --noconfirm $pkg >/dev/null
            done
            ;;
    esac
}

# Install dependencies
install_dependencies() {
    echo -e "${info} Installing dependencies..."
    case "$DISTRO" in
        debian)
            apt-get update >/dev/null
            apt-get install -y ca-certificates curl gnupg lsb-release >/dev/null
            ;;
        fedora)
            dnf install -y dnf-plugins-core >/dev/null
            ;;
        arch)
            pacman -Sy --noconfirm ca-certificates curl gnupg lsb-release >/dev/null
            ;;
    esac
}

# Add Docker GPG key and repository
setup_docker_repo() {
    case "$DISTRO" in
        debian)
            install -m 0755 -d /etc/apt/keyrings
            if curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor --yes -o /etc/apt/keyrings/docker.gpg; then
                chmod a+r /etc/apt/keyrings/docker.gpg
                echo -e "${msg} Added Docker's GPG key"
            else
                echo -e "${err} Failed to add Docker's GPG key"
                exit 1
            fi

            if echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null; then
                echo -e "${msg} Added Docker's stable repository"
            else
                echo -e "${err} Failed to add Docker's stable repository"
                exit 1
            fi

            apt-get update >/dev/null
            ;;
        fedora)
            if dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo; then
                echo -e "${msg} Added Docker's repository"
            else
                echo -e "${err} Failed to add Docker's repository"
                exit 1
            fi

            dnf makecache >/dev/null
            ;;
        arch)
            pacman -Sy --noconfirm >/dev/null
            ;;
    esac
}

# Install Docker
install_docker() {
    echo -e "${info} Installing Docker and Docker compose (this might take a while)..."
    case "$DISTRO" in
        debian)
            if apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin >/dev/null; then
                echo -e "${msg} Docker successfully installed: \033[0;32m$(docker --version)\033[m"
            else
                echo -e "${err} Docker installation failed"
                exit 1
            fi
            ;;
        fedora)
            if dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin >/dev/null; then
                echo -e "${msg} Docker successfully installed: \033[0;32m$(docker --version)\033[m"
            else
                echo -e "${err} Docker installation failed"
                exit 1
            fi
            ;;
        arch)
            if pacman -S --noconfirm docker docker-compose containerd runc; then
                echo -e "${msg} Docker successfully installed: \033[0;32m$(docker --version)\033[m"
            else
                echo -e "${err} Docker installation failed"
                exit 1
            fi
            ;;
    esac
}

# Create Docker user
create_docker_user() {
    while true; do
        echo -e -n "${ask} "
        read -p "Do you want to create a Docker user? [y/n] " yn </dev/tty
        case $yn in
            [Yy] )
                while true; do
                    echo -e -n "${ask} "
                    read -p "Please choose an ID for the new user/group: " id </dev/tty
                    if id $id &>/dev/null; then
                        echo -e "${err} A user with the same ID already exists: \033[0;36m$(id $id)\033[m"
                    else
                        if /usr/sbin/groupadd -g $id dockeruser && /usr/sbin/useradd dockeruser -u $id -g $id -m -s /bin/bash; then
                            echo -e "${msg} Docker user created: \033[0;32m$(id dockeruser)\033[m"
                            break
                        else
                            echo -e "${err} Failed to create Docker user"
                            exit 1
                        fi
                    fi
                done
                break
                ;;
            [Nn] ) break ;;
            * ) echo "Please answer yes [y] or no [n].";;
        esac
    done
}

# Enable Docker service at startup
enable_docker_service() {
    echo -e "${info} Starting Docker services..."
    if systemctl enable --now docker.service containerd.service >/dev/null; then
        echo -e "${msg} Docker services started and enabled."
    else
        echo -e "${err} Could not start Docker services. Try running \033[0;36msystemctl enable --now docker.service containerd.service\033[m again in a few minutes."
    fi
}

main() {
    check_root
    detect_distro

    if is_docker_installed; then
        while true; do
            echo -e "${err} Docker is already installed."
            read -p "Do you still want to run the script? [y/n] " yn </dev/tty
            case $yn in
                [Yy] ) break;;
                [Nn] ) exit 1;;
                * ) echo "Please answer yes [y] or no [n].";;
            esac
        done
    fi

    remove_old_packages
    install_dependencies
    setup_docker_repo
    install_docker
    create_docker_user
    enable_docker_service

    echo -e "${info} Process completed. Run '\033[0;36msystemctl status docker\033[m' to check Docker's status."
}

main "$@"
