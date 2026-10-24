# Single GPU Passthrough (SGP-VM)

Complete automation scripts, configurations, and documentation for running a Windows KVM/QEMU virtual machine with Single GPU Passthrough on Linux.

Tailored for **AMD Ryzen 5 5600** and systems with **non-GRUB bootloaders** (such as `systemd-boot`, `kernelstub`, or `rEFInd`).

---

## Repository Structure

```text
SGP-VM/
├── GUIDE.md                           # Master step-by-step walkthrough & troubleshooting
├── README.md                          # Quick start overview (this file)
├── configs/
│   ├── win10-ryzen5-5600.xml          # Complete Libvirt domain XML tailored for Ryzen 5 5600
│   └── win10-fallback-features.xml    # Fallback Hyper-V enlightenments if BSOD/stutter occurs
├── hooks/
│   ├── qemu                           # Libvirt master hook dispatcher (/etc/libvirt/hooks/qemu)
│   ├── vfio-startup                   # GPU isolation & desktop shutdown script (/usr/local/bin/vfio-startup)
│   └── vfio-teardown                  # Host desktop restore & GPU reattachment (/usr/local/bin/vfio-teardown)
├── scripts/
│   ├── check-iommu.sh                 # Inspects IOMMU groups & verifies GPU isolation
│   ├── detect-bootloader.sh           # Identifies bootloader & prints kernel parameter steps
│   ├── install-hooks.sh               # Automated installer for hooks & systemd services
│   └── patch-vbios.py                 # Automated Python tool to strip NVIDIA ROM headers
└── systemd/
    └── libvirt-nosleep@.service       # Prevents host sleep while the VM is active
```

---

## Quick Start Workflow

### 1. Identify Bootloader & Add Kernel Parameters
On your main rig, run:
```bash
chmod +x scripts/*.sh scripts/*.py
./scripts/detect-bootloader.sh
```
Add the recommended parameters (`amd_iommu=on iommu=pt kvm_amd.avic=1 video=efifb:off`) and reboot.

### 2. Verify IOMMU Groups
```bash
./scripts/check-iommu.sh
```
Ensure your GPU and GPU audio controller are isolated in their own IOMMU group.

### 3. Dump & Patch GPU vBIOS (NVIDIA)
After dumping your GPU vBIOS (or if you already have it), clean the header using the Python utility:
```bash
python3 ./scripts/patch-vbios.py vbios.rom patched.rom
sudo mkdir -p /usr/share/vgabios
sudo cp patched.rom /usr/share/vgabios/patched.rom
sudo chmod 644 /usr/share/vgabios/patched.rom
```

### 4. Install Libvirt Hooks
Run the automated installer as root:
```bash
sudo ./scripts/install-hooks.sh
```

### 5. Configure Your VM
Use [configs/win10-ryzen5-5600.xml](file:///home/kenway/Projects/SGP-VM/configs/win10-ryzen5-5600.xml) as the template for your virtual machine.

If Windows encounters boot loops, replace the `<features>` block with [configs/win10-fallback-features.xml](file:///home/kenway/Projects/SGP-VM/configs/win10-fallback-features.xml) (with `relaxed`, `spinlocks`, and `vapic` turned off).

For in-depth details, see [GUIDE.md](file:///home/kenway/Projects/SGP-VM/GUIDE.md).
