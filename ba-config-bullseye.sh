#!/bin/bash
set -e

# ==========================================
# BLUEACOUSTIC INSTALLER (Debian Bullseye)
# ==========================================
# This script provisions a Raspberry Pi from scratch for Blueacoustic.
# Includes: System, Advanced UART, Audio, Graphics, Docker, Vim (Inline Config), GPSD and Dockerpipe.

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
# ==========================================
echo "--- 1. Configuring base system ---"

# Timezone and locale
sudo locale-gen en_US.UTF-8
sudo localectl set-locale LANG=en_US.UTF-8

# System update
echo "Updating repositories and packages..."
apt update && apt upgrade -y

# Essential system packages
# Added: libegl1, libgles2, fail2ban
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
    build-essential \
    libegl1 \
    libgles2

# ==========================================
# 2. Hardware Configuration
#    (Audio, Graphics, UART, GPS)
# ==========================================
echo "--- 2. Configuring Hardware ---"

# 2.1 Audio Configuration
echo "Configuring Audio Defaults (Card 1)..."
cat <<EOF > /etc/asound.conf
defaults.pcm.card 1
defaults.ctl.card 1
EOF

# 2.2 Graphics Symlinks (Legacy BRCM support)
echo "Creating Graphics Symlinks..."
# Use -sf to force creation if they exist
ln -sf /usr/lib/arm-linux-gnueabihf/libEGL.so.1 /usr/lib/arm-linux-gnueabihf/libbrcmEGL.so
ln -sf /usr/lib/arm-linux-gnueabihf/libGLESv2.so.2 /usr/lib/arm-linux-gnueabihf/libbrcmGLESv2.so
ls -l /usr/lib/arm-linux-gnueabihf/libbrcm*

# 2.3 UART & Config.txt
echo "Configuring /boot/config.txt..."

# Basic Enable
if ! grep -q "enable_uart=1" /boot/config.txt; then
    echo "enable_uart=1" >> /boot/config.txt
fi

# Advanced UART Overlays
# We check if uart5 is already there to avoid duplicating the block on re-runs
if ! grep -q "dtoverlay=uart5" /boot/config.txt; then
    echo "Appending Advanced UART configurations..."
    cat <<EOF >> /boot/config.txt

# --- Blueacoustic UART Config ---
dtoverlay=uart0,txd0_pin=32,rxd0_pin=33,pin_func=7
dtoverlay=uart1,txd1_pin=14,rxd1_pin=15
dtoverlay=uart2,txd2_pin=0,rxd2_pin=1
dtoverlay=uart3,txd3_pin=4,rxd3_pin=5
dtoverlay=uart4,txd4_pin=8,rxd4_pin=9
dtoverlay=uart5,txd5_pin=12,rxd5_pin=13
# --------------------------------
EOF
else
    echo "Advanced UART config already present."
fi

# 2.4 Serial Console Cleanup
echo "Disabling serial console..."
systemctl stop serial-getty@ttyS0.service || true
systemctl disable serial-getty@ttyS0.service || true

if grep -q "console=serial0,115200" /boot/cmdline.txt; then
    sed -i 's/console=serial0,115200//g' /boot/cmdline.txt
    sed -i 's/  / /g' /boot/cmdline.txt
fi

# 2.5 GPSD Configuration
echo "Configuring GPSD for /dev/ttyS0..."
cat <<EOF > /etc/default/gpsd
# Default settings for the gpsd init script and hotplug wrapper
START_DAEMON="true"
USBAUTO="true"
DEVICES="/dev/ttyS0"
GPSD_OPTIONS="-n"
EOF

# 2.6 RTC Configuration (DS3231)
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
# 4. User Environment Setup
# ==========================================
echo "--- 4. Customizing environment for user: $TARGET_USER ---"

sudo -u "$TARGET_USER" bash <<'EOF'
    # Oh My Bash
    if [ ! -d "$HOME/.oh-my-bash" ]; then
        echo "Installing Oh My Bash..."
        bash -c "$(curl -fsSL https://raw.githubusercontent.com/ohmybash/oh-my-bash/master/tools/install.sh)" --unattended
    fi

    # Ultimate Vim
    if [ ! -d "$HOME/.vim_runtime" ]; then
        echo "Installing Ultimate Vim..."
        git clone --depth=1 https://github.com/amix/vimrc.git ~/.vim_runtime
        sh ~/.vim_runtime/install_awesome_vimrc.sh
    fi

    # Vim Plugins
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
EOF

# --- INJECTING CUSTOM VIM CONFIG (No External Link) ---
echo "Applying custom Vim configuration..."
VIM_CONFIG_FILE="$USER_HOME/.vim_runtime/my_configs.vim"

cat <<VIMCONF > "$VIM_CONFIG_FILE"
" vim ~/.vim_runtime/my_configs.vim

" Custom Theme peaksea | ir_black | pyte | solarized
colorscheme pyte

" Set number line
set nu

" 1 tab == 2 spaces
set shiftwidth=2
set tabstop=2

" Git Grutter
let g:gitgutter_enabled = 1

" Set updatetime (for GitGutter git diff)
set updatetime=100

" indentLine
let g:indentLine_char = '▏'
let g:indentLine_color_term = 235

" Fold level
set foldlevel=99

" Nerdtree hidden
let NERDTreeShowHidden=1
VIMCONF

# Ensure correct ownership for the Vim config file
chown "$TARGET_USER:$TARGET_USER" "$VIM_CONFIG_FILE"


# ==========================================
# 5. Python Libraries
# ==========================================
echo "--- 5. Installing Python libraries ---"
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

    # Blocking wait
    cmd=\$(cat $PIPE_DIR/$PIPE_FILE)

    # Calculate timestamp AFTER receiving command
    timestamp=\$(date +"%Y-%m-%d %H:%M:%S")

    # Log command received
    echo "[\${timestamp}] - Command executed: \${cmd}" >> "\$parent_path/logs/system/commands.log"

    # Execute if not empty
    if [ -n "\${cmd}" ]; then
        eval "\${cmd}" >> "\$parent_path/logs/system/commands.log" 2>&1
    fi

    echo "[\${timestamp}] - Command finished" >> "\$parent_path/logs/system/commands.log"
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
echo " - User: $TARGET_USER"
echo " - Docker: Installed"
echo " - Audio: Default Card 1"
echo " - Graphics: libbrcm links created"
echo " - UART: Advanced overlays applied"
echo " - GPSD: /dev/ttyS0"
echo " - Vim: Custom config applied"
echo " - Dockerpipe: Active"
echo "-----------------------------------------------------"
echo "⚠️  WARNING: A reboot is required to apply UART and permission changes."
echo "Rebooting in 10 seconds... (Ctrl+C to cancel)"

sleep 10
reboot
