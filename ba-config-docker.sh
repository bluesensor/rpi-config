#!/bin/bash

# Define color variables for pretty output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🚀 Starting BlueAcoustic installation...${NC}"

# ---------------------------------------------------------
# 1. Directory Configuration (Using absolute paths)
# ---------------------------------------------------------
# Base project directory
BASE_DIR="/home/bs/blueacoustic"
LOG_DIR="$BASE_DIR/logs"

echo -e "${GREEN}📂 Creating directories at $BASE_DIR...${NC}"
# Create project and log directories
mkdir -p "$LOG_DIR"

# Configure System Pipe directory (Required by docker-compose volumes)
echo -e "${GREEN}🔧 Configuring System Pipe at /opt/cmdpipe...${NC}"
sudo mkdir -p /opt/cmdpipe
# Set permissions to allow read/write access for the container
sudo chmod 777 /opt/cmdpipe

# Navigate to the project directory
cd "$BASE_DIR" || { echo "❌ Could not enter $BASE_DIR"; exit 1; }

# ---------------------------------------------------------
# 2. Generate storage.json
# ---------------------------------------------------------
# Mapping Python class attributes to JSON format
echo -e "${GREEN}📝 Generating storage.json with default values...${NC}"
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

# Set write permissions so the Docker container (internal user) can update it
chmod 666 storage.json

# ---------------------------------------------------------
# 3. Generate docker-compose.yml
# ---------------------------------------------------------
echo -e "${GREEN}📝 Generating docker-compose.yml...${NC}"
cat <<EOF > docker-compose.yml
version: "3.3"

services:
  blueacoustic:
    container_name: blueacoustic
    image: dmaroto213/blueacoustic:latest
    restart: always

    # Use host networking to access hardware interfaces easily
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
      - PYTHONUNBUFFERED=1

    volumes:
      # 1. The Pipe (System command pipe)
      - /opt/cmdpipe:/hostpipe
      # 2. Logs and Storage (Persisted in user home)
      - /home/bs/blueacoustic/logs:/blueacoustic/logs
      - /home/bs/blueacoustic/storage.json:/blueacoustic/storage.json
      # 3. System Configs (Host hardware/audio configs)
      - /boot/config.txt:/host/boot/config.txt
      - /run/user/1000/pulse/native:/run/user/1000/pulse/native
      - /home/bs/.config/pulse/:/root/.config/pulse/
      # 4. Timezone Info (Sync container time with host)
      - /etc/timezone:/etc/timezone:ro
      - /etc/localtime:/etc/localtime:ro
EOF

# ---------------------------------------------------------
# 4. Deployment
# ---------------------------------------------------------
echo -e "${BLUE}🐳 Pulling image and starting container...${NC}"
# Using sudo as Docker usually requires root privileges
sudo docker compose up -d --pull always

echo -e "${GREEN}✅ Installation completed successfully!${NC}"
echo -e "   Project Location: $BASE_DIR"
echo -e "   View Logs: docker logs -f blueacoustic"
