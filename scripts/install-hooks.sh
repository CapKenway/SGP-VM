#!/usr/bin/env bash
# ==============================================================================
# scripts/install-hooks.sh
# Installs libvirt hooks, helper scripts, and systemd sleep inhibitor service.
# ==============================================================================

set -euo pipefail

BOLD='\033[1m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}[ERROR] This installation script must be run as root.${NC}"
    echo -e "Please re-run with: ${BOLD}sudo ./scripts/install-hooks.sh${NC}"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo -e "${BOLD}${BLUE}=== Installing Single GPU Passthrough Hooks ===${NC}\n"

# 1. Prepare libvirt hooks directory
mkdir -p /etc/libvirt/hooks
mkdir -p /var/log/libvirt

# 2. Backup existing files if found
backup_if_exists() {
    local target="$1"
    if [ -f "$target" ]; then
        local backup="${target}.bak_$(date +%Y%m%d%H%M%S)"
        echo -e "${YELLOW}[BACKUP]${NC} Backing up $target -> $backup"
        cp "$target" "$backup"
    fi
}

backup_if_exists /etc/libvirt/hooks/qemu
backup_if_exists /usr/local/bin/vfio-startup
backup_if_exists /usr/local/bin/vfio-teardown
backup_if_exists /etc/systemd/system/libvirt-nosleep@.service

# 3. Copy hook and helper scripts
echo -e "${BLUE}[INSTALL]${NC} Copying hooks/qemu -> /etc/libvirt/hooks/qemu"
cp "$SCRIPT_DIR/hooks/qemu" /etc/libvirt/hooks/qemu
chmod +x /etc/libvirt/hooks/qemu

echo -e "${BLUE}[INSTALL]${NC} Copying hooks/vfio-startup -> /usr/local/bin/vfio-startup"
cp "$SCRIPT_DIR/hooks/vfio-startup" /usr/local/bin/vfio-startup
chmod +x /usr/local/bin/vfio-startup

echo -e "${BLUE}[INSTALL]${NC} Copying hooks/vfio-teardown -> /usr/local/bin/vfio-teardown"
cp "$SCRIPT_DIR/hooks/vfio-teardown" /usr/local/bin/vfio-teardown
chmod +x /usr/local/bin/vfio-teardown

# 4. Copy systemd sleep inhibitor service
echo -e "${BLUE}[INSTALL]${NC} Installing systemd-no-sleep service"
cp "$SCRIPT_DIR/systemd/libvirt-nosleep@.service" /etc/systemd/system/libvirt-nosleep@.service
systemctl daemon-reload

# 5. Make sure scripts directory permissions are executable
chmod +x "$SCRIPT_DIR/scripts/"*.sh 2>/dev/null || true
chmod +x "$SCRIPT_DIR/scripts/"*.py 2>/dev/null || true

echo -e "\n${BOLD}${GREEN}=== Installation Completed Successfully! ===${NC}"
echo -e "Hook files placed:"
echo -e "  - /etc/libvirt/hooks/qemu"
echo -e "  - /usr/local/bin/vfio-startup"
echo -e "  - /usr/local/bin/vfio-teardown"
echo -e "  - /etc/systemd/system/libvirt-nosleep@.service"
echo -e "  - Log file: /var/log/libvirt/custom_hooks.log"
echo ""
