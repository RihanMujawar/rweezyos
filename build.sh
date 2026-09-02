#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

KERNEL="$ROOT/src/linux"
BUSYBOX="$ROOT/src/busybox"
ROOTFS="$ROOT/rootfs"

INITRAMFS_SRC="$ROOT/initramfs"
INITRAMFS_BUILD="$ROOT/initramfs-build"

BUILD="$ROOT/build"
DISK_DIR="$ROOT/disk"

KERNEL_TARBALL="$ROOT/src/linux-7.2.tar.xz"
BUSYBOX_TARBALL="$ROOT/src/busybox-1.38.0.tar.bz2"

DISK_IMG="$DISK_DIR/rweezy.img"

JOBS="${JOBS:-$(nproc)}"

# ------------------------------------------------------------
# Helpers
# ------------------------------------------------------------

log() {
    echo "[rweezy] $*"
}

ok() {
    echo "[OK] $*"
}

warn() {
    echo "[WARNING] $*" >&2
}

die() {
    echo "[ERROR] $*" >&2
    exit 1
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || \
        die "Required command not found: $1"
}

# ------------------------------------------------------------
# Host dependency checks
# ------------------------------------------------------------

check_dependencies() {
    log "Checking host dependencies..."

    local tools=(
        curl
        tar
        patch
        make
        gcc
        ld
        bison
        flex
        cpio
        gzip
        mkfs.ext4
        truncate
        sed
        grep
        find
    )

    for tool in "${tools[@]}"; do
        require_command "$tool"
    done

    ok "Host dependencies available"
}

# ------------------------------------------------------------
# Download helper
# ------------------------------------------------------------

download_with_fallback() {
    local output_path="$1"
    shift

    mkdir -p "$(dirname "$output_path")"

    local url

    for url in "$@"; do
        echo "[download] Trying $url"

        rm -f "$output_path"

        if curl -fL \
            --retry 5 \
            --retry-all-errors \
            --retry-delay 2 \
            --connect-timeout 20 \
            --max-time 0 \
            --http1.1 \
            --proto '=https' \
            --tlsv1.2 \
            -o "$output_path" \
            "$url"; then

            if [ -s "$output_path" ]; then
                ok "Downloaded $(basename "$output_path")"
                return 0
            fi
        fi

        warn "Download failed: $url"
    done

    die "Failed to download: $(basename "$output_path")"
}

# ------------------------------------------------------------
# Kernel bootstrap
# ------------------------------------------------------------

bootstrap_linux() {
    mkdir -p "$ROOT/src"

    # --------------------------------------------------------
    # Existing kernel
    # --------------------------------------------------------

    if [ -f "$KERNEL/Makefile" ]; then
        log "Existing Linux kernel source detected."

    else
        log "Linux kernel source not found."
        log "Downloading Linux 7.2 source..."

        download_with_fallback "$KERNEL_TARBALL" \
            "https://cdn.kernel.org/pub/linux/kernel/v7.x/linux-7.2.tar.xz" \
            "https://mirrors.edge.kernel.org/pub/linux/kernel/v7.x/linux-7.2.tar.xz"

        rm -rf "$KERNEL"

        tar -xf "$KERNEL_TARBALL" -C "$ROOT/src"

        local extracted
        extracted="$(tar -tf "$KERNEL_TARBALL" | head -n 1 | cut -d/ -f1)"

        [ -d "$ROOT/src/$extracted" ] || \
            die "Kernel archive extraction failed."

        mv "$ROOT/src/$extracted" "$KERNEL"

        ok "Linux source extracted"
    fi

    [ -f "$KERNEL/Makefile" ] || \
        die "Invalid kernel source tree: $KERNEL"

    # --------------------------------------------------------
    # Apply Rweezy kernel patch
    # --------------------------------------------------------

    if [ -f "$ROOT/kernel/rweezy.patch" ]; then

        log "Checking Rweezy kernel patch..."

        if grep -q "config RWEEZY" "$KERNEL/fs/proc/Kconfig" 2>/dev/null && \
           grep -q "rweezy.o" "$KERNEL/fs/proc/Makefile" 2>/dev/null && \
           [ -f "$KERNEL/fs/proc/rweezy.c" ]; then

            ok "Rweezy kernel patch already applied"

        else
            log "Applying Rweezy kernel patch..."

            (
                cd "$KERNEL"

                patch -p1 < "$ROOT/kernel/rweezy.patch"
            ) || die "Rweezy kernel patch failed."

            ok "Rweezy kernel patch applied"
        fi

    else
        warn "No kernel/rweezy.patch found."
    fi

    # --------------------------------------------------------
    # Safety checks for Rweezy files
    # --------------------------------------------------------

    if [ ! -f "$KERNEL/fs/proc/rweezy.c" ] && \
       [ -f "$ROOT/kernel/rweezy.c" ]; then

        log "Installing rweezy.c..."

        cp "$ROOT/kernel/rweezy.c" \
           "$KERNEL/fs/proc/rweezy.c"
    fi

    if [ ! -f "$KERNEL/fs/proc/rweezy.c" ]; then
        die "Rweezy proc implementation not found."
    fi

    if ! grep -q "rweezy.o" "$KERNEL/fs/proc/Makefile" 2>/dev/null; then
        log "Adding Rweezy object to proc Makefile..."

        printf '%s\n' \
            'proc-$(CONFIG_RWEEZY) += rweezy.o' \
            >> "$KERNEL/fs/proc/Makefile"
    fi

    # --------------------------------------------------------
    # Kernel version suffix
    # --------------------------------------------------------

    printf '%s\n' "-rweezy" > "$KERNEL/localversion-rweezy"

    # --------------------------------------------------------
    # Kernel configuration
    # --------------------------------------------------------

    if [ -f "$ROOT/kernel/rweezy.config" ]; then

        log "Installing Rweezy kernel configuration..."

        cp "$ROOT/kernel/rweezy.config" \
           "$KERNEL/.config"

    elif [ ! -f "$KERNEL/.config" ]; then

        log "No kernel configuration found."
        log "Generating default x86_64 configuration..."

        (
            cd "$KERNEL"

            make x86_64_defconfig
        )
    fi

    log "Updating kernel configuration..."

    (
        cd "$KERNEL"

        make olddefconfig
    )

    ok "Kernel configuration ready"
}

# ------------------------------------------------------------
# BusyBox bootstrap
# ------------------------------------------------------------

bootstrap_busybox() {

    if [ -f "$BUSYBOX/Makefile" ]; then
        log "Existing BusyBox source detected."
        return 0
    fi

    mkdir -p "$ROOT/src"

    log "BusyBox source not found."
    log "Downloading BusyBox 1.38.0..."

    download_with_fallback "$BUSYBOX_TARBALL" \
        "https://busybox.net/downloads/busybox-1.38.0.tar.bz2" \
        "https://www.busybox.net/downloads/busybox-1.38.0.tar.bz2"

    rm -rf "$BUSYBOX"

    tar -xf "$BUSYBOX_TARBALL" -C "$ROOT/src"

    local extracted
    extracted="$(tar -tjf "$BUSYBOX_TARBALL" | head -n 1 | cut -d/ -f1)"

    [ -d "$ROOT/src/$extracted" ] || \
        die "BusyBox archive extraction failed."

    mv "$ROOT/src/$extracted" "$BUSYBOX"

    (
        cd "$BUSYBOX"

        make defconfig

        if [ -f scripts/config ]; then
            scripts/config --enable STATIC
        else
            sed -i \
                's/^# CONFIG_STATIC is not set$/CONFIG_STATIC=y/' \
                .config
        fi

        sed -i \
            's/^CONFIG_TC=y/# CONFIG_TC is not set/' \
            .config

        make olddefconfig
    )

    ok "BusyBox configuration ready"
}

# ------------------------------------------------------------
# Build kernel
# ------------------------------------------------------------

build_kernel() {

    echo
    echo "[1/6] Building Linux kernel..."

    [ -f "$KERNEL/Makefile" ] || \
        die "Kernel source missing."

    (
        cd "$KERNEL"

        log "Kernel source: $PWD"
        log "Build jobs: $JOBS"

        make -j"$JOBS" bzImage
    )

    [ -f "$KERNEL/arch/x86/boot/bzImage" ] || \
        die "Kernel build completed but bzImage was not produced."

    mkdir -p "$BUILD"

    cp "$KERNEL/arch/x86/boot/bzImage" \
       "$BUILD/vmlinuz"

    ok "Kernel built successfully"
}

# ------------------------------------------------------------
# Build BusyBox
# ------------------------------------------------------------

build_busybox() {

    echo
    echo "[2/6] Building BusyBox..."

    (
        cd "$BUSYBOX"

        make -j"$JOBS"
    )

    ok "BusyBox built successfully"
}

# ------------------------------------------------------------
# Root filesystem
# ------------------------------------------------------------

prepare_rootfs() {

    echo
    echo "[3/6] Preparing root filesystem..."

    mkdir -p "$ROOTFS"

    (
        cd "$BUSYBOX"

        make CONFIG_PREFIX="$ROOTFS" install
    )

    ok "Root filesystem prepared"
}

# ------------------------------------------------------------
# Initramfs
# ------------------------------------------------------------

prepare_initramfs() {

    echo
    echo "[4/6] Preparing initramfs..."

    [ -f "$INITRAMFS_SRC/init" ] || \
        die "Missing initramfs/init"

    rm -rf "$INITRAMFS_BUILD"

    mkdir -p \
        "$INITRAMFS_BUILD/bin" \
        "$INITRAMFS_BUILD/dev" \
        "$INITRAMFS_BUILD/proc" \
        "$INITRAMFS_BUILD/sys" \
        "$INITRAMFS_BUILD/run" \
        "$INITRAMFS_BUILD/tmp" \
        "$INITRAMFS_BUILD/newroot"

    cp "$ROOTFS/bin/busybox" \
       "$INITRAMFS_BUILD/bin/busybox"

    local applets=(
        sh
        mount
        switch_root
        cttyhack
        setsid
        sleep
        mkdir
    )

    for applet in "${applets[@]}"; do
        ln -sf busybox \
            "$INITRAMFS_BUILD/bin/$applet"
    done

    cp "$INITRAMFS_SRC/init" \
       "$INITRAMFS_BUILD/init"

    chmod +x \
        "$INITRAMFS_BUILD/init"

    ok "Initramfs prepared"
}

# ------------------------------------------------------------
# Create initramfs
# ------------------------------------------------------------

create_initramfs() {

    echo
    echo "[5/6] Creating initramfs..."

    mkdir -p "$BUILD"

    (
        cd "$INITRAMFS_BUILD"

        find . -print0 | cpio --null -ov --format=newc | gzip -9 > "$BUILD/initramfs.cpio.gz"
    )

    [ -s "$BUILD/initramfs.cpio.gz" ] || \
        die "Initramfs creation failed."

    ok "Initramfs created"
}

# ------------------------------------------------------------
# Create disk image
# ------------------------------------------------------------

create_disk_image() {

    echo
    echo "[6/6] Creating disk image..."

    mkdir -p "$DISK_DIR"

    rm -f "$DISK_IMG"

    truncate -s 512M "$DISK_IMG"

    mkfs.ext4 \
        -L RWEEZY \
        -F \
        -d "$ROOTFS" \
        "$DISK_IMG"

    [ -s "$DISK_IMG" ] || \
        die "Disk image creation failed."

    ok "Disk image created"
}

# ------------------------------------------------------------
# Build summary
# ------------------------------------------------------------

build_summary() {

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
    echo "Disk Image:"
    ls -lh "$DISK_IMG"

    echo
    echo "Rweezy OS build finished successfully!"
}

# ------------------------------------------------------------
# Main
# ------------------------------------------------------------

main() {

    echo "================================"
    echo "       Rweezy Build System"
    echo "================================"

    check_dependencies

    mkdir -p "$BUILD"

    bootstrap_linux
    bootstrap_busybox

    build_kernel
    build_busybox
    prepare_rootfs
    prepare_initramfs
    create_initramfs
    create_disk_image

    build_summary
}

main "$@"

