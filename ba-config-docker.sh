#!/bin/bash

# Define color variables for pretty output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🚀 Starting BlueAcoustic installation...${NC}"

# ---------------------------------------------------------
# 1. Directory Configuration
# ---------------------------------------------------------
BASE_DIR="/home/bs/blueacoustic"
LOG_DIR="$BASE_DIR/logs"

echo -e "${GREEN}📂 Creating directories at $BASE_DIR...${NC}"
mkdir -p "$LOG_DIR"

echo -e "${GREEN}🔧 Configuring System Pipe at /opt/cmdpipe...${NC}"
sudo mkdir -p /opt/cmdpipe
sudo chmod 777 /opt/cmdpipe

# ---------------------------------------------------------
# 2. Configure UDEV Rules (USB/Serial Symlinks)
# ---------------------------------------------------------
# This creates permanent names for USB devices so Docker can find them reliably
echo -e "${GREEN}🔌 Configuring USB Serial rules (udev)...${NC}"

# Write rules to /etc/udev/rules.d/10-usb-serial.rules
# We use 'sudo tee' to write to protected system directories
cat <<EOF | sudo tee /etc/udev/rules.d/10-usb-serial.rules > /dev/null
SUBSYSTEM=="tty", ATTRS{idVendor}=="0403", ATTRS{idProduct}=="6001", GROUP="dialout", SYMLINK+="baXB0"
SUBSYSTEM=="tty", ATTRS{idVendor}=="1a86", ATTRS{idProduct}=="55d3", GROUP="dialout", SYMLINK+="baENE0"
KERNEL=="ttyAMA0", MODE="0666",  GROUP="dialout", SYMLINK+="baMIC0"
EOF

# Reload rules and trigger events to apply changes immediately
echo -e "${GREEN}🔄 Reloading udev rules...${NC}"
sudo udevadm control --reload-rules
sudo udevadm trigger

echo -e "   -> Rules applied. Check with 'ls -l /dev/ba*'"

# Navigate to project dir
cd "$BASE_DIR" || { echo "❌ Could not enter $BASE_DIR"; exit 1; }

# ---------------------------------------------------------
# 3. Generate storage.json
# ---------------------------------------------------------
echo -e "${GREEN}📝 Generating storage.json...${NC}"
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

# ---------------------------------------------------------
# 4. Generate docker-compose.yml
# ---------------------------------------------------------
echo -e "${GREEN}📝 Generating docker-compose.yml...${NC}"
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
      # Mapping the symlinks created by udev rules
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
      - PYTHONUNBUFFERED=1

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
# 5. Deployment
# ---------------------------------------------------------
echo -e "${BLUE}🐳 Pulling image and starting container...${NC}"
sudo docker compose up -d --pull always

echo -e "${GREEN}✅ Installation completed successfully!${NC}"
echo -e "   Project Location: $BASE_DIR"
echo -e "   View Logs: docker logs -f blueacoustic"
