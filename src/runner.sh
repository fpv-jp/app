#!/bin/bash
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }

log_info "Installing GitHub Actions Runner service..."

USER=$(whoami)

log_info "Copying actions-runner.service template from container..."
if ! docker cp fpvjp-app:/src/actions-runner.service - | \
  sudo sed "s|__USER__|${USER}|g" | \
  sudo tee /etc/systemd/system/actions-runner.service >/dev/null; then
    log_error "Failed to copy or generate actions-runner.service"
    exit 1
fi

log_info "Reloading systemd daemon..."
sudo systemctl daemon-reload

log_info "Enabling Actions Runner service..."
sudo systemctl enable actions-runner.service

log_info "Starting Actions Runner service..."
if sudo systemctl start actions-runner.service; then
    log_info "Actions Runner service started successfully"
else
    log_error "Failed to start Actions Runner service"
    sudo systemctl status actions-runner.service
    exit 1
fi

echo ""
log_info "Service status:"
sudo systemctl status actions-runner.service --no-pager

echo ""
log_info "Installation completed successfully!"
echo ""
log_info "Useful commands:"
echo "  sudo systemctl status actions-runner.service   # Check status"
echo "  sudo systemctl stop actions-runner.service     # Stop service"
echo "  sudo systemctl restart actions-runner.service  # Restart service"
echo "  sudo journalctl -u actions-runner.service -f   # View logs"
