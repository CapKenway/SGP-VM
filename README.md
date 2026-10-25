# Single GPU Passthrough (SGP-VM)

Complete automation scripts, configurations, and documentation for running a Windows KVM/QEMU virtual machine with Single GPU Passthrough on Linux.

Tailored for **AMD Ryzen 5 5600** and **AMD Radeon RX 6700 XT** on non-GRUB bootloaders (**Limine**, **systemd-boot**, Pop!_OS **kernelstub**, or **rEFInd**).

---

## Repository Structure

```text
SGP-VM/
├── GUIDE.md                           # Master step-by-step walkthrough & troubleshooting
├── README.md                          # Quick start overview (this file)
├── configs/
│   ├── win10-ryzen5-5600.xml          # Complete Libvirt domain XML tailored for Ryzen 5 5600 & RX 6700 XT
│   └── win10-fallback-features.xml    # Fallback Hyper-V enlightenments if BSOD/stutter occurs
├── hooks/
│   ├── qemu                           # Libvirt master hook dispatcher (/etc/libvirt/hooks/qemu)
│   ├── vfio-startup                   # GPU isolation & desktop shutdown script (/usr/local/bin/vfio-startup)
│   └── vfio-teardown                  # Host desktop restore & GPU reattachment (/usr/local/bin/vfio-teardown)
├── scripts/
│   ├── check-iommu.sh                 # Inspects IOMMU groups & verifies GPU isolation
│   ├── detect-bootloader.sh           # Identifies bootloader (Limine/systemd-boot/etc.) & prints kernel steps
│   ├── install-hooks.sh               # Automated installer for hooks & systemd services
│   └── patch-vbios.py                 # Automated Python tool to strip NVIDIA ROM headers (optional for AMD)
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
If you are using **Limine**, open `/boot/limine.conf` (or `/boot/efi/limine.conf`), locate your Linux boot entry, and add the recommended parameters to `cmdline:`:
```text
cmdline: ... amd_iommu=on iommu=pt kvm_amd.avic=1 video=efifb:off
```
*(Limine requires no update command; simply save and reboot).*

### 2. Verify IOMMU Groups
```bash
./scripts/check-iommu.sh
```
Confirm your **AMD Radeon RX 6700 XT** (Navi 22 `1002:73df`) and **Navi 21/22 HDMI Audio** (`1002:ab28`) are in an isolated IOMMU group.

### 3. Install Libvirt Hooks
Run the automated installer as root:
```bash
sudo ./scripts/install-hooks.sh
```

### 4. Configure Your VM
Use [configs/win10-ryzen5-5600.xml](file:///home/kenway/Projects/SGP-VM/configs/win10-ryzen5-5600.xml) as the template for your virtual machine.
- Note: On AMD Radeon RX 6700 XT, `<rom>` is **optional** and generally not needed because RDNA 2 initializes directly over PCIe BARs without header tampering.

If Windows encounters boot loops, replace the `<features>` block with [configs/win10-fallback-features.xml](file:///home/kenway/Projects/SGP-VM/configs/win10-fallback-features.xml) (with `relaxed`, `spinlocks`, and `vapic` turned off).

For in-depth details, see [GUIDE.md](file:///home/kenway/Projects/SGP-VM/GUIDE.md).
