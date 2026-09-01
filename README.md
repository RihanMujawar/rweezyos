# Rweezy OS

A minimal, from-scratch Linux distribution built from source. Rweezy OS compiles a custom Linux kernel with a proprietary identity interface, bundles BusyBox as the userspace, and boots into a fully functional virtual machine with networking support.

## Features

- **Custom Linux Kernel 7.2.0** with the `-rweezy` local version suffix
- **`/proc/rweezy` kernel interface** — a read-only proc entry exposing OS identity, kernel version, ABI version, and build string
- **BusyBox 1.38.0 userspace** — statically linked, ~408 applets (shell, coreutils, networking, init)
- **Two-stage boot** — initramfs with `switch_root` into a real ext4 root filesystem
- **Networking** — automatic DHCP via `udhcpc` with a custom DHCP event handler
- **Emergency shell** — drops to an interactive shell if the root filesystem fails to mount
- **KVM/QEMU optimized** — virtio drivers, designed for virtual machine deployment

## Prerequisites

- Linux host (x86_64)
- GCC (15.x or compatible)
- GNU Make
- `cpio` and `gzip`
- `nproc` (coreutils)
- Sufficient disk space (~2 GB for source trees and build artifacts)

## Quick Start

### 1. Clone the repository

```bash
git clone https://github.com/RihanMujawar/rweezyos.git
cd rweezyos
```

### 2. Build

```bash
chmod +x build.sh
./build.sh
```

This runs six steps:

| Step | Description |
|------|-------------|
| 1/6 | Compiles the Linux kernel and copies `bzImage` to `build/vmlinuz` |
| 2/6 | Compiles BusyBox |
| 3/6 | Installs BusyBox into the root filesystem |
| 4/6 | Prepares the initramfs staging tree with required symlinks |
| 5/6 | Creates the compressed initramfs (`build/initramfs.cpio.gz`) |
| 6/6 | Creates and populates the ext4 root disk image (`disk/rweezy.img`) |

### 3. Boot in QEMU

```bash
qemu-system-x86_64 \
  -kernel build/vmlinuz \
  -initrd build/initramfs.cpio.gz \
  -drive file=disk/rweezy.img,format=raw,if=virtio \
  -append "root=/dev/vda rw" \
  -m 512M
```

Once booted, you'll see the Rweezy welcome banner, network initialization, kernel identity info, and an interactive shell.

> **Note:** The disk image is regenerated from scratch on every build so it
> always matches the freshly built root filesystem.

## Project Structure

```
rweezy/
├── build.sh                 # Main build script
├── build/                   # Build outputs (generated)
│   ├── vmlinuz              # Compiled kernel image
│   ├── initramfs.cpio.gz    # Compressed initramfs
│   └── debugfs.cmds         # debugfs script used to populate the disk image
├── disk/
│   └── rweezy.img           # 512 MB ext4 root disk image (regenerated per build)
├── initramfs/
│   └── init                 # Initramfs init script (switch_root)
├── initramfs-build/         # Initramfs staging tree (generated)
├── kernel/
│   ├── rweezy.config        # Saved kernel .config
│   ├── rweezy.patch         # Kernel patch (Kconfig + rweezy.c)
│   ├── rweezy-Kconfig       # Standalone RWEEZY Kconfig snippet
│   └── rweezy.c             # /proc/rweezy kernel module source
├── rootfs/
│   ├── init                 # Root filesystem init (networking + shell)
│   ├── init.backup          # Alternate init variant
│   ├── init.network         # Alternate init with network + switch_root
│   ├── init-realroot        # Another switch_root variant
│   ├── bin/busybox          # Installed BusyBox binary
│   └── usr/share/udhcpc/
│       └── default.script   # DHCP event handler script
└── src/
    ├── linux/               # Linux kernel 7.2.0 source (with Rweezy patches)
    └── busybox/             # BusyBox 1.38.0 source
```

## Boot Process

```
BIOS/UEFI → Kernel (vmlinuz) → initramfs/init
  │
  ├── Mounts /proc, /sys, /dev
  ├── Mounts /dev/vda (ext4) to /newroot
  ├── Moves virtual filesystems to /newroot
  └── switch_root /newroot /init
        │
        ├── Detects eth0, brings up networking
        ├── Runs udhcpc for DHCP
        ├── Displays uname -a and /proc/rweezy
        └── Launches interactive shell (setsid cttyhack /bin/sh)
```

## Custom Kernel Module: `/proc/rweezy`

The kernel includes a custom proc entry at `/proc/rweezy` that outputs:

```
Rweezy OS
Kernel: 7.2.0-rweezy-<git-hash>
Rweezy ABI: 1
Build: <kernel build string>
```

Source: `src/linux/fs/proc/rweezy.c`

To disable, set `CONFIG_RWEEZY=n` in the kernel config.

## Networking

Rweezy uses BusyBox `udhcpc` for DHCP. When the system boots:

1. The `eth0` interface is detected and brought up
2. `udhcpc` requests an IP address from the DHCP server
3. The custom `default.script` handles IP assignment and default gateway configuration

To use networking in QEMU, add a user-mode network device:

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

## Disk Image

`build.sh` automatically creates a 512 MB ext4 disk image at `disk/rweezy.img`
(label `RWEEZY`) and populates it with the BusyBox binary, its applet symlinks,
and the `rootfs/init` script using `debugfs` — no root access required. The
image is rebuilt from scratch on every build.

To create/format it manually instead:

```bash
qemu-img create -f raw disk/rweezy.img 512M
mkfs.ext4 -L RWEEZY disk/rweezy.img
```

## Kernel Configuration

Key kernel options in `src/linux/.config`:

| Option | Value | Description |
|--------|-------|-------------|
| `CONFIG_64BIT` | y | 64-bit kernel |
| `CONFIG_KVM_GUEST` | y | KVM virtual machine guest support |
| `CONFIG_VIRTIO_BLK` | y | Virtio block device driver |
| `CONFIG_SCSI_VIRTIO` | y | Virtio SCSI driver |
| `CONFIG_EXT4_FS` | y | ext4 filesystem support |
| `CONFIG_BLK_DEV_INITRD` | y | Initial RAM filesystem support |
| `CONFIG_RWEEZY` | y | Rweezy OS identity interface |
| `CONFIG_HZ_1000` | y | 1000 Hz tick rate |
| `CONFIG_PREEMPT_LAZY` | y | Preemptible kernel |
| `CONFIG_NET` | y | Networking support |

## BusyBox Configuration

- **Static linking** (`CONFIG_STATIC=y`) — no external library dependencies
- **891 applets enabled** out of the full BusyBox set
- **408 symlinks** generated during install
- Custom install prefix: the project root filesystem

## Available Init Scripts

The project includes multiple init script variants:

| File | Purpose |
|------|---------|
| `initramfs/init` | Initramfs init — mounts root and `switch_root` |
| `rootfs/init` | Active root init — networking + interactive shell |
| `rootfs/init.backup` | Backup init — mounts proc/sys/dev + shell (no switch_root) |
| `rootfs/init.network` | Alternate init with networking + switch_root |
| `rootfs/init-realroot` | Another switch_root variant |

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/my-feature`)
3. Commit your changes (`git commit -m "Add my feature"`)
4. Push to the branch (`git push origin feature/my-feature`)
5. Open a Pull Request

## Author

**Rehan Mujawar** — [rehan.learning@hotmail.com](mailto:rehan.learning@hotmail.com)

## License

This project does not currently include a license file. Please contact the author for usage terms.
