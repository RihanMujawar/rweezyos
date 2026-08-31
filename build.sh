#!/bin/bash
set -e

ROOT="$(cd "$(dirname "$0")" && pwd)"

KERNEL="$ROOT/src/linux"
BUSYBOX="$ROOT/src/busybox"
ROOTFS="$ROOT/rootfs"

INITRAMFS_SRC="$ROOT/initramfs"
INITRAMFS_BUILD="$ROOT/initramfs-build"

BUILD="$ROOT/build"

echo "================================"
echo "       Rweezy Build System"
echo "================================"

mkdir -p "$BUILD"

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
