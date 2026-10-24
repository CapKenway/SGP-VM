# Complete Single GPU Passthrough Guide
### Tailored for AMD Ryzen 5 5600 & Non-GRUB Linux Systems (systemd-boot / rEFInd / kernelstub)
*Based on the RisingPrism community guidelines, modern Linux kernels, and QEMU/KVM best practices.*

---

## Table of Contents
1. [Overview & How Single GPU Passthrough Works](#1-overview--how-single-gpu-passthrough-works)
2. [Prerequisites & BIOS Configuration](#2-prerequisites--bios-configuration)
3. [Bootloader & Kernel Parameters (Non-GRUB)](#3-bootloader--kernel-parameters-non-grub)
4. [IOMMU Groups Verification](#4-iommu-groups-verification)
5. [GPU vBIOS Extraction & Patching](#5-gpu-vbios-extraction--patching)
6. [Libvirt Hook Architecture & Installation](#6-libvirt-hook-architecture--installation)
7. [Virtual Machine Setup & XML Configuration](#7-virtual-machine-setup--xml-configuration)
8. [Hyper-V Enlightenments & Ryzen 5 5600 Topology](#8-hyper-v-enlightenments--ryzen-5-5600-topology)
9. [Audio & Input Devices (Scream & Evdev)](#9-audio--input-devices-scream--evdev)
10. [Troubleshooting & Recovery Strategies](#10-troubleshooting--recovery-strategies)

---

## 1. Overview & How Single GPU Passthrough Works

In a traditional dual-GPU passthrough system, Linux permanently retains a secondary GPU (or iGPU) to display the desktop, while the dedicated gaming GPU is assigned exclusively to the virtual machine.

On a **Single GPU system** (such as an AMD Ryzen 5 5600 CPU with no integrated graphics, and a single dedicated PCIe GPU):
1. The Linux host boots and displays your desktop normally using native GPU drivers (`amdgpu` or `nvidia`).
2. When you start the VM:
   - The Libvirt hook (`/etc/libvirt/hooks/qemu`) fires.
   - It runs `/usr/local/bin/vfio-startup`, which terminates the display manager (GDM, SDDM, LightDM), unbinds the Linux virtual console and framebuffer (`efi-framebuffer`), unloads the GPU kernel modules, and binds the GPU to `vfio-pci`.
   - Your physical monitor goes blank momentarily while the GPU switches over.
   - QEMU boots the Windows VM and attaches the physical GPU directly; your monitor lights up with Windows!
3. When you shut down Windows:
   - Libvirt fires the `release` hook.
   - It runs `/usr/local/bin/vfio-teardown`, which unloads `vfio-pci`, reloads the native GPU modules, rebinds the virtual consoles, and relaunches your Linux display manager.
   - Your Linux desktop returns without requiring a system reboot.

> [!IMPORTANT]
> **Safety Net Tip:** Before testing your first VM launch, always enable SSH (`sudo systemctl enable --now sshd` or `ssh`) on your Linux host. Keep your auxiliary laptop or phone connected via SSH so that if the screen stays black, you can inspect `/var/log/libvirt/custom_hooks.log` or run `sudo /usr/local/bin/vfio-teardown` to restore your screen immediately.

---

## 2. Prerequisites & BIOS Configuration

Reboot into your motherboard BIOS/UEFI (usually by pressing `Del` or `F2` at startup) and configure the following:

| Setting | Recommended Value | Reason |
| :--- | :--- | :--- |
| **SVM Mode (AMD-V)** | **Enabled** | Required for KVM virtualization on AMD CPUs. |
| **IOMMU** | **Enabled** | Required for hardware memory address isolation between Host and VM. |
| **Above 4G Decoding** | **Enabled** | Ensures 64-bit PCIe memory regions can be mapped. |
| **Resizable BAR (ReBAR)** | *Optional (Disable if issues arise)* | Some older guest OS or GPUs fail to initialize if BAR size exceeds limits. |
| **CSM / Legacy Boot** | **Disabled (Pure UEFI)** | Passthrough via OVMF requires a standard UEFI environment. |

*Hardware Tip:* Ensure your GPU is installed in the top PCIe x16 slot wired directly to the Ryzen 5 5600 CPU lanes (PCIe Bus 01:00.0) rather than a chipset slot.

---

## 3. Bootloader & Kernel Parameters (Non-GRUB)

Because your system does not use GRUB, you are likely running **systemd-boot** (Arch Linux, Pop!_OS, Solus) or **rEFInd**.

### Automated Detection
Run the detection script included in this repository:
```bash
./scripts/detect-bootloader.sh
```
This script will inspect `/proc/cmdline`, identify your bootloader, and show you exactly what file or command to execute.

### Required Kernel Parameters for AMD Ryzen 5 5600
Add the following arguments to your kernel command line:
```text
amd_iommu=on iommu=pt kvm_amd.avic=1 video=efifb:off
```

- `amd_iommu=on`: Forces AMD IOMMU driver initialization.
- `iommu=pt`: Enables passthrough mode for host devices, improving host device performance while retaining IOMMU isolation.
- `kvm_amd.avic=1`: Enables Advanced Virtual Interrupt Controller (AVIC) on AMD Zen processors. Matches `<avic state="on"/>` in the Hyper-V XML!
- `video=efifb:off`: **Crucial for Single GPU passthrough.** Prevents the Linux kernel from holding a permanent lock on the boot EFI framebuffer, allowing the GPU to be released cleanly.

### Configuration Methods by Bootloader:

#### 1. Pop!_OS (systemd-boot with kernelstub)
Pop!_OS manages boot entries via `kernelstub`. Run:
```bash
sudo kernelstub -a "amd_iommu=on iommu=pt kvm_amd.avic=1 video=efifb:off"
```
Verify with:
```bash
sudo kernelstub -p
```

#### 2. Pure systemd-boot (Arch Linux / generic systemd-boot)
1. Locate your active loader entry:
   ```bash
   sudo nano /boot/loader/entries/*.conf
   # Or /boot/efi/loader/entries/*.conf
   # Or /efi/loader/entries/*.conf
   ```
2. Locate the line starting with `options` and append the parameters:
   ```text
   options root=UUID=xxxx-xxxx rw quiet amd_iommu=on iommu=pt kvm_amd.avic=1 video=efifb:off
   ```
3. Update systemd-boot:
   ```bash
   sudo bootctl update
   ```

#### 3. rEFInd
1. Edit the configuration file:
   ```bash
   sudo nano /boot/refind_linux.conf
   # Or /boot/efi/EFI/refind/refind.conf
   ```
2. In the `"Boot with standard options"` line, append:
   ```text
   "Boot with standard options"  "ro root=UUID=... amd_iommu=on iommu=pt kvm_amd.avic=1 video=efifb:off"
   ```

**Reboot your host** after saving bootloader changes.

---

## 4. IOMMU Groups Verification

PCI devices are isolated in hardware units called IOMMU groups. The GPU and its audio controller must be in a clean group, free of unrelated motherboard devices (like SATA controllers or network cards).

Run the inspector script:
```bash
./scripts/check-iommu.sh
```

### Ideal Output Example:
```text
>>> IOMMU Group 14 (Contains GPU):
	01:00.0 VGA compatible controller [0300]: NVIDIA Corporation AD104 [GeForce RTX 4070] [10de:2786] (rev a1) [GPU]
	01:00.1 Audio device [0403]: NVIDIA Corporation Device [10de:22bc] (rev a1) [AUDIO]
```
If your GPU appears alone (or only with its own Audio and USB-C controllers) inside its group, your system is 100% ready for passthrough.

---

## 5. GPU vBIOS Extraction & Patching

When a PC boots, the motherboard firmware executes the GPU's ROM. This often modifies the ROM in memory, preventing QEMU from initializing the GPU properly inside the VM. Providing a clean vBIOS ROM file solves this issue.

*Note: Required for NVIDIA GPUs; optional but beneficial for AMD GPUs.*

### Step 5.1: Dumping the vBIOS
#### Method A: In Linux (via TTY)
1. Switch to a text terminal by pressing `Ctrl + Alt + F3`.
2. Log in and stop your display manager:
   ```bash
   # GDM (GNOME)
   sudo systemctl stop gdm3  # or gdm
   # SDDM (KDE)
   sudo systemctl stop sddm
   # LightDM
   sudo systemctl stop lightdm
   ```
3. Unload the GPU driver:
   - For NVIDIA:
     ```bash
     sudo modprobe -r nvidia_uvm nvidia_drm nvidia_modeset nvidia
     ```
   - For AMD:
     ```bash
     sudo modprobe -r amdgpu radeon
     ```
4. Dump using `nvflash` (NVIDIA) or `amdvbflash` (AMD):
   ```bash
   # For NVIDIA:
   sudo ./nvflash --save vbios.rom
   # For AMD:
   sudo ./amdvbflash -s 0 vbios.rom
   ```
5. Reboot back to desktop:
   ```bash
   sudo reboot
   ```

#### Method B: From Windows (if dual-booting)
Download **GPU-Z** (recommended version 2.5.0), click the small arrow icon next to "BIOS Version", and click **Save to file...**.

### Step 5.2: Automatic Header Stripping (NVIDIA)
NVIDIA ROM dumps usually contain an extra UEFI header before the actual ROM code. Use the automated Python script included in this repository:
```bash
python3 ./scripts/patch-vbios.py vbios.rom patched.rom
```
The script searches for the `VIDEO` string, finds the preceding `0x55 0xAA` (`U\xAA`) signature, and trims the unwanted header with byte-level precision.

### Step 5.3: Placing the ROM File
Move the patched ROM to the system directory and set read permissions:
```bash
sudo mkdir -p /usr/share/vgabios
sudo cp patched.rom /usr/share/vgabios/patched.rom
sudo chmod 644 /usr/share/vgabios/patched.rom
```
*(On Fedora/RHEL systems, use `/var/lib/libvirt/vgabios/patched.rom` instead due to SELinux rules).*

---

## 6. Libvirt Hook Architecture & Installation

The hooks automate stopping your desktop environment, unbinding display drivers, and reloading them on shutdown.

### Automated Hook Installation
Run the installer as root:
```bash
sudo ./scripts/install-hooks.sh
```

This will automatically:
1. Create `/etc/libvirt/hooks` and backup any existing hooks.
2. Install `/etc/libvirt/hooks/qemu` (executable).
3. Install `/usr/local/bin/vfio-startup` and `/usr/local/bin/vfio-teardown` (executable).
4. Install and register `/etc/systemd/system/libvirt-nosleep@.service` to prevent host suspension during VM gameplay.

### Verifying Permissions:
```bash
ls -la /etc/libvirt/hooks/qemu
ls -la /usr/local/bin/vfio-startup
ls -la /usr/local/bin/vfio-teardown
```
All three files must have executable (`-rwxr-xr-x`) permissions.

---

## 7. Virtual Machine Setup & XML Configuration

### 7.1 Initial VM Creation in Virt-Manager
1. Create a standard Windows 10/11 virtual machine:
   - Chipset: **Q35**
   - Firmware: **UEFI (OVMF_CODE.secboot.fd or OVMF_CODE.fd)**
2. Install Windows completely using standard virtual display (QXL/Spice) and install the VirtIO guest drivers (`virtio-win.iso`).
3. Shut down the VM.

### 7.2 Removing the Virtual Display
In Virt-Manager hardware view (or via `virsh edit win10`), **delete** all virtual display hardware:
- Remove **Display Spice**
- Remove **Video QXL / Bochs / Virtio**
- Remove **Channel spicevmc**
- Remove **Audio spice**

### 7.3 Attaching the Physical GPU
Click **Add Hardware** -> **PCI Host Device**:
1. Add your GPU video controller (e.g. `01:00.0`).
2. Add your GPU audio controller (e.g. `01:00.1`).

In the XML view of the GPU video device, add the `<rom>` tag:
```xml
    <hostdev mode='subsystem' type='pci' managed='yes'>
      <source>
        <address domain='0x0000' bus='0x01' slot='0x00' function='0x0'/>
      </source>
      <rom file='/usr/share/vgabios/patched.rom'/>
      <address type='pci' domain='0x0000' bus='0x01' slot='0x00' function='0x0' multifunction='on'/>
    </hostdev>
```

---

## 8. Hyper-V Enlightenments & Ryzen 5 5600 Topology

Open your VM XML (`virsh edit win10`) and replace the `<features>`, `<cpu>`, and `<clock>` sections with the configurations below.

### Primary XML Configuration
```xml
  <features>
    <acpi/>
    <apic/>
    <hyperv mode="custom">
      <relaxed state="on"/>
      <vapic state="on"/>
      <spinlocks state="on"/>
      <vpindex state="on"/>
      <runtime state="on"/>
      <synic state="on"/>
      <stimer state="on"/>
      <frequencies state="on"/>
      <tlbflush state="off"/>
      <ipi state="off"/>
      <avic state="on"/>
    </hyperv>
    <kvm>
      <hidden state="on"/>
    </kvm>
    <vmport state="off"/>
    <ioapic driver="kvm"/>
  </features>

  <cpu mode="host-passthrough" check="none" migratable="on">
    <topology sockets="1" dies="1" clusters="1" cores="12" threads="1"/>
    <cache mode="passthrough"/>
    <feature policy="require" name="topoext"/>
  </cpu>

  <clock offset="localtime">
    <timer name="rtc" tickpolicy="catchup"/>
    <timer name="pit" tickpolicy="delay"/>
    <timer name="hpet" present="yes"/>
    <timer name="hypervclock" present="yes"/>
  </clock>
```

### CPU Topology Notes for Ryzen 5 5600
The AMD Ryzen 5 5600 is a Zen 3 processor with **1 CCX, 6 physical cores, and 12 SMT threads**.
- **User Preference (`cores="12" threads="1"`):** Informs Windows that it has 12 separate physical cores. This works well for many games that misinterpret virtual hyperthreading.
- **True SMT Topology (`cores="6" threads="2"`):** Informs Windows of the exact 6-core/2-thread layout.
- **Dedicated Host Core Option (`cores="5" threads="2"`):** Passing 10 vCPUs to the VM and reserving Core 0 (vCPU 0 and SMT vCPU 6) exclusively for the Linux host ensures the Linux background processes never stutter your game!

### Fallback Hyper-V Features (If BSOD or Boot Loops Occur)
If Windows hangs at the spinning circle, encounters blue screens, or games suffer from timing jitter, replace the `<hyperv>` block with:
```xml
    <hyperv mode="custom">
      <relaxed state="off"/>
      <vapic state="off"/>
      <spinlocks state="off"/>
      <vpindex state="on"/>
      <runtime state="on"/>
      <synic state="on"/>
      <stimer state="on"/>
      <frequencies state="on"/>
      <tlbflush state="off"/>
      <ipi state="off"/>
      <avic state="on"/>
    </hyperv>
```
*(Reference file available in `configs/win10-fallback-features.xml`).*

---

## 9. Audio & Input Devices (Scream & Evdev)

Because the virtual display is removed, standard Spice audio and virtual mouse devices are disabled. Here are the two highest-performance solutions:

### 9.1 Evdev Keyboard & Mouse Passthrough (Instant Hotkey Switching)
Evdev allows passing your physical mouse and keyboard directly to the VM with near-zero latency. You can toggle control between Linux and Windows by pressing **Left-Ctrl + Right-Ctrl** simultaneously.

1. Find your input device paths in `/dev/input/by-id/`:
   ```bash
   ls -la /dev/input/by-id/
   ```
2. Add the `<input>` elements inside `<devices>` in your XML:
   ```xml
   <input type='passthrough' bus='virtio'>
     <source evdev='/dev/input/by-id/usb-Your_Keyboard_Name-event-kbd'/>
   </input>
   <input type='passthrough' bus='virtio'>
     <source evdev='/dev/input/by-id/usb-Your_Mouse_Name-event-mouse'/>
   </input>
   ```

### 9.2 Scream Audio (Low Latency Over Virtual Network)
1. On the Windows Guest: Download and install the [Scream Virtual Sound Card](https://github.com/duncanthrax/scream).
2. On the Linux Host: Run the Scream receiver (PulseAudio/PipeWire):
   ```bash
   scream -i virbr0
   ```
Audio streams over the internal virtual network bridge without crackle or latency.

---

## 10. Troubleshooting & Recovery Strategies

### 10.1 Screen Remains Black on VM Start
1. SSH into the host from your auxiliary laptop or phone:
   ```bash
   ssh yourusername@host-ip-address
   ```
2. Check the hook execution log:
   ```bash
   sudo tail -n 50 /var/log/libvirt/custom_hooks.log
   ```
3. Check the QEMU VM log:
   ```bash
   sudo tail -n 50 /var/log/libvirt/qemu/win10.log
   ```
4. Restore your host display without rebooting:
   ```bash
   sudo virsh destroy win10
   sudo /usr/local/bin/vfio-teardown
   ```

### 10.2 NVIDIA Error 43
Modern NVIDIA drivers permit virtualization, but if Error 43 appears in Windows Device Manager:
1. Ensure the vBIOS ROM is patched with `patch-vbios.py` and specified in `<rom file='...'/>`.
2. Ensure `<kvm><hidden state='on'/></kvm>` is included in `<features>`.
3. Add a vendor ID string under `<hyperv>`:
   ```xml
   <hyperv mode="custom">
     <vendor_id state="on" value="1234567890ab"/>
     ...
   </hyperv>
   ```

### 10.3 AMD GPU Reset Bug
Some older AMD GPUs (Polaris / Navi) fail to reset properly when the VM powers off.
- Install the `vendor-reset` DKMS kernel module if your card suffers from reset issues:
  ```bash
  git clone https://github.com/gnif/vendor-reset.git
  cd vendor-reset && sudo dkms install .
  ```
- Add `vendor-reset` to `/etc/modules-load.d/vendor-reset.conf`.

---
*Happy gaming on your Single GPU Passthrough VM!*
