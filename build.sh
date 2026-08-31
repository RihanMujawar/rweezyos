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
    if [ -f "$ROOT/kernel/rweezy.patch" ] && \
      { ! grep -q "CONFIG_RWEEZY" "$KERNEL/fs/proc/Kconfig" 2>/dev/null || \
        ! grep -q "rweezy.o" "$KERNEL/fs/proc/Makefile" 2>/dev/null || \
        [ ! -f "$KERNEL/fs/proc/rweezy.c" ]; }; then
      patch -p1 -d "$KERNEL" < "$ROOT/kernel/rweezy.patch"
    fi

    if [ -f "$ROOT/src/linux/localversion-rweezy" ] && [ ! -f "$KERNEL/localversion-rweezy" ]; then
      cp "$ROOT/src/linux/localversion-rweezy" "$KERNEL/localversion-rweezy"
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
  fi

  if [ -f "$ROOT/kernel/rweezy.patch" ]; then
    patch -p1 -d "$KERNEL" < "$ROOT/kernel/rweezy.patch"
  fi

  if [ -f "$ROOT/src/linux/localversion-rweezy" ] && [ ! -f "$KERNEL/localversion-rweezy" ]; then
    cp "$ROOT/src/linux/localversion-rweezy" "$KERNEL/localversion-rweezy"
  fi
}

bootstrap_busybox() {
  if [ -f "$BUSYBOX/Makefile" ]; then
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
echo "Rweezy build finished successfully!"
