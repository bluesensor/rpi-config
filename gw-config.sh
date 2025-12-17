#!/bin/bash
set -euo pipefail

echo "Starting system configuration..."

# -------------------------
# System update
# -------------------------
echo "Updating system packages..."
sudo apt update && sudo apt upgrade -y

# -------------------------
# UART configuration
# -------------------------
echo "Configuring UART..."
if ! grep -q "enable_uart=1" /boot/config.txt; then
    echo "enable_uart=1" | sudo tee -a /boot/config.txt
else
    echo "UART already enabled"
fi

sudo systemctl stop serial-getty@ttyS0.service || true
sudo systemctl disable serial-getty@ttyS0.service || true

if grep -q "console=serial0,115200" /boot/cmdline.txt; then
    echo "Removing serial console..."
    sudo sed -i 's/console=serial0,115200//g' /boot/cmdline.txt
    sudo sed -i 's/  / /g' /boot/cmdline.txt
fi

# -------------------------
# Essential packages (Trixie)
# -------------------------
echo "Installing essential packages..."
sudo apt install -y \
    vim \
    cutecom \
    fail2ban \
    python3-pip \
    speedtest-cli \
    nmap \
    gpsd-clients

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
# Timezone
# -------------------------
echo "Setting timezone..."
sudo timedatectl set-timezone America/Guayaquil

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
# Docker
# -------------------------
echo "Installing Docker..."
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker "$USER"

# -------------------------
# Python libraries
# -------------------------
echo "Installing Python libraries..."
pip3 install --break-system-packages \
    digi-xbee \
    rich \
    schedule

# -------------------------
# Network test
# -------------------------
echo "Running speedtest..."
speedtest || echo "Speedtest finished with warnings"

# -------------------------
# Finish
# -------------------------
echo "Applying environment changes..."
source ~/.bashrc

echo "Configuration completed successfully."
echo "Rebooting in 10 seconds (Ctrl+C to cancel)..."
sleep 10
sudo reboot
