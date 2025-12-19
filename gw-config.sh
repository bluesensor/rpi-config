#!/bin/bash
set -euo pipefail

echo "Starting system configuration..."

# -------------------------
# Locales fix (Evita errores de Perl)
# -------------------------
echo "Configuring locales..."
sudo locale-gen es_EC.UTF-8 || true
sudo localectl set-locale LANG=es_EC.UTF-8 || true

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
    gpsd-clients \
    curl \
    gnupg


# Verificar la versión de Nmap
echo "Checking Nmap version..."
nmap --version

# Instalación de Oh My Bash (mejorada)
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
# Docker (Fix para Trixie 32-bit)
# -------------------------
echo "Installing Docker..."
# Trixie 32-bit no tiene repo oficial aún, usamos el de Bookworm
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/raspbian/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg --yes
sudo chmod a+r /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/raspbian bookworm stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo usermod -aG docker "$USER"

# -------------------------
# Python libraries
# -------------------------
echo "Installing Python libraries..."
pip3 install --break-system-packages \
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
source ~/.bashrc

echo "Configuration completed successfully."
echo "A system reboot is required to apply UART changes and other configurations."
echo "Rebooting in 10 seconds... (press Ctrl+C to cancel)"
sleep 10
sudo reboot
