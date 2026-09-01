#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"

KERNEL="$ROOT/src/linux"
BUSYBOX="$ROOT/src/busybox"
ROOTFS="$ROOT/rootfs"

INITRAMFS_SRC="$ROOT/initramfs"
INITRAMFS_BUILD="$ROOT/initramfs-build"

BUILD="$ROOT/build"

download_with_fallback() {
  local output_path="$1"
  shift

  rm -f "$output_path"

  local url
  for url in "$@"; do
    echo "[download] Trying $url"
    if curl -fL --retry 3 --retry-all-errors --retry-delay 2 \
      --connect-timeout 20 --max-time 600 --http1.1 \
      --proto '=https' --tlsv1.2 -o "$output_path" "$url"; then
      return 0
    fi
    rm -f "$output_path"
  done

  echo "[download] ERROR: failed to download from all configured URLs" >&2
  return 1
}

bootstrap_linux() {
  if [ -f "$KERNEL/Makefile" ]; then
    # The fs/proc/Makefile must NEVER contain C code. If `.orig` backups exist,
    # rebuild a pristine Makefile, then append our single rweezy line.
    if [ -f "$KERNEL/fs/proc/Makefile.orig" ]; then
      cp "$KERNEL/fs/proc/Makefile.orig" "$KERNEL/fs/proc/Makefile"
      if ! grep -q "CONFIG_RWEEZY" "$KERNEL/fs/proc/Makefile" 2>/dev/null; then
        printf '\nproc-$(CONFIG_RWEEZY)\t+= rweezy.o\n' >> "$KERNEL/fs/proc/Makefile"
      fi
    fi
    rm -f "$KERNEL/fs/proc/Makefile.rej"

    if [ -f "$ROOT/kernel/rweezy.c" ]; then
      cp "$ROOT/kernel/rweezy.c" "$KERNEL/fs/proc/rweezy.c"
    fi

    # Ensure Kconfig carries the RWEEZY option.
    if ! grep -q "^config RWEEZY" "$KERNEL/fs/proc/Kconfig" 2>/dev/null; then
      if [ -f "$ROOT/kernel/rweezy.patch" ]; then
        # Apply only the Kconfig (and new-file) hunks; the Makefile hunk is
        # handled directly above because its context does not match.
        patch -p1 --forward -d "$KERNEL" \
          -F3 -N < "$ROOT/kernel/rweezy.patch" >/dev/null 2>&1 || true
        rm -f "$KERNEL/fs/proc/Makefile.rej"
      fi
      if ! grep -q "^config RWEEZY" "$KERNEL/fs/proc/Kconfig" 2>/dev/null; then
        if [ -f "$ROOT/kernel/rweezy-Kconfig" ]; then
          cat "$ROOT/kernel/rweezy-Kconfig" >> "$KERNEL/fs/proc/Kconfig"
        fi
      fi
    fi

    # Defensive: re-guard the Makefile after any patch activity.
    if ! grep -q "CONFIG_RWEEZY" "$KERNEL/fs/proc/Makefile" 2>/dev/null; then
      printf '\nproc-$(CONFIG_RWEEZY)\t+= rweezy.o\n' >> "$KERNEL/fs/proc/Makefile"
    fi
    rm -f "$KERNEL/fs/proc/Makefile.rej"

    if [ -f "$ROOT/src/linux/localversion-rweezy" ] && [ ! -f "$KERNEL/localversion-rweezy" ]; then
      cp "$ROOT/src/linux/localversion-rweezy" "$KERNEL/localversion-rweezy"
    fi
    if [ -f "$KERNEL/.config" ]; then
      (cd "$KERNEL" && make olddefconfig)
    fi
    return 0
  fi

  mkdir -p "$ROOT/src"
  local tarball="$ROOT/src/linux-7.2.tar.xz"
  echo "[bootstrap] Downloading Linux 7.2 source..."
  download_with_fallback "$tarball" \
    "https://cdn.kernel.org/pub/linux/kernel/v7.x/linux-7.2.tar.xz" \
    "https://mirrors.edge.kernel.org/pub/linux/kernel/v7.x/linux-7.2.tar.xz"

  rm -rf "$KERNEL"
  tar -xf "$tarball" -C "$ROOT/src"
  local extracted="$(tar -tf "$tarball" | head -n 1 | cut -d/ -f1)"
  mv "$ROOT/src/$extracted" "$KERNEL"

  if [ -f "$ROOT/kernel/rweezy.config" ]; then
    cp "$ROOT/kernel/rweezy.config" "$KERNEL/.config"
    (cd "$KERNEL" && make olddefconfig)
  fi

  # Apply Rweezy customizations deterministically (do not rely on the malformed
  # rweezy.patch Makefile hunk, which does not match this kernel's Makefile).
  if [ -f "$ROOT/kernel/rweezy.patch" ]; then
    # Try a fuzz-tolerant forward-only patch for Kconfig + new-file hunks.
    patch -p1 --forward -d "$KERNEL" -F3 -N < "$ROOT/kernel/rweezy.patch" >/dev/null 2>&1 || true
    rm -f "$KERNEL/fs/proc/Makefile.rej"
  fi

  # Ensure rweezy.c exists
  if [ ! -f "$KERNEL/fs/proc/rweezy.c" ] && [ -f "$ROOT/kernel/rweezy.c" ]; then
    cp "$ROOT/kernel/rweezy.c" "$KERNEL/fs/proc/rweezy.c"
  fi

  # Ensure Kconfig carries the RWEEZY option
  if ! grep -q "^config RWEEZY" "$KERNEL/fs/proc/Kconfig" 2>/dev/null; then
    if [ -f "$ROOT/kernel/rweezy-Kconfig" ]; then
      cp "$KERNEL/fs/proc/Kconfig" "$KERNEL/fs/proc/Kconfig.orig"
      cp "$KERNEL/fs/proc/Makefile" "$KERNEL/fs/proc/Makefile.orig"
      cat "$ROOT/kernel/rweezy-Kconfig" >> "$KERNEL/fs/proc/Kconfig"
    fi
  fi

  # Ensure Makefile has rweezy.o entry
  if ! grep -q "CONFIG_RWEEZY" "$KERNEL/fs/proc/Makefile" 2>/dev/null; then
    printf '\nproc-$(CONFIG_RWEEZY)\t+= rweezy.o\n' >> "$KERNEL/fs/proc/Makefile"
  fi

  rm -f "$KERNEL/fs/proc/Makefile.rej"

  if [ -f "$ROOT/src/linux/localversion-rweezy" ] && [ ! -f "$KERNEL/localversion-rweezy" ]; then
    cp "$ROOT/src/linux/localversion-rweezy" "$KERNEL/localversion-rweezy"
  fi
}

bootstrap_busybox() {
  if [ -f "$BUSYBOX/Makefile" ]; then
    # Ensure the TC applet stays disabled on existing trees as well.
    if grep -q "^CONFIG_TC=y" "$BUSYBOX/.config" 2>/dev/null; then
      sed -i 's/^CONFIG_TC=y$/# CONFIG_TC is not set/' "$BUSYBOX/.config"
      (cd "$BUSYBOX" && make oldconfig >/dev/null 2>&1 || true)
    fi
    return 0
  fi

  mkdir -p "$ROOT/src"
  local tarball="$ROOT/src/busybox-1.38.0.tar.bz2"
  echo "[bootstrap] Downloading BusyBox 1.38.0 source..."
  download_with_fallback "$tarball" \
    "https://busybox.net/downloads/busybox-1.38.0.tar.bz2" \
    "https://www.busybox.net/downloads/busybox-1.38.0.tar.bz2"

  rm -rf "$BUSYBOX"
  tar -xf "$tarball" -C "$ROOT/src"
  local extracted="$(tar -tjf "$tarball" | head -n 1 | cut -d/ -f1)"
  mv "$ROOT/src/$extracted" "$BUSYBOX"

  (cd "$BUSYBOX" && make defconfig >/dev/null)
  if [ -f "$BUSYBOX/scripts/config" ]; then
    (cd "$BUSYBOX" && scripts/config --enable STATIC >/dev/null)
  else
    sed -i 's/^# CONFIG_STATIC is not set$/CONFIG_STATIC=y/' "$BUSYBOX/.config"
  fi
  # The tc applet requires CBQ constants that were removed from modern
  # kernel UAPI headers, so it cannot be compiled. Disable it.
  sed -i 's/^CONFIG_TC=y$/# CONFIG_TC is not set/' "$BUSYBOX/.config"
  (cd "$BUSYBOX" && make oldconfig >/dev/null 2>&1 || true)
}

echo "================================"
echo "       Rweezy Build System"
echo "================================"

mkdir -p "$BUILD"
bootstrap_linux
bootstrap_busybox

if [ ! -d "$ROOTFS" ]; then
  mkdir -p "$ROOTFS"
fi

echo
echo "[1/5] Building Linux kernel..."
cd "$KERNEL"
make -j"$(nproc)"
cp arch/x86/boot/bzImage "$BUILD/vmlinuz"

echo
echo "[2/5] Building BusyBox..."
cd "$BUSYBOX"
make -j"$(nproc)"

echo
echo "[3/5] Preparing root filesystem..."
make CONFIG_PREFIX="$ROOTFS" install

echo
echo "[4/5] Preparing initramfs..."

# Clean previously generated initramfs
rm -rf "$INITRAMFS_BUILD"

# Create temporary initramfs structure
mkdir -p "$INITRAMFS_BUILD"/{bin,dev,proc,sys,run,tmp,newroot}

# Copy BusyBox
cp "$ROOTFS/bin/busybox" "$INITRAMFS_BUILD/bin/busybox"

# Required BusyBox applets
ln -sf busybox "$INITRAMFS_BUILD/bin/sh"
ln -sf busybox "$INITRAMFS_BUILD/bin/mount"
ln -sf busybox "$INITRAMFS_BUILD/bin/switch_root"
ln -sf busybox "$INITRAMFS_BUILD/bin/cttyhack"
ln -sf busybox "$INITRAMFS_BUILD/bin/setsid"
ln -sf busybox "$INITRAMFS_BUILD/bin/sleep"
ln -sf busybox "$INITRAMFS_BUILD/bin/mkdir"

# Copy temporary initramfs init
cp "$INITRAMFS_SRC/init" "$INITRAMFS_BUILD/init"
chmod +x "$INITRAMFS_BUILD/init"

echo
echo "[5/5] Creating initramfs..."

cd "$INITRAMFS_BUILD"

find . -print0 | cpio --null -ov --format=newc | gzip -9 > "$BUILD/initramfs.cpio.gz"

echo
echo "[6/6] Creating root disk image..."

DISK_DIR="$ROOT/disk"
DISK_IMG="$DISK_DIR/rweezy.img"
DISK_SIZE=512M

mkdir -p "$DISK_DIR"

# The disk image is a build artifact: recreate it fresh every build so the
# contents always match the current rootfs (debugfs cannot overwrite links).
echo "[disk] Creating $DISK_IMG (${DISK_SIZE})..."
qemu-img create -f raw "$DISK_IMG" "$DISK_SIZE" >/dev/null
mkfs.ext4 -q -L RWEEZY "$DISK_IMG"

if command -v debugfs >/dev/null 2>&1; then
  echo "[disk] Populating root filesystem into disk image (debugfs)..."
  DEBUGFS_CMDS="$ROOT/build/debugfs.cmds"
  rm -f "$DEBUGFS_CMDS"

  {
    printf 'mkdir /bin\nmkdir /sbin\nmkdir /usr\nmkdir /usr/sbin\nmkdir /usr/bin\nmkdir /etc\nmkdir /proc\nmkdir /sys\nmkdir /dev\nmkdir /tmp\nmkdir /run\nmkdir /var\nmkdir /newroot\n'
    # Copy the BusyBox binary.
    if [ -f "$ROOTFS/bin/busybox" ]; then
      printf 'write %s /bin/busybox\n' "$ROOTFS/bin/busybox"
    fi
    # Copy the installed busybox applet symlinks.
    for link in "$ROOTFS"/bin/* "$ROOTFS"/sbin/* "$ROOTFS"/usr/bin/* "$ROOTFS"/usr/sbin/*; do
      [ -L "$link" ] || continue
      name="$(basename "$link")"
      rel="${link#$ROOTFS/}"
      dir="$(dirname "$rel")"
      case "$dir" in
        bin)        target="busybox" ;;
        sbin)       target="../bin/busybox" ;;
        usr/bin)    target="../../bin/busybox" ;;
        usr/sbin)   target="../../bin/busybox" ;;
      esac
      printf 'cd /%s\nsymlink %s %s\n' "$dir" "$name" "$target"
    done
    # Install the root init script as /init.
    if [ -f "$ROOTFS/init" ]; then
      printf 'cd /\nwrite %s /init\n' "$ROOTFS/init"
    fi
    printf 'quit\n'
  } > "$DEBUGFS_CMDS"

  debugfs -w -f "$DEBUGFS_CMDS" "$DISK_IMG" >/dev/null 2>&1
  echo "[disk] Disk image populated: $DISK_IMG"
else
  echo "[disk] NOTE: debugfs not found. Create and populate the disk manually:"
  echo "        qemu-img create -f raw $DISK_IMG $DISK_SIZE"
  echo "        mkfs.ext4 -L RWEEZY $DISK_IMG"
fi

# e2fsck to keep the image clean before booting.
if command -v e2fsck >/dev/null 2>&1; then
  e2fsck -fy "$DISK_IMG" >/dev/null 2>&1 || true
fi

echo
echo "================================"
echo "       Build complete!"
echo "================================"

echo
echo "Kernel:"
ls -lh "$BUILD/vmlinuz"

echo
echo "Initramfs:"
ls -lh "$BUILD/initramfs.cpio.gz"

echo
echo "Disk image:"
ls -lh "$DISK_IMG"

echo
echo "Rweezy build finished successfully!"
