# Rweezy OS — Detailed Documentation

## Table of Contents

1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Build System](#build-system)
4. [Kernel](#kernel)
5. [Userspace (BusyBox)](#userspace-busybox)
6. [Initramfs](#initramfs)
7. [Root Filesystem](#root-filesystem)
8. [Boot Process (Detailed)](#boot-process-detailed)
9. [Networking](#networking)
10. [Disk Image](#disk-image)
11. [Custom Kernel Module](#custom-kernel-module)
12. [Configuration Reference](#configuration-reference)
13. [QEMU Usage](#qemu-usage)
14. [Troubleshooting](#troubleshooting)
15. [Development Guide](#development-guide)

---

## Overview

Rweezy OS is an independent, minimal Linux distribution built entirely from source. It is designed as an educational and hobbyist project that demonstrates how a complete Linux operating system is assembled from its core components:

- A custom-compiled **Linux kernel** (7.2.0) with Rweezy-specific modifications
- **BusyBox** (1.39.0) providing the entire userspace (shell, coreutils, init, networking tools)
- A hand-crafted **two-stage boot process** using initramfs and `switch_root`
- A custom **kernel identity interface** at `/proc/rweezy`

The target platform is **x86_64 KVM/QEMU virtual machines**. The system boots from a virtio block device (`/dev/vda`) containing an ext4 root filesystem.

---

## Architecture

```
┌─────────────────────────────────────────────────────┐
│                    Rweezy OS                         │
├─────────────────────────────────────────────────────┤
│                                                     │
│  ┌──────────────────────────────────────────────┐   │
│  │              Linux Kernel 7.2.0               │   │
│  │  • x86_64, KVM guest optimized               │   │
│  │  • /proc/rweezy identity interface            │   │
│  │  • Virtio drivers (block, net, SCSI)          │   │
│  │  • ext4, networking, modules                   │   │
│  └──────────────────────────────────────────────┘   │
│                                                     │
│  ┌──────────────────────────────────────────────┐   │
│  │          BusyBox 1.39.0 Userspace             │   │
│  │  • Statically linked (~408 applets)           │   │
│  │  • /bin/sh (ash shell)                        │   │
│  │  • Core utilities (ls, cat, cp, mv, etc.)     │   │
│  │  • Networking (ip, udhcpc, wget)              │   │
│  │  • init, switch_root, mount                   │   │
│  └──────────────────────────────────────────────┘   │
│                                                     │
│  ┌──────────────────────────────────────────────┐   │
│  │           Custom Init Scripts                 │   │
│  │  • initramfs/init (stage 1)                   │   │
│  │  • rootfs/init (stage 2)                      │   │
│  │  • DHCP handler (udhcpc default.script)       │   │
│  └──────────────────────────────────────────────┘   │
│                                                     │
│  ┌──────────────────────────────────────────────┐   │
│  │         ext4 Root Filesystem                  │   │
│  │  • /dev/vda (virtio block device)             │   │
│  │  • 512 MB, volume label "RWEEZY"             │   │
│  └──────────────────────────────────────────────┘   │
│                                                     │
└─────────────────────────────────────────────────────┘
```

---

## Build System

The entire build is orchestrated by a single script: `build.sh`.

### Build Steps

| Step | Action | Output |
|------|--------|--------|
| 1/5 | Compile Linux kernel with `make -j$(nproc)` | `build/vmlinuz` (bzImage) |
| 2/5 | Compile BusyBox with `make -j$(nproc)` | `src/busybox/busybox` |
| 3/5 | Install BusyBox into rootfs | `rootfs/bin/`, `rootfs/sbin/`, `rootfs/usr/` |
| 4/5 | Prepare initramfs staging tree | `initramfs-build/` with busybox + symlinks |
| 5/5 | Create compressed initramfs archive | `build/initramfs.cpio.gz` |

### Build Variables

```bash
ROOT="$(cd "$(dirname "$0")" && pwd)"      # Project root
KERNEL="$ROOT/src/linux"                     # Kernel source tree
BUSYBOX="$ROOT/src/busybox"                 # BusyBox source tree
ROOTFS="$ROOT/rootfs"                        # Root filesystem overlay
INITRAMFS_SRC="$ROOT/initramfs"             # Initramfs source templates
INITRAMFS_BUILD="$ROOT/initramfs-build"     # Initramfs staging (generated)
BUILD="$ROOT/build"                          # Final build outputs
```

### Initramfs Symlinks Created

During step 4, the following BusyBox applet symlinks are created in `initramfs-build/bin/`:

```
sh → busybox
mount → busybox
switch_root → busybox
cttyhack → busybox
setsid → busybox
sleep → busybox
mkdir → busybox
```

These are the minimal set required for the initramfs init script to function.

### Build Requirements

| Dependency | Purpose |
|-----------|---------|
| GCC | Compiles kernel and BusyBox |
| GNU Make | Build orchestration |
| cpio | Creates initramfs archive (newc format) |
| gzip | Compresses initramfs |
| nproc | Detects CPU count for parallel builds |
| find | Lists files for cpio archive |

---

## Kernel

### Version

- **Linux 7.2.0** ("Baby Opossum Posse")
- **Local version suffix:** `-rweezy` (from `src/linux/localversion-rweezy`)
- **Full version string:** `7.2.0-rweezy-<git-commit-hash>`

### Key Configuration Options

#### Architecture
- `CONFIG_64BIT=y` — 64-bit kernel
- `CONFIG_X86_64=y` — x86_64 target
- `CONFIG_SMP=y` — Symmetric multiprocessing
- `CONFIG_NR_CPUS=256` — Maximum 256 CPUs

#### Virtualization
- `CONFIG_KVM_GUEST=y` — KVM paravirtualized guest
- `CONFIG_VIRTIO=y` — Virtio subsystem
- `CONFIG_VIRTIO_BLK=y` — Virtio block device driver
- `CONFIG_VIRTIO_NET=y` — Virtio network device driver
- `CONFIG_SCSI_VIRTIO=y` — Virtio SCSI driver
- `CONFIG_PCI_IOV=y` — PCI SR-IOV support

#### Filesystem
- `CONFIG_EXT4_FS=y` — ext4 filesystem (root partition)
- `CONFIG_BLK_DEV_INITRD=y` — Initial RAM filesystem support
- `CONFIG_TMPFS=y` — Temporary filesystem

#### Networking
- `CONFIG_NET=y` — Networking support
- `CONFIG_INET=y` — IPv4 networking
- `CONFIG_IPV6=y` — IPv6 networking
- `CONFIG_NETFILTER=y` — Packet filtering
- `CONFIG_CFG80211=y` — Wireless configuration
- `CONFIG_MAC80211=y` — Wireless MAC layer

#### Kernel Features
- `CONFIG_HZ_1000=y` — 1000 Hz tick rate (low latency)
- `CONFIG_PREEMPT_LAZY=y` — Preemptible kernel
- `CONFIG_MODULES=y` — Loadable kernel modules
- `CONFIG_RWEEZY=y` — Rweezy OS identity interface

#### Hardware
- `CONFIG_SATA_AHCI=y` — SATA AHCI controller
- `CONFIG_EFI=y` — EFI boot support
- `CONFIG_BLK_DEV_SD=y` — SCSI disk support
- `CONFIG_USB_SUPPORT=y` — USB support

### Kernel Source Modifications

The Rweezy kernel includes the following custom additions to the upstream Linux 7.2.0 source:

1. **`src/linux/fs/proc/rweezy.c`** — Custom `/proc/rweezy` proc entry
2. **`src/linux/fs/proc/Kconfig`** — Added `CONFIG_RWEEZY` option
3. **`src/linux/fs/proc/Makefile`** — Added build rule for `rweezy.o`
4. **`src/linux/localversion-rweezy`** — Contains `-rweezy` suffix

---

## Userspace (BusyBox)

### Version

- **BusyBox 1.39.0**
- **Static linking** (`CONFIG_STATIC=y`) — no shared library dependencies
- **891 configuration options enabled**
- **408 applet symlinks** generated

### Key Applets

| Category | Applets |
|----------|---------|
| Shell | `sh` (ash), `bash`-compatible builtins |
| Coreutils | `ls`, `cat`, `cp`, `mv`, `rm`, `mkdir`, `chmod`, `chown`, `date`, `echo`, `head`, `tail`, `wc`, `grep`, `find`, `sort`, `uniq` |
| Filesystem | `mount`, `umount`, `fdisk`, `mkfs.ext4`, `df`, `du`, `sync` |
| Networking | `ip`, `ifconfig`, `ping`, `wget`, `udhcpc`, `udhcpd`, `nslookup`, `telnet`, `ssh` |
| Init | `init`, `reboot`, `halt`, `poweroff`, `switch_root` |
| Process | `ps`, `top`, `kill`, `nice`, `nohup`, `xargs` |
| Archiving | `tar`, `gzip`, `gunzip`, `cpio`, `zip`, `unzip` |
| Text | `vi`, `sed`, `awk`, `cut`, `tr`, `diff`, `tee` |
| System | `mount`, `umount`, `sysctl`, `dmesg`, `free`, `uptime`, `uname` |

### Build Configuration

The BusyBox `.config` file at `src/busybox/.config` controls which applets are compiled. Key options:

- `CONFIG_STATIC=y` — Statically linked binary
- `CONFIG_CROSS_COMPILER_PREFIX=""` — Native compilation (no cross-compiler)
- `CONFIG_PREFIX="$ROOTFS"` — Install prefix set during build

---

## Initramfs

The initramfs (initial RAM filesystem) is the first userspace environment loaded by the kernel. Its sole purpose is to mount the real root filesystem and `switch_root` into it.

### Source

- **Init script:** `initramfs/init`
- **BusyBox binary:** Copied from `rootfs/bin/busybox` during build

### Initramfs Directory Structure

```
initramfs-build/
├── init              # Init script (PID 1)
├── bin/
│   ├── busybox       # Statically linked BusyBox
│   ├── sh → busybox
│   ├── mount → busybox
│   ├── switch_root → busybox
│   ├── cttyhack → busybox
│   ├── setsid → busybox
│   ├── sleep → busybox
│   └── mkdir → busybox
├── dev/              # Device nodes (devtmpfs mount point)
├── proc/             # Proc filesystem mount point
├── sys/              # Sysfs mount point
├── run/              # Runtime mount point
├── tmp/              # Temporary directory
└── newroot/          # Mount point for real root filesystem
```

### Init Script Behavior

The `initramfs/init` script executes the following sequence:

1. Displays the Rweezy welcome banner
2. Mounts `/proc`, `/sys`, `/dev` (kernel virtual filesystems)
3. Creates `/newroot` mount point
4. Waits 1 second for the virtio disk to become ready
5. Mounts `/dev/vda` (ext4) to `/newroot`
6. If mount fails → drops to emergency shell (`setsid cttyhack /bin/sh`)
7. Creates `/proc`, `/sys`, `/dev` directories in `/newroot`
8. Moves virtual filesystems from old root to `/newroot`
9. Executes `switch_root /newroot /init` to pivot into the real root

### Initramfs Archive Creation

```bash
cd initramfs-build
find . -print0 | cpio --null -ov --format=newc | gzip -9 > build/initramfs.cpio.gz
```

- **Format:** newc (the standard initramfs format for Linux)
- **Compression:** gzip at maximum compression level (9)
- **Typical size:** ~1.3 MB compressed

---

## Root Filesystem

The root filesystem is stored on the ext4 disk image (`disk/rweezy.img`) and contains the full Rweezy userspace.

### Directory Structure

```
rootfs/
├── init                          # Root init script (PID 1 after switch_root)
├── init.backup                   # Alternate init (no switch_root)
├── init.network                  # Alternate init with network + switch_root
├── init-realroot                 # Another switch_root variant
├── bin/
│   ├── busybox                   # Installed BusyBox binary
│   ├── sh → busybox              # Shell
│   ├── ls → busybox              # (and ~408 other applet symlinks)
│   └── ...
├── sbin/                         # System binaries (generated)
├── usr/
│   ├── bin/                      # User binaries (generated)
│   ├── sbin/                     # System binaries (generated)
│   └── share/
│       └── udhcpc/
│           └── default.script    # DHCP event handler
├── proc/                         # Mount point (created at boot)
├── sys/                          # Mount point (created at boot)
├── dev/                          # Mount point (created at boot)
├── tmp/                          # Temporary directory
├── run/                          # Runtime directory
└── var/                          # Variable data
```

### Root Init Script (`rootfs/init`)

The root init script runs after `switch_root` and performs:

1. **Network detection:** Checks if `eth0` exists via `ip link show eth0`
2. **Interface activation:** Brings up `eth0` with `ip link set eth0 up`
3. **DHCP:** Runs `udhcpc -i eth0` to obtain an IP address
4. **Identity display:** Shows `uname -a` and `cat /proc/rweezy`
5. **Shell launch:** Starts an interactive shell with `setsid cttyhack /bin/sh`

### Init Script Variants

| Script | Description | Use Case |
|--------|-------------|----------|
| `rootfs/init` | Networking + shell (active) | Default boot |
| `rootfs/init.backup` | Mounts proc/sys/dev + shell | Debugging without switch_root |
| `rootfs/init.network` | Network + switch_root | Alternate boot path |
| `rootfs/init-realroot` | switch_root variant | Alternate boot path |

---

## Boot Process (Detailed)

### Stage 1: Kernel + Initramfs

```
1. BIOS/UEFI loads kernel (build/vmlinuz) and initramfs (build/initramfs.cpio.gz)
2. Kernel initializes, extracts initramfs to rootfs
3. Kernel executes /init (initramfs/init) as PID 1
4. initramfs/init mounts /proc, /sys, /dev
5. Mounts /dev/vda (ext4) to /newroot
6. Moves virtual filesystems to /newroot
7. Executes switch_root /newroot /init
```

### Stage 2: Real Root

```
8. Kernel executes /init (rootfs/init) as PID 1 on real root
9. Detects eth0 network interface
10. Brings up eth0 and runs udhcpc for DHCP
11. Displays uname -a (kernel version)
12. Displays /proc/rweezy (Rweezy identity)
13. Launches interactive shell (setsid cttyhack /bin/sh)
```

### Visual Flow

```
Power On
  │
  ▼
BIOS/UEFI
  │
  ▼
Kernel Loading (vmlinuz + initramfs.cpio.gz)
  │
  ▼
Kernel Initialization
  │
  ▼
initramfs/init (PID 1)
  │
  ├── Mount /proc, /sys, /dev
  ├── Mount /dev/vda → /newroot (ext4)
  │     └── If fail → emergency shell
  ├── Move /proc, /sys, /dev to /newroot
  └── switch_root /newroot /init
        │
        ▼
rootfs/init (PID 1 on real root)
  │
  ├── ip link set eth0 up
  ├── udhcpc -i eth0
  ├── uname -a
  ├── cat /proc/rweezy
  └── exec setsid cttyhack /bin/sh
        │
        ▼
Interactive Shell
```

---

## Networking

### DHCP Configuration

Rweezy uses BusyBox's built-in DHCP client (`udhcpc`) with a custom event handler script.

### Default Script (`rootfs/usr/share/udhcpc/default.script`)

```sh
#!/bin/sh

case "$1" in
    deconfig)
        ip addr flush dev "$interface"
        ;;

    bound|renew)
        ip addr flush dev "$interface"
        ip addr add "$ip/${subnet:-24}" dev "$interface"

        if [ -n "$router" ]; then
            ip route del default 2>/dev/null || true
            ip route add default via "$router" dev "$interface"
        fi
        ;;
esac
```

### DHCP Events

| Event | Action |
|-------|--------|
| `deconfig` | Flushes all IP addresses from the interface |
| `bound` | Assigns the leased IP address and default gateway |
| `renew` | Replaces the IP address and updates the default gateway |

### Environment Variables Provided by udhcpc

| Variable | Description |
|----------|-------------|
| `$interface` | Network interface name (e.g., `eth0`) |
| `$ip` | Assigned IP address |
| `$subnet` | Subnet mask |
| `$router` | Default gateway |
| `$dns` | DNS server(s) |
| `$hostname` | Hostname from DHCP |
| `$lease` | Lease time in seconds |

---

## Disk Image

### Pre-built Image

- **Location:** `disk/rweezy.img`
- **Size:** 512 MB
- **Filesystem:** ext4
- **Volume label:** `RWEEZY`

### Creating a New Disk Image

```bash
# Create raw disk image
qemu-img create -f raw disk/rweezy.img 512M

# Format with ext4
mkfs.ext4 -L RWEEZY disk/rweezy.img

# Mount and populate (optional)
mkdir -p /tmp/rweezy-mount
sudo mount -o loop disk/rweezy.img /tmp/rweezy-mount
# ... copy files ...
sudo umount /tmp/rweezy-mount
```

### Partitioning (Optional)

For more complex setups, you can partition the disk image:

```bash
# Create partitioned image
qemu-img create -f raw disk/rweezy.img 512M
fdisk disk/rweezy.img  # Create single partition, type 83

# Format the partition
sudo losetup -fP disk/rweezy.img
sudo mkfs.ext4 -L RWEEZY /dev/loop0p1
```

---

## Custom Kernel Module

### `/proc/rweezy` Interface

**Source:** `src/linux/fs/proc/rweezy.c`

This kernel module creates a read-only entry at `/proc/rweezy` that exposes the following information:

```
Rweezy OS
Kernel: 7.2.0-rweezy-08dbfad3f504
Rweezy ABI: 1
Build: #1 SMP PREEMPT_DYNAMIC Mon Aug 31 2026
```

### Implementation Details

```c
static int rweezy_proc_show(struct seq_file *m, void *v)
{
    seq_puts(m, "Rweezy OS\n");
    seq_printf(m, "Kernel: %s\n", utsname()->release);
    seq_puts(m, "Rweezy ABI: 1\n");
    seq_printf(m, "Build: %s\n", utsname()->version);
    return 0;
}
```

- Uses `proc_create_single()` for a simple read-only proc entry
- Calls `pde_make_permanent()` to prevent the entry from being removed
- Registered via `fs_initcall()` (called during filesystem initialization)

### Kconfig Option

```
config RWEEZY
    bool "Rweezy OS identity interface (/proc/rweezy)"
    depends on PROC_FS
    default n
    help
      Provides a read-only /proc/rweezy file that exposes Rweezy OS
      identity information including kernel release, ABI version, and
      build identity.
```

### Build Integration

In `src/linux/fs/proc/Makefile`:
```makefile
proc-$(CONFIG_RWEEZY) += rweezy.o
```

---

## Configuration Reference

### Kernel Configuration (`src/linux/.config`)

#### Critical Options

| Option | Value | Description |
|--------|-------|-------------|
| `CONFIG_64BIT` | y | 64-bit kernel |
| `CONFIG_X86_64` | y | x86_64 architecture |
| `CONFIG_SMP` | y | Symmetric multiprocessing |
| `CONFIG_KVM_GUEST` | y | KVM paravirtualization |
| `CONFIG_VIRTIO` | y | Virtio subsystem |
| `CONFIG_VIRTIO_BLK` | y | Virtio block device |
| `CONFIG_VIRTIO_NET` | y | Virtio network device |
| `CONFIG_SCSI_VIRTIO` | y | Virtio SCSI |
| `CONFIG_EXT4_FS` | y | ext4 filesystem |
| `CONFIG_BLK_DEV_INITRD` | y | initramfs support |
| `CONFIG_RWEEZY` | y | Rweezy identity interface |
| `CONFIG_NET` | y | Networking |
| `CONFIG_INET` | y | IPv4 |
| `CONFIG_IPV6` | y | IPv6 |
| `CONFIG_HZ_1000` | y | 1000 Hz tick rate |
| `CONFIG_PREEMPT_LAZY` | y | Preemptible kernel |
| `CONFIG_MODULES` | y | Loadable modules |
| `CONFIG_EFI` | y | EFI boot |
| `CONFIG_SATA_AHCI` | y | SATA AHCI |

### BusyBox Configuration (`src/busybox/.config`)

#### Critical Options

| Option | Value | Description |
|--------|-------|-------------|
| `CONFIG_STATIC` | y | Statically linked |
| `CONFIG_CROSS_COMPILER_PREFIX` | "" | Native compilation |
| `CONFIG_PREFIX` | (set at build) | Install prefix |
| `CONFIGASH` | y | ash shell |
| `CONFIG_FEATURE_SH_MATH` | y | Shell math support |
| `CONFIG_FEATURE_SH_ESCAPED_N` | y | Escaped newlines |

---

## QEMU Usage

### Basic Boot

```bash
qemu-system-x86_64 \
  -kernel build/vmlinuz \
  -initrd build/initramfs.cpio.gz \
  -drive file=disk/rweezy.img,format=raw,if=virtio \
  -append "root=/dev/vda rw" \
  -m 512M
```

### With Networking

```bash
qemu-system-x86_64 \
  -kernel build/vmlinuz \
  -initrd build/initramfs.cpio.gz \
  -drive file=disk/rweezy.img,format=raw,if=virtio \
  -netdev user,id=net0 \
  -device virtio-net-pci,netdev=net0 \
  -append "root=/dev/vda rw" \
  -m 512M
```

### With Serial Console (Headless)

```bash
qemu-system-x86_64 \
  -kernel build/vmlinuz \
  -initrd build/initramfs.cpio.gz \
  -drive file=disk/rweezy.img,format=raw,if=virtio \
  -append "root=/dev/vda rw console=ttyS0" \
  -nographic \
  -m 512M
```

### QEMU Options Reference

| Option | Description |
|--------|-------------|
| `-kernel` | Path to the kernel image |
| `-initrd` | Path to the initramfs |
| `-drive` | Disk image with virtio interface |
| `-append` | Kernel command line arguments |
| `-m` | Amount of RAM (e.g., `512M`, `1G`) |
| `-netdev user` | User-mode networking (NAT) |
| `-device virtio-net-pci` | Virtio network device |
| `-nographic` | Disable graphical output |
| `-serial mon:stdio` | Redirect serial console to terminal |
| `-smp` | Number of CPUs (e.g., `-smp 4`) |
| `-enable-kvm` | Enable KVM acceleration (if available) |

### Performance Optimization

```bash
# With KVM acceleration (requires KVM support)
qemu-system-x86_64 \
  -kernel build/vmlinuz \
  -initrd build/initramfs.cpio.gz \
  -drive file=disk/rweezy.img,format=raw,if=virtio \
  -append "root=/dev/vda rw" \
  -enable-kvm \
  -smp 4 \
  -m 1G
```

---

## Troubleshooting

### Kernel doesn't boot

- Verify the kernel image exists: `ls -lh build/vmlinuz`
- Check QEMU command line for correct paths
- Ensure `root=/dev/vda rw` is in the `-append` argument
- Try adding `console=ttyS0 console=tty0` for more output

### Root filesystem fails to mount

- Verify the disk image exists: `ls -lh disk/rweezy.img`
- Check the disk image is valid: `file disk/rweezy.img`
- Ensure the disk is formatted as ext4: `blkid disk/rweezy.img`
- The init script will drop to an emergency shell on failure

### Network doesn't come up

- Verify QEMU includes a network device (`-netdev user` + `-device virtio-net-pci`)
- Check if `eth0` exists: `ip link show`
- Try manual DHCP: `udhcpc -i eth0`
- Check the DHCP script: `cat /usr/share/udhcpc/default.script`

### /proc/rweezy not found

- Ensure `CONFIG_RWEEZY=y` in the kernel config
- Rebuild the kernel after changing the config
- Check the kernel version includes `-rweezy` suffix

### Build fails

- Ensure all dependencies are installed (gcc, make, cpio, gzip)
- Check that source trees exist in `src/linux/` and `src/busybox/`
- Verify sufficient disk space (2+ GB)
- Check compiler output for specific errors

---

## Development Guide

### Making Changes

#### Kernel Modifications

1. Edit source files in `src/linux/`
2. Modify kernel config: `cd src/linux && make menuconfig`
3. Rebuild: `cd src/linux && make -j$(nproc)`
4. Copy new kernel: `cp src/linux/arch/x86/boot/bzImage build/vmlinuz`

#### BusyBox Modifications

1. Edit source files in `src/busybox/`
2. Modify config: `cd src/busybox && make menuconfig`
3. Rebuild: `cd src/busybox && make -j$(nproc)`
4. Reinstall: `cd src/busybox && make CONFIG_PREFIX=../rootfs install`

#### Init Script Changes

1. Edit `initramfs/init` (stage 1) or `rootfs/init` (stage 2)
2. Rebuild initramfs: `./build.sh` (runs steps 4-5 only if kernel/BusyBox unchanged)

#### Root Filesystem Changes

1. Modify files in `rootfs/`
2. Note: `rootfs/bin/`, `rootfs/sbin/`, `rootfs/usr/` are generated by BusyBox install
3. Custom files (like `rootfs/usr/share/udhcpc/default.script`) persist across rebuilds

### Testing Changes

The primary testing method is booting in QEMU:

```bash
# Quick rebuild and test
./build.sh && qemu-system-x86_64 \
  -kernel build/vmlinuz \
  -initrd build/initramfs.cpio.gz \
  -drive file=disk/rweezy.img,format=raw,if=virtio \
  -append "root=/dev/vda rw" \
  -m 512M
```

### Git Workflow

```bash
# Check status
git status

# Stage changes
git add <files>

# Commit
git commit -m "Description of changes"

# View log
git log --oneline
```

### Adding New Features

1. **New kernel module:** Add source to `src/linux/`, update `Kconfig` and `Makefile`
2. **New BusyBox applet:** Enable in `src/busybox/.config` via `make menuconfig`
3. **New init script variant:** Create in `rootfs/` with a descriptive name
4. **New userspace tool:** Add to `rootfs/` or enable in BusyBox config

---

## Directory Reference

| Directory | Description | Generated |
|-----------|-------------|-----------|
| `build/` | Final build outputs | Yes |
| `disk/` | Bootable disk images | Partial |
| `docs/` | Documentation | No |
| `initramfs/` | Initramfs source templates | No |
| `initramfs-build/` | Initramfs staging tree | Yes |
| `iso/` | ISO image output (reserved) | — |
| `kernel/` | Saved kernel configs | No |
| `rootfs/` | Root filesystem overlay | Partial |
| `scripts/` | Helper scripts (reserved) | — |
| `src/linux/` | Linux kernel source | No |
| `src/busybox/` | BusyBox source | No |
