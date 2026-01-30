#!/bin/bash

# ==============================================================================
# BLUEACOUSTIC INSTALLER - SAFE MODE (IDEMPOTENT)
# ==============================================================================
# This script is IDEMPOTENT: It can be executed multiple times without the risk
# of losing configuration data (storage.json) or creating duplicate Cron tasks.
# ==============================================================================

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}🚀 Starting BlueAcoustic Safe Installation...${NC}"

# ---------------------------------------------------------
# 1. Directory Configuration
# ---------------------------------------------------------
BASE_DIR="/home/bs/blueacoustic"
LOG_DIR="$BASE_DIR/logs/system"

echo -e "${GREEN}📂 Verifying directories...${NC}"
mkdir -p "$LOG_DIR"

echo -e "${GREEN}🔧 Configuring System Pipe at /opt/cmdpipe...${NC}"
# Pipe Configuration
if [ ! -d "/opt/cmdpipe" ]; then
    echo "   -> Creating /opt/cmdpipe directory"
    sudo mkdir -p /opt/cmdpipe
    sudo chmod 777 /opt/cmdpipe
fi

if [ ! -p "/opt/cmdpipe/dockerpipe" ]; then
    echo "   -> Creating named pipe (FIFO) dockerpipe"
    sudo mkfifo /opt/cmdpipe/dockerpipe
    sudo chmod 666 /opt/cmdpipe/dockerpipe
fi

# ---------------------------------------------------------
# 2. Configure UDEV Rules (Always safe to re-run)
# ---------------------------------------------------------
# It is always safe to overwrite these to ensure hardware is detected correctly
echo -e "${GREEN}🔌 Updating USB/Serial rules (udev)...${NC}"
cat <<EOF | sudo tee /etc/udev/rules.d/10-usb-serial.rules > /dev/null
SUBSYSTEM=="tty", ATTRS{idVendor}=="0403", ATTRS{idProduct}=="6001", GROUP="dialout", SYMLINK+="baXB0"
SUBSYSTEM=="tty", ATTRS{idVendor}=="1a86", ATTRS{idProduct}=="55d3", GROUP="dialout", SYMLINK+="baENE0"
KERNEL=="ttyAMA0", MODE="0666",  GROUP="dialout", SYMLINK+="baMIC0"
EOF

echo -e "${GREEN}🔄 Reloading udev rules...${NC}"
sudo udevadm control --reload-rules
sudo udevadm trigger

# Navigate to project dir
cd "$BASE_DIR" || { echo "❌ Error: Could not enter $BASE_DIR"; exit 1; }

# ---------------------------------------------------------
# 3. Generate storage.json (PROTECTED)
# ---------------------------------------------------------
# CRITICAL: We check if the file exists. If it does, we DO NOT touch it.
if [ -f "storage.json" ]; then
    echo -e "${YELLOW}🛡️  storage.json detected. SKIPPING overwrite to preserve your data.${NC}"
else
    echo -e "${GREEN}📝 Creating default storage.json...${NC}"
    cat <<EOF > storage.json
{
    "gateway_address_64": null,
    "latest_click_timestamp": null,
    "latest_click_latitude": "nil",
    "latest_click_longitude": "nil",
    "latest_click_hdop": "nil",
    "latest_click_count": "nil",
    "click_counting": true,
    "click_counting_frequency": 1,
    "click_counting_delay": 35,
    "click_mode": 0,
    "hours": "0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0",
    "communication_method": "PUSH",
    "audio_length": 2000,
    "audio_chunk_length": 500,
    "noise_gate_threshold": -45.0,
    "noise_gate_reduction_level": -40.0,
    "noise_gate_attack_time": 0.0005,
    "noise_gate_decay_time": 0.01,
    "high_pass_frequency": 2600
}
EOF
    chmod 666 storage.json
fi

# ---------------------------------------------------------
# 4. INFRASTRUCTURE (DOCKER-COMPOSE)
# ---------------------------------------------------------
# This file is always updated to ensure the container structure matches the latest version
echo -e "${GREEN}📝 Updating docker-compose.yml...${NC}"
cat <<EOF > docker-compose.yml
version: "3.3"

services:
  blueacoustic:
    container_name: blueacoustic
    image: dmaroto213/blueacoustic:latest
    restart: always
    network_mode: "host"

    devices:
      - /dev/input
      - /dev/snd
      - /dev/snd:/dev/snd
      - /dev/baXB0
      - /dev/baENE0
      - /dev/ttyAMA3

    environment:
      - PULSE_SERVER=unix:/run/user/1000/pulse/native
      - XBEE_DEVICE=/dev/baXB0
      - XBEE_BAUD_RATE=9600
      - EPEVER_DEVICE=/dev/baENE0
      - AUDIO_DEVICE_NAME=AMS-22
      - AUDIO_FALLBACK_INDEX=0
      - LOG_LEVEL=INFO

    volumes:
      - /opt/cmdpipe:/hostpipe
      - /home/bs/blueacoustic/logs:/blueacoustic/logs
      - /home/bs/blueacoustic/storage.json:/blueacoustic/storage.json
      - /boot/config.txt:/host/boot/config.txt
      - /run/user/1000/pulse/native:/run/user/1000/pulse/native
      - /home/bs/.config/pulse/:/root/.config/pulse/
      - /etc/timezone:/etc/timezone:ro
      - /etc/localtime:/etc/localtime:ro
EOF

# ---------------------------------------------------------
# 5. Generate dockerpipe.sh
# ---------------------------------------------------------
echo -e "${GREEN}📝 Updating system scripts (Hostpipe & Auto-Updater)...${NC}"

# Dockerpipe Listener (Hostpipe)
cat <<'EOF' > dockerpipe.sh
#!/bin/bash
mkdir -p "$(dirname "$0")/logs/system"
parent_path=$(cd "$(dirname "${BASH_SOURCE[0]}")" || exit ; pwd -P)

while true; do
    cmd=$(cat /opt/cmdpipe/dockerpipe)
    timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    echo "[$timestamp] - Command executed: $cmd" >> "$parent_path/logs/system/commands.log"
    if [ -n "$cmd" ]; then
        eval "$cmd" >> "$parent_path/logs/system/commands.log" 2>&1
    fi
    echo "[$timestamp] - Command finished" >> "$parent_path/logs/system/commands.log"
done
EOF
chmod +x dockerpipe.sh

# ---------------------------------------------------------
# 6. Generate update_safe.sh
# ---------------------------------------------------------
echo -e "${GREEN}📝 Updating update_safe.sh...${NC}"
cat <<'EOF' > update_safe.sh
#!/bin/bash
LOG_FILE="/home/bs/blueacoustic/logs/system/update_process.log"
LOCK_FILE="/tmp/ba_update.lock"
DAILY_FLAG="/tmp/ba_updated_session"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"; }

if [ -f "$LOCK_FILE" ]; then exit 0; fi
touch "$LOCK_FILE"

# Ping Check (Google DNS)
if ! ping -c 3 -W 5 8.8.8.8 &> /dev/null; then
    rm -f "$LOCK_FILE"
    exit 0
fi

# Session Check (Avoid update loops during a single internet session)
if [ -f "$DAILY_FLAG" ]; then
    rm -f "$LOCK_FILE"
    exit 0
fi

log "🌐 Internet detected. Starting Watchtower update..."

/usr/bin/docker run --rm \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v /home/bs/.docker/config.json:/config.json \
    containrrr/watchtower \
    --run-once \
    --cleanup \
    blueacoustic >> "$LOG_FILE" 2>&1

if [ $? -eq 0 ]; then
    log "✅ Update process finished."
    touch "$DAILY_FLAG"
else
    log "🔥 Update failed."
fi

rm -f "$LOCK_FILE"
EOF
chmod +x update_safe.sh

# ---------------------------------------------------------
# 7. Fix Permissions & Cron
# ---------------------------------------------------------
echo -e "${GREEN}🔒 Fixing ownership permissions...${NC}"
sudo chown -R bs:bs "$BASE_DIR"

# ---------------------------------------------------------
# 8. Configure Crontab (Auto Update)
# ---------------------------------------------------------
echo -e "${GREEN}⏰ Configuring Crontab for Auto-Update...${NC}"
CRON_CMD="$BASE_DIR/update_safe.sh"

# Logic: Read existing cron, remove our job if exists (to prevent duplicates), then add it back.
(crontab -u bs -l 2>/dev/null | grep -Fv "$CRON_CMD"; echo "*/5 * * * * $CRON_CMD") | crontab -u bs -

echo -e "   -> Cron job set: Run update_safe.sh every 5 minutes."

# ---------------------------------------------------------
# 9. AUDIO FIX (PULSEAUDIO REPAIR)
# ---------------------------------------------------------
echo -e "${GREEN}🔊 Verifying Audio System (PulseAudio Fix)...${NC}"

# We detect if Docker mistakenly created a FOLDER where the socket should go
# if [ -d "/run/user/1000/pulse/native" ]; then
#     echo -e "${YELLOW}⚠️  Invalid directory detected at Pulse socket path. Removing it...${NC}"
#     # We deleted the fake folder that caused the "not a directory" error
#     sudo rm -rf /run/user/1000/pulse/native
# fi

# We make sure the audio service is running
if ! pulseaudio --check; then
    echo "   -> Starting PulseAudio daemon..."
    pulseaudio --start --exit-idle-time=-1
    sleep 2 # Esperamos a que cree el socket
fi

# Final verification
if [ -S "/run/user/1000/pulse/native" ]; then
     echo "   -> Audio Socket Status: OK ✅"
else
     echo -e "${YELLOW}⚠️  Warning: Audio socket still missing. Restarting Raspberry might be needed.${NC}"
fi

# ---------------------------------------------------------
# 10. Deployment
# ---------------------------------------------------------
echo -e "${BLUE}🐳 Pulling image and starting container...${NC}"
sudo docker compose up -d --pull always

echo -e "${GREEN}✅ Installation completed successfully!${NC}"
echo -e "   Project Location: $BASE_DIR"
echo -e "   Hostpipe Script: $BASE_DIR/dockerpipe.sh"
echo -e "   Logs: docker logs -f blueacoustic"
