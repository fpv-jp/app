#!/bin/bash

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

if [ $# -ne 2 ]; then
    log_error "Usage: sudo bash $0 <PLATFORM> <MODE>"
    echo ""
    echo "PLATFORM options:"
    echo "  RPI4_V4L2"
    echo "  JETSON_NANO_2GB"
    echo "  JETSON_ORIN_NANO_SUPER"
    echo "  RADXA_ROCK_5B"
    echo "  RADXA_ROCK_5T"
    echo "  RPI4_LIBCAM"
    echo "  RPI5_LIBCAM"
    echo ""
    echo "MODE options:"
    echo "  P2P"
    echo "  SFU"
    echo ""
    echo "Example: $0 RPI4_V4L2 P2P"
    exit 1
fi

PLATFORM=$1
MODE=$2

if [ "$EUID" -ne 0 ]; then 
    log_error "This script must be run as root (use sudo)"
    exit 1
fi

if ! command -v docker &> /dev/null; then
    log_error "Docker is not installed or not in PATH"
    exit 1
fi

if ! docker ps -a --format '{{.Names}}' | grep -q "^fpvjp-app$"; then
    log_error "Docker container 'fpvjp-app' not found"
    exit 1
fi

log_info "Starting VTX installation for $PLATFORM in $MODE mode..."

if [ -f /opt/vtx/vtx ]; then
    log_warn "VTX is already installed. This will overwrite existing files."
    read -p "Continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Installation cancelled."
        exit 0
    fi
fi

log_info "Creating /opt/vtx directory..."
mkdir -p /opt/vtx

log_info "Copying server certificate..."
if ! docker cp fpvjp-app:/app/certificate/server-ca-cert.pem /opt/vtx/; then
    log_error "Failed to copy server-ca-cert.pem from container"
    exit 1
fi

log_info "Copying VTX binary for platform: $PLATFORM"
case "$PLATFORM" in
    RPI4_V4L2)
        BINARY="vtx-rpi4-v4l2"
        ;;
    JETSON_NANO_2GB)
        BINARY="vtx-jetson-nano-2gb"
        ;;
    JETSON_ORIN_NANO_SUPER)
        BINARY="vtx-jetson-orin-nano-super"
        ;;
    RADXA_ROCK_5B)
        BINARY="vtx-radxa-rock-5b"
        ;;
    RADXA_ROCK_5T)
        BINARY="vtx-radxa-rock-5t"
        ;;
    RPI4_LIBCAM)
        BINARY="vtx-rpi4-libcam"
        ;;
    RPI5_LIBCAM)
        BINARY="vtx-rpi5-libcam"
        ;;
    *)
        log_error "Unknown platform: $PLATFORM"
        exit 1
        ;;
esac

if ! docker cp "fpvjp-app:/src/$BINARY" /opt/vtx/vtx; then
    log_error "Failed to copy $BINARY from container"
    exit 1
fi

log_info "Setting executable permission..."
chmod +x /opt/vtx/vtx

log_info "Copying environment file for mode: $MODE"
case "$MODE" in
    P2P)
        ENV_FILE="p2p.env"
        ;;
    SFU)
        ENV_FILE="sfu.env"
        ;;
    *)
        log_error "Unknown mode: $MODE"
        exit 1
        ;;
esac

if ! docker cp "fpvjp-app:/src/$ENV_FILE" /etc/vtx.env; then
    log_error "Failed to copy $ENV_FILE from container"
    exit 1
fi

log_info "Updating /etc/hosts with fpv hostname..."
if grep -q "^127\.0\.0\.1.*\bfpv\b" /etc/hosts; then
    log_info "fpv hostname already exists in /etc/hosts"
else
    if grep -q "^127\.0\.0\.1" /etc/hosts; then
        sed -i '/^127\.0\.0\.1/ s/$/ fpv/' /etc/hosts
        log_info "Added fpv to existing 127.0.0.1 entry"
    else
        echo "127.0.0.1 localhost fpv" >> /etc/hosts
        log_info "Added new 127.0.0.1 entry with fpv"
    fi
fi

log_info "Copying systemd service file..."
if ! docker cp fpvjp-app:/src/vtx.service /etc/systemd/system/; then
    log_error "Failed to copy vtx.service from container"
    exit 1
fi

log_info "Reloading systemd daemon..."
systemctl daemon-reload

log_info "Enabling VTX service..."
systemctl enable vtx.service

log_info "Starting VTX service..."
if systemctl start vtx.service; then
    log_info "VTX service started successfully"
else
    log_error "Failed to start VTX service"
    systemctl status vtx.service
    exit 1
fi

echo ""
log_info "Service status:"
systemctl status vtx.service --no-pager

echo ""
log_info "Installation completed successfully!"
log_info "Platform: $PLATFORM"
log_info "Mode: $MODE"
echo ""
log_info "Useful commands:"
echo "  sudo systemctl status vtx.service   # Check status"
echo "  sudo systemctl stop vtx.service     # Stop service"
echo "  sudo systemctl restart vtx.service  # Restart service"
echo "  sudo journalctl -u vtx.service -f   # View logs"
