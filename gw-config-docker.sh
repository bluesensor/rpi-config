#!/bin/bash

# ==========================================
# Dockerpipe Automated Installer (IDEMPOTENT)
# ==========================================

set -e

USER_NAME="pi"
USER_HOME="/home/$USER_NAME"
TEMPLATES_DIR="$USER_HOME/Templates"
PIPE_DIR="/opt/cmdpipe"
PIPE_FILE="dockerpipe"

# Check if running as root
if [ "$EUID" -ne 0 ]; then
  echo "Please run this script as root (sudo ./install.sh)"
  exit 1
fi

echo "=== Dockerpipe Idempotent Installer ==="

# -------------------------------------------------
# 0. Base directories
# -------------------------------------------------
mkdir -p "$TEMPLATES_DIR"
chown "$USER_NAME:$USER_NAME" "$TEMPLATES_DIR"

# Shared folder
SHARED_DIR="$TEMPLATES_DIR/shared-data-bluegateway"
if [ ! -d "$SHARED_DIR" ]; then
    mkdir -p "$SHARED_DIR"
    chown -R "$USER_NAME:$USER_NAME" "$SHARED_DIR"
    echo "Created directory $SHARED_DIR"
else
    echo "Directory already exists: $SHARED_DIR"
fi

# -------------------------------------------------
# 1. Setup Named Pipe (safe / idempotent)
# -------------------------------------------------
if [ ! -d "$PIPE_DIR" ]; then
    mkdir -p "$PIPE_DIR"
    echo "Created directory $PIPE_DIR"
fi

if [ ! -p "$PIPE_DIR/$PIPE_FILE" ]; then
    mkfifo "$PIPE_DIR/$PIPE_FILE"
    chmod 666 "$PIPE_DIR/$PIPE_FILE"
    echo "Created named pipe: $PIPE_DIR/$PIPE_FILE"
else
    echo "Named pipe already exists."
fi

# -------------------------------------------------
# Function to safely write file only if changed
# -------------------------------------------------
write_if_changed() {
    local target_file="$1"
    local tmp_file
    tmp_file=$(mktemp)

    cat > "$tmp_file"

    if [ -f "$target_file" ]; then
        if cmp -s "$tmp_file" "$target_file"; then
            rm "$tmp_file"
            echo "No changes in $target_file"
            return
        fi
    fi

    mv "$tmp_file" "$target_file"
    echo "Updated: $target_file"
}

# -------------------------------------------------
# Create standard subdirectories for each instance
# -------------------------------------------------
create_bluegateway_subdirs() {
    local base_dir="$1"

    for subdir in data logs recordings; do
        if [ ! -d "$base_dir/$subdir" ]; then
            mkdir -p "$base_dir/$subdir"
            echo "Created directory $base_dir/$subdir"
        else
            echo "Directory already exists: $base_dir/$subdir"
        fi
    done

    chown -R "$USER_NAME:$USER_NAME" "$base_dir"
}

# -------------------------------------------------
# Install service instance
# -------------------------------------------------
install_instance() {
    local SERVICE_NAME=$1
    local DIRECTORY_NAME=$2
    local FULL_DIR="$TEMPLATES_DIR/$DIRECTORY_NAME"
    local SCRIPT_PATH="$FULL_DIR/dockerpipe.sh"
    local SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"

    echo ""
    echo "------------------------------------------------"
    echo "Processing: $SERVICE_NAME"
    echo "Directory : $FULL_DIR"
    echo "------------------------------------------------"

    # Create main directory only if missing
    if [ ! -d "$FULL_DIR" ]; then
        mkdir -p "$FULL_DIR"
        chown "$USER_NAME:$USER_NAME" "$FULL_DIR"
        echo "Created directory $FULL_DIR"
    else
        echo "Directory already exists."
    fi

    # Create required subdirectories
    create_bluegateway_subdirs "$FULL_DIR"

    # -----------------------------
    # Create dockerpipe.sh safely
    # -----------------------------
    write_if_changed "$SCRIPT_PATH" <<EOF
#!/bin/bash

mkdir -p "\$(dirname "\$0")/logs"
parent_path=\$(cd "\$(dirname "\${BASH_SOURCE[0]}")" || exit ; pwd -P)

while true; do
    cmd=\$(cat /opt/cmdpipe/dockerpipe)
    timestamp=\$(date +"%Y-%m-%d %H:%M:%S")

    echo "[\$timestamp] - Command executed: \$cmd" >> "\$parent_path/logs/commands.log"

    if [ -n "\$cmd" ]; then
        eval "\$cmd" >> "\$parent_path/logs/commands.log" 2>&1
    fi

    echo "[\$timestamp] - Command finished" >> "\$parent_path/logs/commands.log"
done
EOF

    chmod +x "$SCRIPT_PATH"
    chown "$USER_NAME:$USER_NAME" "$SCRIPT_PATH"

    # -----------------------------
    # Create systemd service safely
    # -----------------------------
    write_if_changed "$SERVICE_FILE" <<EOF
[Unit]
Description=Dockerpipe Service ($SERVICE_NAME)
After=multi-user.target

[Service]
User=$USER_NAME
Type=simple
Restart=always
RestartSec=10
WorkingDirectory=$FULL_DIR
ExecStart=$SCRIPT_PATH

[Install]
WantedBy=multi-user.target
EOF

    systemctl enable "${SERVICE_NAME}.service" >/dev/null 2>&1 || true
}

# -------------------------------------------------
# Install 4 instances
# -------------------------------------------------
install_instance "dockerpipe"  "bluegateway"
install_instance "dockerpipe0" "bluegateway-virt0"
install_instance "dockerpipe1" "bluegateway-virt1"
install_instance "dockerpipe2" "bluegateway-virt2"

# Reload systemd once
systemctl daemon-reload

# Restart services safely
for svc in dockerpipe dockerpipe0 dockerpipe1 dockerpipe2; do
    systemctl restart "$svc"
done

echo ""
echo "=== Installation Complete ==="
echo "Created/validated folders:"
echo "  - $TEMPLATES_DIR/bluegateway/{data,logs,recordings}"
echo "  - $TEMPLATES_DIR/bluegateway-virt0/{data,logs,recordings}"
echo "  - $TEMPLATES_DIR/bluegateway-virt1/{data,logs,recordings}"
echo "  - $TEMPLATES_DIR/bluegateway-virt2/{data,logs,recordings}"
echo "  - $SHARED_DIR"
echo ""
echo "Check logs with: journalctl -u dockerpipe1 -f"
