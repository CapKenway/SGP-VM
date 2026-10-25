# Complete Single GPU Passthrough Guide
### Tailored for AMD Ryzen 5 5600 + AMD Radeon RX 6700 XT on Non-GRUB Systems (Limine / systemd-boot / rEFInd / kernelstub)
*Based on the RisingPrism community guidelines, modern Linux kernels, and QEMU/KVM best practices.*

---

## Table of Contents
1. [Overview & How Single GPU Passthrough Works](#1-overview--how-single-gpu-passthrough-works)
2. [Prerequisites & BIOS Configuration](#2-prerequisites--bios-configuration)
3. [Bootloader & Kernel Parameters (Limine & Non-GRUB)](#3-bootloader--kernel-parameters-limine--non-grub)
4. [IOMMU Groups Verification](#4-iommu-groups-verification)
5. [GPU vBIOS on AMD Radeon RX 6700 XT](#5-gpu-vbios-on-amd-radeon-rx-6700-xt)
6. [Libvirt Hook Architecture & Installation](#6-libvirt-hook-architecture--installation)
7. [Virtual Machine Setup & XML Configuration](#7-virtual-machine-setup--xml-configuration)
8. [Hyper-V Enlightenments & Ryzen 5 5600 Topology](#8-hyper-v-enlightenments--ryzen-5-5600-topology)
9. [Audio & Input Devices (Scream & Evdev)](#9-audio--input-devices-scream--evdev)
10. [Troubleshooting & Recovery Strategies (RX 6700 XT & Ryzen 5000)](#10-troubleshooting--recovery-strategies-rx-6700-xt--ryzen-5000)

---

## 1. Overview & How Single GPU Passthrough Works

In a traditional dual-GPU passthrough system, Linux permanently retains a secondary GPU (or iGPU) to display the desktop, while the dedicated gaming GPU is assigned exclusively to the virtual machine.

On a **Single GPU system** (such as an AMD Ryzen 5 5600 CPU with no integrated graphics, paired with an AMD Radeon RX 6700 XT):
1. The Linux host boots and displays your desktop normally using the native `amdgpu` kernel driver.
2. When you start the VM:
   - The Libvirt hook (`/etc/libvirt/hooks/qemu`) fires with the `prepare` event.
   - It runs `/usr/local/bin/vfio-startup`, which terminates the display manager (GDM, SDDM, LightDM), unbinds the Linux virtual console and framebuffer (`efi-framebuffer` / `simple-framebuffer`), terminates any remaining DRI client processes, unloads `amdgpu` and `snd_hda_intel`, and binds the GPU to `vfio-pci`.
   - Your physical monitor goes blank momentarily while the GPU switches over.
   - QEMU boots the Windows VM and attaches the physical RX 6700 XT directly; your monitor lights up with Windows!
3. When you shut down Windows:
   - Libvirt fires the `release` hook.
   - It runs `/usr/local/bin/vfio-teardown`, which unloads `vfio-pci`, reloads `amdgpu` and audio modules, rebinds the virtual consoles, and relaunches your Linux display manager.
   - Your Linux desktop returns without requiring a system reboot.

> [!IMPORTANT]
> **Safety Net Tip:** Before testing your first VM launch, always enable SSH (`sudo systemctl enable --now sshd` or `ssh`) on your Linux host. Keep an auxiliary device (laptop or phone) connected via SSH so that if the screen stays black, you can inspect `/var/log/libvirt/custom_hooks.log` or run `sudo /usr/local/bin/vfio-teardown` to restore your desktop immediately.

---

## 2. Prerequisites & BIOS Configuration

Reboot into your motherboard BIOS/UEFI (usually by pressing `Del` or `F2` at startup) and configure the following:

| Setting | Recommended Value | Reason |
| :--- | :--- | :--- |
| **SVM Mode (AMD-V)** | **Enabled** | Required for KVM virtualization on AMD CPUs. |
| **IOMMU** | **Enabled** | Required for hardware memory address isolation between Host and VM. |
| **Above 4G Decoding** | **Enabled** | Ensures 64-bit PCIe memory regions can be mapped. |
| **Smart Access Memory / ReBAR** | *Enabled (Disable if Code 43 occurs)* | Usually works fine on RDNA 2, but can be disabled if Windows driver hangs. |
| **CSM / Legacy Boot** | **Disabled (Pure UEFI)** | Passthrough via OVMF requires a standard UEFI environment. |

*Hardware Tip:* Ensure your RX 6700 XT is installed in the top PCIe x16 slot wired directly to the Ryzen 5 5600 CPU lanes (typically PCIe Bus 01:00.0) rather than a motherboard chipset slot.

---

## 3. Bootloader & Kernel Parameters (Limine & Non-GRUB)

Because your system does not use GRUB, you are likely running **Limine**, **systemd-boot**, Pop!_OS **kernelstub**, or **rEFInd**.

### Automated Detection
Run the detection script included in this repository:
```bash
./scripts/detect-bootloader.sh
```
This script will inspect `/proc/cmdline`, identify your active bootloader, and show you exactly what configuration file or command to use.

### Required Kernel Parameters for AMD Ryzen 5 5600 + RX 6700 XT
Add the following arguments to your kernel command line:
```text
amd_iommu=on iommu=pt kvm_amd.avic=1 video=efifb:off
```

- `amd_iommu=on`: Forces AMD IOMMU driver initialization.
- `iommu=pt`: Enables passthrough mode for host devices, improving performance while retaining IOMMU isolation.
- `kvm_amd.avic=1`: Enables Advanced Virtual Interrupt Controller (AVIC) on AMD Zen processors. Matches `<avic state="on"/>` in the Hyper-V XML!
- `video=efifb:off`: **Crucial for Single GPU passthrough.** Prevents the Linux kernel from holding a permanent lock on the boot EFI framebuffer, allowing `amdgpu` to be unloaded cleanly.

---

### Configuration Methods by Bootloader:

#### 1. Limine
Limine reads its configuration directly on every boot without requiring any regeneration tools.

1. Open your Limine configuration file (commonly `/boot/limine.conf`, `/boot/efi/limine.conf`, or `/boot/limine/limine.conf`):
   ```bash
   sudo nano /boot/limine.conf
   ```
2. Locate your Linux boot entry and append the parameters to `cmdline:`:
   ```text
   /Linux
       protocol: linux
       kernel_path: boot():/vmlinuz-linux
       cmdline: root=UUID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx rw quiet amd_iommu=on iommu=pt kvm_amd.avic=1 video=efifb:off
       module_path: boot():/initramfs-linux.img
   ```
3. Save the file. **No update or install command is needed**; changes take effect immediately on next reboot!

#### 2. Pop!_OS (systemd-boot with kernelstub)
Pop!_OS manages boot entries via `kernelstub`. Run:
```bash
sudo kernelstub -a "amd_iommu=on iommu=pt kvm_amd.avic=1 video=efifb:off"
```
Verify with:
```bash
sudo kernelstub -p
```

#### 3. Pure systemd-boot (Arch Linux / Solus)
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

#### 4. rEFInd
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

PCI devices are grouped into hardware isolation containers called IOMMU groups. The RX 6700 XT and its audio controller must be in a clean group, free of unrelated motherboard devices (like SATA controllers or network cards).

Run the inspector script:
```bash
./scripts/check-iommu.sh
```

### Ideal RX 6700 XT Output Example:
```text
>>> IOMMU Group 14 (Contains GPU):
	01:00.0 VGA compatible controller [0300]: Advanced Micro Devices, Inc. [AMD/ATI] Navi 22 [Radeon RX 6700/6700 XT / 6800M] [1002:73df] (rev c1) [GPU]
	01:00.1 Audio device [0403]: Advanced Micro Devices, Inc. [AMD/ATI] Navi 21/22 HDMI Audio [1002:ab28] [AUDIO]
```
If your RX 6700 XT appears only with its audio controller in that group, your system is 100% ready for passthrough.

---

## 5. GPU vBIOS on AMD Radeon RX 6700 XT

### Important Note for AMD Radeon Users
Unlike NVIDIA GPUs, **AMD Radeon RX 6000 series (RDNA 2 / Navi 22) cards generally do NOT require a modified or patched vBIOS ROM!**
- You do **NOT** need to strip headers.
- In 95% of setups, **you do NOT even need to specify a `<rom>` tag** in your Libvirt XML.
- OVMF and QEMU will initialize the card directly over PCIe BARs.

### When is a vBIOS dump needed?
Only if your specific motherboard UEFI modifies the GPU vBIOS during boot and causes the Windows VM to show a black screen on start.

If you ever need to dump it:
1. In Linux (TTY):
   ```bash
   sudo ./scripts/patch-vbios.py --help # (Header stripping is for NVIDIA; AMD can be used untouched)
   sudo ./amdvbflash -s 0 rx6700xt.rom
   ```
2. Place the untouched ROM:
   ```bash
   sudo mkdir -p /usr/share/vgabios
   sudo cp rx6700xt.rom /usr/share/vgabios/rx6700xt.rom
   sudo chmod 644 /usr/share/vgabios/rx6700xt.rom
   ```

---

## 6. Libvirt Hook Architecture & Installation

The hooks automate stopping your desktop environment, unbinding `amdgpu`, and reloading everything on VM shutdown.

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

### 7.3 Attaching the Physical RX 6700 XT
Click **Add Hardware** -> **PCI Host Device**:
1. Add your RX 6700 XT Video device (`01:00.0`).
2. Add your RX 6700 XT Audio device (`01:00.1`).

In the XML view, the devices will look like:
```xml
    <!-- RX 6700 XT Graphics (Navi 22) -->
    <hostdev mode='subsystem' type='pci' managed='yes'>
      <source>
        <address domain='0x0000' bus='0x01' slot='0x00' function='0x0'/>
      </source>
      <address type='pci' domain='0x0000' bus='0x01' slot='0x00' function='0x0' multifunction='on'/>
    </hostdev>

    <!-- RX 6700 XT HDMI Audio -->
    <hostdev mode='subsystem' type='pci' managed='yes'>
      <source>
        <address domain='0x0000' bus='0x01' slot='0x00' function='0x1'/>
      </source>
      <address type='pci' domain='0x0000' bus='0x01' slot='0x00' function='0x1'/>
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

## 10. Troubleshooting & Recovery Strategies (RX 6700 XT & Ryzen 5000)

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

### 10.2 AMD Radeon RX 6700 XT (RDNA 2) Reset Behavior
- **Hardware FLR (Function Level Reset):** The RX 6700 XT (Navi 22) supports hardware-level PCIe FLR out of the box. Unlike Polaris (RX 480/580) or Navi 10 (RX 5700 XT), it does **not** generally suffer from the legacy AMD reset bug.
- If the card fails to re-initialize after multiple VM restarts:
  Make sure your host kernel is 5.15 or newer (modern kernels handle Navi 22 FLR gracefully).
- If `amdgpu` fails to unload during startup with "Module amdgpu is in use":
  Our updated `vfio-startup` script automatically runs `fuser -k /dev/dri/*` to terminate any rogue background processes before module unload.

### 10.3 AMD Smart Access Memory (SAM / Resizable BAR)
If Windows device manager reports Code 43 on the RX 6700 XT after installing Adrenalin drivers:
1. Temporarily disable **Resizable BAR** in your motherboard BIOS.
2. Alternatively, ensure Above 4G Decoding remains enabled while testing without ReBAR.

---
*Happy gaming on your Single GPU Passthrough VM!*
