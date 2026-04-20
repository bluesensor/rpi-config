#!/bin/bash
set -euo pipefail

echo "Starting system configuration..."

echo "Configuring locales to English (US)..."
sudo locale-gen en_US.UTF-8 || true
sudo localectl set-locale LANG=en_US.UTF-8 || true

# Actualización del sistema
echo "Updating system packages..."
sudo apt update && sudo apt upgrade -y

# Configuración de UART
echo "Configuring UART..."
if ! grep -q "enable_uart=1" /boot/config.txt; then
    echo "enable_uart=1" | sudo tee -a /boot/config.txt
else
    echo "UART already enabled in config.txt"
fi

sudo systemctl stop serial-getty@ttyS0.service || true
sudo systemctl disable serial-getty@ttyS0.service || true

# Eliminar console=serial0,115200 de cmdline.txt
if grep -q "console=serial0,115200" /boot/cmdline.txt; then
    echo "Removing serial console from cmdline.txt..."
    sudo sed -i 's/console=serial0,115200//g' /boot/cmdline.txt
    sudo sed -i 's/  / /g' /boot/cmdline.txt  # Eliminar espacios duplicados
fi

# -------------------------
# Essential packages
# -------------------------
echo "Installing essential packages..."
sudo apt install -y \
    vim \
    cutecom \
    fail2ban \
    python3-pip \
    speedtest-cli \
    nmap \
    gpsd-clients \
    curl \
    gnupg

# Verificar la versión de Nmap
echo "Checking Nmap version..."
nmap --version

# Instalación de Oh My Bash
echo "Checking Oh My Bash installation..."
if [ ! -d ~/.oh-my-bash ]; then
    echo "Installing Oh My Bash..."
    bash -c "$(curl -fsSL https://raw.githubusercontent.com/ohmybash/oh-my-bash/master/tools/install.sh)" || {
        echo "Oh My Bash installation failed"
        exit 1
    }
else
    echo "Oh My Bash already installed. Skipping..."
fi

# -------------------------
# Vim + Ultimate Vim
# -------------------------
echo "Setting up Vim..."

if [ ! -d "$HOME/.vim_runtime" ]; then
    echo "Installing Ultimate Vim..."
    git clone --depth=1 https://github.com/amix/vimrc.git ~/.vim_runtime
    sh ~/.vim_runtime/install_awesome_vimrc.sh
else
    echo "Ultimate Vim already installed"
fi

# -------------------------
# Vim Plugins
# -------------------------
echo "Installing Vim plugins..."

VIM_PLUGINS=(
    "airblade/vim-gitgutter vim-gitgutter"
    "pangloss/vim-javascript vim-javascript"
    "tpope/vim-jdaddy vim-jdaddy"
    "scrooloose/nerdcommenter nerdcommenter"
    "MTDL9/vim-log-highlighting vim-log-highlighting"
)

for plugin in "${VIM_PLUGINS[@]}"; do
    repo=$(echo $plugin | awk '{print $1}')
    dir=$(echo $plugin | awk '{print $2}')

    if [ ! -d "$HOME/.vim_runtime/my_plugins/$dir" ]; then
        git clone https://github.com/$repo.git "$HOME/.vim_runtime/my_plugins/$dir"
    else
        echo "Plugin $dir already installed"
    fi
done

# Custom Vim config
echo "Applying custom Vim config..."
curl -fsSLo ~/.vim_runtime/my_configs.vim \
https://gist.githubusercontent.com/branny-dev/141770d40dd364403555e85304201ca7/raw/f53157986a9fa661dbaf66a79c2b786537f7b7c1/my_configs.vim


# -------------------------
# RTC DS3231
# -------------------------
echo "Configuring RTC..."
if [ ! -d "config-rtc" ]; then
    git clone https://github.com/Seeed-Studio/pi-hats.git config-rtc
fi

(
    cd config-rtc/tools
    sudo ./install.sh -u rtc_ds3231
)

sudo i2cdetect -y 1 || true

# -------------------------
# Docker (Fix para Buster 32-bit - EOL, usamos script de conveniencia)
# -------------------------
# Raspbian Buster alcanzó EOL en junio 2024 y Docker dejó de publicar
# paquetes en download.docker.com/linux/raspbian/dists/buster.
# Usamos get.docker.com que es la vía oficial recomendada por Docker
# para distros EOL. Detecta automáticamente arquitectura (armv7/armv6)
# y hace best-effort para Buster.
echo "Installing Docker..."
if ! command -v docker &>/dev/null; then
    echo "Docker not found. Installing via get.docker.com..."
    curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
    sudo sh /tmp/get-docker.sh
    rm -f /tmp/get-docker.sh

    # Agregar usuario al grupo docker (toma efecto tras re-login)
    sudo usermod -aG docker "$USER"

    # Habilitar e iniciar el servicio (crítico en gateway desatendido)
    sudo systemctl enable docker
    sudo systemctl start docker
else
    echo "Docker already installed: $(docker --version)"
fi

# Fix para iptables en Buster (conflicto nftables vs legacy)
if command -v update-alternatives &>/dev/null; then
    sudo update-alternatives --set iptables /usr/sbin/iptables-legacy 2>/dev/null || true
fi

# Verify
docker --version || echo "WARNING: Docker install may have failed"
docker compose version || echo "WARNING: docker compose plugin missing"


# -------------------------
# Python libraries
# -------------------------
echo "Installing Python libraries..."
pip3 install \
    digi-xbee \
    rich \
    schedule

# Test de velocidad de red
echo "Running network speed test..."
if command -v speedtest &>/dev/null; then
    speedtest || echo "Speedtest completed with warnings (check connection)"
else
    echo "Speedtest CLI not installed. Installing now..."
    sudo apt install -y speedtest-cli && speedtest
fi

# Aplicar configuraciones
echo "Applying environment changes..."
source ~/.bashrc || true

echo "Configuration completed successfully."
echo "NOTE: You must log out and back in for docker group membership to take effect."
echo "A system reboot is required to apply UART changes and other configurations."
echo "Rebooting in 10 seconds... (press Ctrl+C to cancel)"
sleep 10
sudo reboot
