#!/bin/bash
set -euo pipefail

echo "Starting system configuration..."

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

# Instalación de paquetes esenciales
echo "Installing essential packages..."
sudo apt install -y vim cutecom fail2ban python3-pip speedtest-cli nmap

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

# Configuración de Vim
echo "Setting up Vim environment..."
if [ ! -d ~/.vim_runtime ]; then
    git clone --depth=1 https://github.com/amix/vimrc.git ~/.vim_runtime
    bash ~/.vim_runtime/install_awesome_vimrc.sh
else
    echo "Vim configuration already exists"
fi

# Plugins de Vim
echo "Installing Vim plugins..."
PLUGINS=(
    "airblade/vim-gitgutter"
    "pangloss/vim-javascript"
    "tpope/vim-jdaddy"
    "scrooloose/nerdcommenter"
    "MTDL9/vim-log-highlighting"
)

for plugin in "${PLUGINS[@]}"; do
    dir_name=$(basename "$plugin")
    if [ ! -d "~/.vim_runtime/my_plugins/$dir_name" ]; then
        git clone --depth=1 "https://github.com/$plugin.git" "~/.vim_runtime/my_plugins/$dir_name"
    fi
done

# Configuración personalizada de Vim
echo "Applying custom Vim configuration..."
curl -fsSLo ~/.vim_runtime/my_configs.vim https://gist.githubusercontent.com/branny-dev/141770d40dd364403555e85304201ca7/raw/f53157986a9fa661dbaf66a79c2b786537f7b7c1/my_configs.vim

# Configuración de zona horaria
echo "Setting timezone to America/Guayaquil..."
sudo timedatectl set-timezone America/Guayaquil

# Configuración de RTC (DS3231)
echo "Configuring RTC module..."
if [ ! -d "config-rtc" ]; then
    git clone https://github.com/Seeed-Studio/pi-hats.git config-rtc
fi

(
    cd config-rtc/tools || { echo "Failed to enter RTC tools directory"; exit 1; }
    sudo ./install.sh -u rtc_ds3231
)
echo "Checking I2C devices (look for 68 for RTC):"
sudo i2cdetect -y 1

# Instalación de Docker
echo "Installing Docker..."
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker "$USER"

# Instalación de dependencias Python
echo "Installing Python libraries..."
PYTHON_PKGS=(
    digi-xbee
    rich
    schedule
)
for pkg in "${PYTHON_PKGS[@]}"; do
    sudo pip3 install "$pkg"
done

# Test de velocidad de red
echo "Running network speed test..."
if command -v speedtest &>/dev/null; then
    speedtest || echo "Speedtest completed with warnings (check connection)"
else
    echo "Speedtest CLI not installed. Installing now..."
    sudo apt install -y speedtest-cli && speedtest
fi

# Instalación de NVM (Node Version Manager)
echo "Installing NVM (Node Version Manager)..."
if ! command -v nvm &>/dev/null; then
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
    [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion
    echo "NVM installed successfully."
else
    echo "NVM is already installed. Skipping..."
fi

# Cargar NVM manualmente en caso de que no esté disponible
if ! command -v nvm &>/dev/null; then
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
    [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion
fi

# Instalación de Node.js usando NVM
echo "Installing Node.js version 14.15.5 using NVM..."
nvm install 14.15.5
nvm use 14.15.5
echo "Node.js version $(node --version) installed and activated."

# Instalación de PM2
echo "Installing PM2 globally..."
npm install pm2 -g
echo "PM2 installed successfully."

# Configuración de PM2 Logrotate
echo "Installing PM2 Logrotate module..."
pm2 install pm2-logrotate
echo "PM2 Logrotate module installed successfully."

# Aplicar configuraciones
echo "Applying environment changes..."
source ~/.bashrc

echo "Configuration completed successfully."
echo "A system reboot is required to apply UART changes and other configurations."
echo "Rebooting in 10 seconds... (press Ctrl+C to cancel)"
sleep 10
sudo reboot
