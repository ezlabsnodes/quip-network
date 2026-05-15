#!/bin/bash
set -euo pipefail

echo "=========================================="
echo " Quip Network Node Auto Setup"
echo "=========================================="

# 1. User Inputs
read -p "Enter node_name (Example: Nodename - 0xethereum): " NODE_NAME
read -p "Enter secret (Press Enter for fresh setup/auto-generate): " SECRET

# Generate secret if left blank
if [ -z "$SECRET" ]; then
    SECRET=$(openssl rand -hex 32)
    echo -e "\n[INFO] Secret is blank, auto-generated: $SECRET"
fi

# Fallback if node_name is left blank
if [ -z "$NODE_NAME" ]; then
    NODE_NAME="my-cpu-node-$(openssl rand -hex 4)"
    echo -e "[INFO] Node name is blank, using default: $NODE_NAME"
fi

# Auto-detect Public IPv4 strictly
PUBLIC_IP=$(curl -4 -s ifconfig.me || curl -s https://api4.ipify.org || curl -4 -s icanhazip.com)

if [ -z "$PUBLIC_IP" ]; then
    echo -e "\033[1;31m[ERROR] Failed to detect IPv4 address. Make sure this VPS has a public IPv4.\033[0m" >&2
    exit 1
fi

echo -e "[INFO] Detected Public IPv4: $PUBLIC_IP"
echo "=========================================="

# ==========================================
# 2. Setup Dependency (Optimized with Smart Fallback)
# ==========================================
USERNAME=$(whoami)
ARCH=$(uname -m)
DOCKER_COMPOSE_VERSION="v2.26.1"

function info() { echo -e "\033[1;32m[INFO] $1\033[0m"; }
function warn() { echo -e "\033[1;33m[WARN] $1\033[0m"; }
function error() { echo -e "\033[1;31m[ERROR] $1\033[0m" >&2; exit 1; }

# Smart install function: mencoba install cepat, jika gagal (404) baru update
function install_packages() {
    info "Installing packages..."
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "$@" || {
        warn "Initial installation failed (likely stale cache). Running a quick update and retrying..."
        sudo apt-get update -qq
        sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --fix-missing "$@" || {
            error "Failed to install packages even after update."
        }
    }
}

function command_exists() { command -v "$1" &> /dev/null; }

info "Checking system architecture..."
if [ "$ARCH" != "x86_64" ]; then
    warn "Non-x86_64 architecture detected ($ARCH), some packages might need adjustment"
fi

# Install essential build tools tanpa memaksakan full apt upgrade di awal
install_packages \
    git clang cmake build-essential openssl pkg-config libssl-dev \
    openssh-server sed nano automake autoconf nvme-cli libgbm-dev libleveldb-dev bsdmainutils  \
    ca-certificates curl gnupg lsb-release software-properties-common

# Docker Installation
info "Checking Docker installation..."
if ! command_exists docker; then
    info "Installing Docker..."
    sudo install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    sudo chmod a+r /etc/apt/keyrings/docker.gpg

    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

    sudo apt-get update -qq
    install_packages docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    
    sudo usermod -aG docker $USERNAME
    info "Docker installed."
else
    info "Docker already installed: $(docker --version)"
fi

# Docker Compose Installation
info "Checking Docker Compose installation..."
if ! command_exists docker-compose; then
    info "Installing Docker Compose standalone..."
    sudo curl -L "https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" \
        -o /usr/local/bin/docker-compose
    sudo chmod +x /usr/local/bin/docker-compose
    info "Docker Compose installed."
else
    info "Docker Compose already installed."
fi

# ==========================================
# 3. Setup Node Quip Network
# ==========================================
info "Cloning Quip Network Repository..."
rm -rf nodes.quip.network
git clone https://ezlabsnodes:glpat-Nqj_oP7YoPxzHs4MoKAi4GM6MQpvOjEKdTptcGgydg8.01.171xfc3oo@gitlab.com/quip.network/nodes.quip.network.git

cd nodes.quip.network

info "Configuring data/config.toml..."
cp data/config.cpu.toml data/config.toml

# Replace config values
sed -i "s/node_name = \"my-cpu-node\"/node_name = \"$NODE_NAME\"/g" data/config.toml
sed -i "s/secret = \"CHANGE_ME\"/secret = \"$SECRET\"/g" data/config.toml
sed -i "s/# auto_mine = false/auto_mine = true/g" data/config.toml

# Add public_host below port = 20049 using the strictly grabbed IPv4
sed -i "/port = 20049/a public_host = \"$PUBLIC_IP\"" data/config.toml

info "Setting up .env file..."
cp env.example .env

# ==========================================
# 4. Start Node
# ==========================================
info "Starting Docker Compose (CPU Profile)..."
docker compose --profile cpu up -d

echo "=========================================="
echo " Setup Complete! Node is running."
echo " Node Name   : $NODE_NAME"
echo " Public IPv4 : $PUBLIC_IP"
echo " Secret      : $SECRET"
echo "=========================================="
