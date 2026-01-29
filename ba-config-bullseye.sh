#!/bin/bash
set -e

# ==========================================
# BLUEACOUSTIC INSTALLER (Debian Bullseye)
# ==========================================
# This script provisions a Raspberry Pi from scratch for Blueacoustic.
# Includes: Base system, UART, Docker, BS environment, Vim, GPSD and Dockerpipe IPC.

TARGET_USER="bs"
USER_HOME="/home/$TARGET_USER"
PIPE_DIR="/opt/cmdpipe"
PIPE_FILE="dockerpipe"
SERVICE_NAME="dockerpipe"
APP_DIR="$USER_HOME/blueacoustic"

# --------------------------------------------------
# Safety check: must be executed as root
# --------------------------------------------------
if [ "$EUID" -ne 0 ]; then
  echo "❌ Please run this script as root: sudo ./install-blueacoustic.sh"
  exit 1
fi

echo "🚀 Starting Blueacoustic installation on Debian Bullseye..."

# ==========================================
# 1. Base System Configuration
#    (Locales, Timezone, Updates)
# ==========================================
echo "--- 1. Configuring base system ---"

# Timezone and locale
timedatectl set-timezone America/Guayaquil
locale-gen en_US.UTF-8
localectl set-locale LANG=en_US.UTF-8

# System update
echo "Updating repositories and packages..."
apt update && apt upgrade -y

# Essential system packages
echo "Installing system dependencies..."
apt install -y \
    vim \
    git \
    curl \
    wget \
    cutecom \
    fail2ban \
    python3-pip \
    speedtest-cli \
    nmap \
    gnupg \
    gpsd \
    gpsd-clients \
    i2c-tools \
    libffi-dev \
    libssl-dev \
    python3-dev \
    build-essential

# ==========================================
# 2. Hardware Configuration (UART & GPSD)
# ==========================================
echo "--- 2. Configuring hardware (UART & GPS) ---"

# Enable UART in /boot/config.txt
if ! grep -q "enable_uart=1" /boot/config.txt; then
    echo "enable_uart=1" >> /boot/config.txt
    echo "UART enabled in config.txt"
else
    echo "UART was already enabled."
fi

# Disable serial console service
systemctl stop serial-getty@ttyS0.service || true
systemctl disable serial-getty@ttyS0.service || true

# Remove serial console from kernel cmdline
if grep -q "console=serial0,115200" /boot/cmdline.txt; then
    echo "Removing serial console from cmdline.txt..."
    sed -i 's/console=serial0,115200//g' /boot/cmdline.txt
    sed -i 's/  / /g' /boot/cmdline.txt
fi

# GPSD default configuration
# NOTE: Device is fixed to /dev/ttyS0 (UART)
echo "Configuring GPSD for /dev/ttyS0..."
cat <<EOF > /etc/default/gpsd
# Default settings for the gpsd init script and hotplug wrapper
START_DAEMON="true"
USBAUTO="true"
DEVICES="/dev/ttyS0"
GPSD_OPTIONS="-n"
EOF

# RTC configuration (DS3231)
echo "Configuring DS3231 RTC..."
if [ ! -d "/home/$TARGET_USER/config-rtc" ]; then
    sudo -u "$TARGET_USER" git clone https://github.com/Seeed-Studio/pi-hats.git "/home/$TARGET_USER/config-rtc"
fi
(
    cd "/home/$TARGET_USER/config-rtc/tools"
    ./install.sh -u rtc_ds3231
)

# ==========================================
# 3. Docker Installation
# ==========================================
echo "--- 3. Installing Docker ---"

if ! command -v docker &> /dev/null; then
    curl -sSL https://get.docker.com | sh
    usermod -aG docker "$TARGET_USER"
    echo "Docker installed and user $TARGET_USER added to docker group."
else
    echo "Docker is already installed."
fi

# ==========================================
# 4. User Environment Setup (Oh My Bash & Vim)
# ==========================================
echo "--- 4. Customizing environment for user: $TARGET_USER ---"

# Run this block as TARGET_USER to preserve permissions
sudo -u "$TARGET_USER" bash <<'EOF'
    # Oh My Bash installation
    if [ ! -d "$HOME/.oh-my-bash" ]; then
        echo "Installing Oh My Bash..."
        bash -c "$(curl -fsSL https://raw.githubusercontent.com/ohmybash/oh-my-bash/master/tools/install.sh)" --unattended
    fi

    # Ultimate Vim configuration
    if [ ! -d "$HOME/.vim_runtime" ]; then
        echo "Installing Ultimate Vim..."
        git clone --depth=1 https://github.com/amix/vimrc.git ~/.vim_runtime
        sh ~/.vim_runtime/install_awesome_vimrc.sh
    fi

    # Vim plugins
    echo "Installing Vim plugins..."
    mkdir -p ~/.vim_runtime/my_plugins

    PLUGINS=(
        "airblade/vim-gitgutter"
        "pangloss/vim-javascript"
        "tpope/vim-jdaddy"
        "scrooloose/nerdcommenter"
        "MTDL9/vim-log-highlighting"
    )

    for repo in "${PLUGINS[@]}"; do
        dirname=$(basename "$repo")
        if [ ! -d "$HOME/.vim_runtime/my_plugins/$dirname" ]; then
            git clone "https://github.com/$repo.git" "$HOME/.vim_runtime/my_plugins/$dirname"
        fi
    done

    # Custom Vim configuration
    curl -fsSLo ~/.vim_runtime/my_configs.vim \
    https://gist.githubusercontent.com/branny-dev/141770d40dd364403555e85304201ca7/raw/f53157986a9fa661dbaf66a79c2b786537f7b7c1/my_configs.vim
EOF

# ==========================================
# 5. Python Libraries
# ==========================================
echo "--- 5. Installing Python libraries ---"

# NOTE: Installed at system level, not virtualenv
pip3 install \
    digi-xbee \
    rich \
    schedule

# ==========================================
# 6. Dockerpipe IPC Configuration
# ==========================================
echo "--- 6. Configuring Dockerpipe service ---"

# 6.1 Create named pipe directory and FIFO
if [ ! -d "$PIPE_DIR" ]; then
    mkdir -p "$PIPE_DIR"
fi

if [ ! -p "$PIPE_DIR/$PIPE_FILE" ]; then
    mkfifo "$PIPE_DIR/$PIPE_FILE"
    chmod 666 "$PIPE_DIR/$PIPE_FILE"
    echo "Named pipe created at $PIPE_DIR/$PIPE_FILE"
else
    echo "Named pipe already exists."
fi

# 6.2 Application directory
if [ ! -d "$APP_DIR" ]; then
    mkdir -p "$APP_DIR"
    chown "$TARGET_USER:$TARGET_USER" "$APP_DIR"
    echo "Application directory created: $APP_DIR"
fi

# 6.3 dockerpipe.sh listener script
SCRIPT_PATH="$APP_DIR/dockerpipe.sh"
cat <<END_SCRIPT > "$SCRIPT_PATH"
#!/bin/bash

# Ensure logs directory exists
mkdir -p "\$(dirname "\$0")/logs"

while true; do
    parent_path=\$(cd "\$(dirname "\${BASH_SOURCE[0]}")" || exit ; pwd -P)
    timestamp=\$(date +"%Y-%m-%d %H:%M:%S")

    # Blocking read: waits until a command is written to the FIFO
    cmd=\$(cat $PIPE_DIR/$PIPE_FILE)

    echo "[\${timestamp}] - Command received" >> "\$parent_path/logs/commands.log"

    # Execute command and log stdout/stderr
    eval "\$cmd" >> "\$parent_path/logs/commands.log" 2>&1

    echo "[\${timestamp}] - Command finished" >> "\$parent_path/logs/commands.log"
done
END_SCRIPT

chmod +x "$SCRIPT_PATH"
chown "$TARGET_USER:$TARGET_USER" "$SCRIPT_PATH"

# 6.4 Systemd service
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
cat <<EOF > "$SERVICE_FILE"
[Unit]
Description=Dockerpipe Service for Blueacoustic
After=multi-user.target

[Service]
User=$TARGET_USER
Type=simple
Restart=always
RestartSec=10
WorkingDirectory=$APP_DIR
ExecStart=$SCRIPT_PATH

[Install]
WantedBy=multi-user.target
EOF

# Enable and start service
systemctl daemon-reload
systemctl enable "${SERVICE_NAME}.service"
systemctl restart "${SERVICE_NAME}.service"
echo "Dockerpipe service installed and running."

# ==========================================
# 7. Finalization
# ==========================================

echo ""
echo "✅ INSTALLATION COMPLETED SUCCESSFULLY"
echo "-----------------------------------------------------"
echo "Summary:"
echo " - Target user: $TARGET_USER"
echo " - Docker installed: Yes"
echo " - GPSD device: /dev/ttyS0"
echo " - Dockerpipe FIFO: $PIPE_DIR/$PIPE_FILE"
echo "-----------------------------------------------------"
echo "⚠️  WARNING: A reboot is required to apply UART and permission changes."
echo "Rebooting in 10 seconds... (Ctrl+C to cancel)"

sleep 10
reboot
