#!/usr/bin/env bash
# ==============================================================================
# check-iommu.sh
# Inspects IOMMU Groups, highlights GPU and related devices, and checks isolation.
# ==============================================================================

set -euo pipefail

BOLD='\033[1m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BOLD}${BLUE}=== IOMMU Group Inspector ===${NC}\n"

if [ ! -d /sys/kernel/iommu_groups ]; then
    echo -e "${RED}[ERROR] /sys/kernel/iommu_groups directory not found!${NC}"
    echo -e "Make sure:"
    echo -e " 1. SVM / AMD-V is enabled in your UEFI/BIOS."
    echo -e " 2. IOMMU is enabled in your UEFI/BIOS."
    echo -e " 3. 'amd_iommu=on' and 'iommu=pt' are in your kernel boot options."
    exit 1
fi

shopt -s nullglob
GROUPS=(/sys/kernel/iommu_groups/*)
if [ ${#GROUPS[@]} -eq 0 ]; then
    echo -e "${RED}[ERROR] No IOMMU groups found. Please enable IOMMU in BIOS and bootloader.${NC}"
    exit 1
fi

echo -e "${BOLD}Found ${#GROUPS[@]} IOMMU groups.${NC}\n"

GPU_GROUPS=()

for g in $(find /sys/kernel/iommu_groups/ -maxdepth 1 -mindepth 1 -type d | sort -V); do
    group_num="${g##*/}"
    devices=("$g"/devices/*)
    group_has_gpu=false
    group_output=""

    for d in "${devices[@]}"; do
        pci_id="${d##*/}"
        device_info="$(lspci -nns "$pci_id" 2>/dev/null || echo "$pci_id")"
        if echo "$device_info" | grep -Ei -q "VGA compatible|3D controller|Display controller"; then
            group_has_gpu=true
            group_output+="\t${BOLD}${GREEN}${device_info} [GPU]${NC}\n"
        elif echo "$device_info" | grep -Ei -q "Audio device"; then
            group_output+="\t${YELLOW}${device_info} [AUDIO]${NC}\n"
        else
            group_output+="\t${device_info}\n"
        fi
    done

    if [ "$group_has_gpu" = true ]; then
        GPU_GROUPS+=("$group_num")
        echo -e "${BOLD}${BLUE}>>> IOMMU Group $group_num (Contains GPU):${NC}"
        echo -e "$group_output"
    else
        echo -e "IOMMU Group $group_num:"
        echo -e "$group_output"
    fi
done

echo -e "${BOLD}${BLUE}=== GPU Isolation Summary ===${NC}"
for grp in "${GPU_GROUPS[@]}"; do
    dev_count=$(find "/sys/kernel/iommu_groups/$grp/devices/" -maxdepth 1 -mindepth 1 | wc -l)
    echo -e "Group ${BOLD}$grp${NC} has ${BOLD}$dev_count${NC} device(s)."
    
    # Check if any non-GPU devices are in this group (except audio / USB-C controller on GPU)
    non_gpu_found=false
    for d in /sys/kernel/iommu_groups/"$grp"/devices/*; do
        info="$(lspci -nns "${d##*/}")"
        if ! echo "$info" | grep -Ei -q "VGA|3D|Display|Audio|USB controller|Serial bus controller"; then
            echo -e "  ${RED}[WARNING] Non-GPU device found in group:${NC} $info"
            non_gpu_found=true
        fi
    done

    if [ "$non_gpu_found" = false ]; then
        echo -e "  ${GREEN}[OK] Group is cleanly isolated for PCI passthrough!${NC}"
    else
        echo -e "  ${YELLOW}[NOTE] If your GPU shares a group with motherboard devices (e.g. SATA, PCIe bridge), consider:${NC}"
        echo -e "   - Moving GPU to the top PCIe x16 slot wired directly to the CPU."
        echo -e "   - Checking ACS support in BIOS or using the ACS override kernel patch as a last resort."
    fi
done
