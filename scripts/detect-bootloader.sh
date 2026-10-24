#!/usr/bin/env bash
# ==============================================================================
# detect-bootloader.sh
# Detects the active bootloader and instructs how to add kernel parameters
# for Single GPU Passthrough (IOMMU, efifb:off, AVIC).
# ==============================================================================

set -euo pipefail

BOLD='\033[1m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BOLD}${BLUE}=== Single GPU Passthrough: Bootloader & Kernel Inspector ===${NC}\n"

# 1. Current Kernel Command Line
echo -e "${BOLD}Current Boot Arguments (/proc/cmdline):${NC}"
cat /proc/cmdline
echo ""

# 2. Check IOMMU / AVIC flags in current cmdline
echo -e "${BOLD}Checking recommended kernel parameters:${NC}"
CMDLINE="$(cat /proc/cmdline)"

check_param() {
    local param="$1"
    if echo "$CMDLINE" | grep -q -w "$param"; then
        echo -e "  [${GREEN}ACTIVE${NC}] $param"
    else
        echo -e "  [${RED}MISSING${NC}] $param"
    fi
}

check_param "amd_iommu=on"
check_param "iommu=pt"
check_param "kvm_amd.avic=1"
check_param "video=efifb:off"

echo ""
echo -e "${BOLD}${BLUE}=== Detecting Installed Bootloader ===${NC}"

BOOTLOADER="unknown"

# Detect Pop!_OS kernelstub
if command -v kernelstub >/dev/null 2>&1 && [ -f /etc/kernelstub/configuration ]; then
    BOOTLOADER="kernelstub"
# Detect systemd-boot
elif [ -d /boot/loader/entries ] || [ -d /efi/loader/entries ] || [ -d /boot/efi/loader/entries ] || command -v bootctl >/dev/null 2>&1; then
    if bootctl is-installed 2>/dev/null | grep -q "yes" || [ -d /boot/loader/entries ] || [ -d /efi/loader/entries ] || [ -d /boot/efi/loader/entries ]; then
        BOOTLOADER="systemd-boot"
    fi
# Detect rEFInd
elif [ -f /boot/refind_linux.conf ] || [ -d /boot/efi/EFI/refind ] || [ -d /boot/EFI/refind ] || [ -f /boot/efi/refind_linux.conf ]; then
    BOOTLOADER="refind"
# Detect Limine
elif [ -f /boot/limine.conf ] || [ -f /boot/limine/limine.conf ] || [ -f /boot/efi/limine.conf ]; then
    BOOTLOADER="limine"
# Detect GRUB (for reference)
elif [ -f /etc/default/grub ]; then
    BOOTLOADER="grub"
fi

echo -e "Detected Bootloader: ${BOLD}${GREEN}${BOOTLOADER}${NC}\n"

echo -e "${BOLD}${BLUE}=== Instructions to Add Kernel Parameters ===${NC}"
RECOMMENDED_ARGS="amd_iommu=on iommu=pt kvm_amd.avic=1 video=efifb:off"

case "$BOOTLOADER" in
    "kernelstub")
        echo -e "${YELLOW}You are using kernelstub (standard on Pop!_OS with systemd-boot):${NC}"
        echo -e "Run the following command in terminal:"
        echo -e "  ${BOLD}sudo kernelstub -a \"${RECOMMENDED_ARGS}\"${NC}"
        echo -e "\nTo verify it was added:"
        echo -e "  ${BOLD}sudo kernelstub -p${NC}"
        ;;

    "systemd-boot")
        echo -e "${YELLOW}You are using systemd-boot:${NC}"
        echo -e "Find your current entry configuration file in one of these directories:"
        echo -e "  - /boot/loader/entries/"
        echo -e "  - /boot/efi/loader/entries/"
        echo -e "  - /efi/loader/entries/"
        echo -e "\nLook for files ending in .conf (e.g. arch.conf, pop.conf, linux.conf)."
        echo -e "Open the file with sudo nano/vim and append to the ${BOLD}options${NC} line:"
        echo -e "  options ... ${BOLD}${RECOMMENDED_ARGS}${NC}"
        echo -e "\nThen update the bootloader with:"
        echo -e "  ${BOLD}sudo bootctl update${NC}"
        ;;

    "refind")
        echo -e "${YELLOW}You are using rEFInd:${NC}"
        echo -e "Edit ${BOLD}/boot/refind_linux.conf${NC} (or inside your EFI partition):"
        echo -e "In the \"Boot with standard options\" line, append:"
        echo -e "  ${BOLD}${RECOMMENDED_ARGS}${NC}"
        echo -e "Save the file. No update command needed for rEFInd."
        ;;

    "limine")
        echo -e "${YELLOW}You are using Limine:${NC}"
        echo -e "Edit ${BOLD}/boot/limine.conf${NC} or ${BOLD}/boot/limine/limine.conf${NC}."
        echo -e "Find your boot entry and append to ${BOLD}cmdline:${NC}:"
        echo -e "  cmdline: ... ${BOLD}${RECOMMENDED_ARGS}${NC}"
        ;;

    "grub")
        echo -e "${YELLOW}You have GRUB installed:${NC}"
        echo -e "Edit ${BOLD}/etc/default/grub${NC}."
        echo -e "Add to ${BOLD}GRUB_CMDLINE_LINUX_DEFAULT${NC}:"
        echo -e "  GRUB_CMDLINE_LINUX_DEFAULT=\"... ${BOLD}${RECOMMENDED_ARGS}${NC}\""
        echo -e "\nUpdate grub with:"
        echo -e "  Arch/Void:     ${BOLD}sudo grub-mkconfig -o /boot/grub/grub.cfg${NC}"
        echo -e "  Debian/Ubuntu: ${BOLD}sudo update-grub${NC}"
        echo -e "  Fedora:        ${BOLD}sudo grub2-mkconfig -o /etc/grub2.cfg${NC}"
        ;;

    *)
        echo -e "${RED}Could not automatically determine your bootloader configuration file.${NC}"
        echo -e "Check /boot or /boot/efi to see which bootloader config exists."
        echo -e "Required parameters to add to your bootloader kernel command line:"
        echo -e "  ${BOLD}${RECOMMENDED_ARGS}${NC}"
        ;;
esac

echo -e "\n${BOLD}${YELLOW}After modifying your bootloader, REBOOT your machine to apply the changes!${NC}"
