#!/bin/bash

err="\033[1;31m[!]\033[m"
msg="\033[1;32m[+]\033[m"
info="\033[0;36m[:]\033[m"
ask="\033[0;35m[?]\033[m"

# Check if the machine is running a Debian-based system
is_debian() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        if [[ "$ID" == "debian" || "$ID_LIKE" =~ "debian" ]]; then
            return 0
        fi
    fi
    return 1
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
    for pkg in docker.io docker-doc docker-compose podman-docker containerd runc; do
        apt-get remove -y $pkg >/dev/null
    done
}

# Install dependencies
install_dependencies() {
    echo -e "${info} Updating repositories..."
    apt-get update >/dev/null
    echo -e "${info} Installing dependencies..."
    apt-get install -y ca-certificates curl gnupg >/dev/null
}

# Add Docker GPG key
add_gpg_key() {
    install -m 0755 -d /etc/apt/keyrings
    if curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor --yes -o /etc/apt/keyrings/docker.gpg; then
        chmod a+r /etc/apt/keyrings/docker.gpg
        echo -e "${msg} Added Docker's GPG key"
    else
        echo -e "${err} Failed to add Docker's GPG key"
        exit 1
    fi
}

# Add Docker repository
add_repository() {
    if echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null; then
        echo -e "${msg} Added Docker's stable repository"
    else
        echo -e "${err} Failed to add Docker's stable repository"
        exit 1
    fi
}

# Install Docker
install_docker() {
    echo -e "${info} Updating repositories..."
    apt-get update >/dev/null
    echo -e "${info} Installing Docker and Docker compose (this might take a while)..."
    if apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin >/dev/null; then
        echo -e "${msg} Docker successfully installed: \033[0;32m$(docker --version)\033[m"
    else
        echo -e "${err} Docker installation failed"
        exit 1
    fi
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

    if ! is_debian; then
        echo -e "${err} This script only works on Debian machines, sorry!"
        exit 1
    fi

    remove_old_packages
    install_dependencies
    add_gpg_key
    add_repository
    install_docker
    create_docker_user
    enable_docker_service

    echo -e "${info} Process completed. Run '\033[0;36msystemctl status docker\033[m' to check Docker's status."
}

main "$@"
