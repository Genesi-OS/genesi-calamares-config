#!/usr/bin/env bash
# Finalize the installed Genesi Limine boot menu after Calamares installs the
# loader, and wire up the Btrfs-snapshot recovery stack (limine-snapper-sync).
#
# This is the Limine counterpart of genesi-grub-setup.sh. It runs as
# shellprocess@genesi_limine and self-gates on /etc/default/limine, so it only
# acts when the user picked Limine and the GRUB path is never affected. Design
# goals, in priority order:
#   1. NEVER abort the install. The bootloader module already ran limine-install
#      and wrote a working limine.conf; everything here is finalization on top of
#      an already-bootable system, so every step is guarded and non-fatal.
#   2. Reproduce CachyOS's proven post-setup recipe (limine-mkinitcpio-hook +
#      sd-btrfs-overlayfs + limine-update) so new kernels get entries and
#      snapshots boot WRITABLE.
#   3. Rebrand the result to Genesi (menu name + palette) without touching the
#      generated boot entries.
#
# Calamares expands ${ROOT} in the command string but does NOT export it, so the
# target mount point is passed as the FIRST ARGUMENT (see
# shellprocess_genesi_limine.conf). env/`/mnt` fallbacks are for manual runs.
set -uo pipefail
exec 2>&1

ROOT="${1:-${ROOT:-/mnt}}"

log()  { echo "==> Genesi Limine: $*"; }
warn() { echo "==> Genesi Limine: WARNING: $*"; }

log "finalizing Limine in $ROOT"
if [ ! -d "$ROOT/etc" ] || [ ! -d "$ROOT/usr" ]; then
    warn "'$ROOT' does not look like an installed target root — skipping"
    exit 0
fi

# Self-gate (mirror of genesi-grub-setup.sh): the bootloader module writes
# /etc/default/limine ONLY for a Limine install. If it's absent, GRUB (or another
# loader) was chosen — this is a clean no-op.
if [ ! -e "$ROOT/etc/default/limine" ]; then
    log "/etc/default/limine absent — Limine is not the selected bootloader, skipping"
    exit 0
fi

# The bootloader module writes limine.conf into the ESP (path depends on the
# mount layout). Locate it; if it isn't there, Limine wasn't the active loader
# (or the module failed) — nothing to finalize, exit cleanly.
limine_conf="$(find "$ROOT/boot" -maxdepth 4 -name 'limine.conf' 2>/dev/null | head -n1)"
if [ -z "$limine_conf" ]; then
    warn "no limine.conf found under $ROOT/boot — not a Limine install, skipping"
    exit 0
fi
log "found limine.conf at ${limine_conf#$ROOT}"

# Run target-side commands in the chroot. arch-chroot sets up the API mounts
# (proc/sys/dev + resolv.conf) that pacman needs; fall back to plain chroot.
if command -v arch-chroot >/dev/null 2>&1; then
    run_target() { arch-chroot "$ROOT" "$@"; }
else
    run_target() { chroot "$ROOT" "$@"; }
fi

# ---- 1. Btrfs snapshot recovery stack (limine-snapper-sync) ------------------
# Only meaningful on a Btrfs root; but the packages are harmless elsewhere and
# limine-snapper-sync.service simply won't do anything without snapper. Network
# is up at this stage (online install), so pacman can pull from the repos. Every
# step is non-fatal: a missing package must never abort the install — worst case
# Limine still boots, only snapshot sync is absent until the package appears.
log "installing the Limine snapshot stack (non-fatal)"
run_target pacman -S --needed --noconfirm limine-snapper-sync limine-mkinitcpio-hook \
    || warn "could not install limine-snapper-sync/limine-mkinitcpio-hook — Limine still boots, snapshot sync skipped"
# cachyos-snapper-support pulls snapper + snap-pac config tuned for CachyOS-based
# systems; optional, so guard it separately.
run_target pacman -S --needed --noconfirm cachyos-snapper-support \
    || warn "cachyos-snapper-support not installed (optional)"

# limine-entry-tool and limine-mkinitcpio-hook are mutually exclusive ways to
# generate entries; prefer the hook (automatic on kernel install). Only swap if
# the hook actually got installed above.
if run_target pacman -Qq limine-mkinitcpio-hook >/dev/null 2>&1; then
    if run_target pacman -Qq limine-entry-tool >/dev/null 2>&1; then
        log "replacing limine-entry-tool with limine-mkinitcpio-hook"
        run_target pacman -R --noconfirm limine-entry-tool || warn "could not remove limine-entry-tool"
    fi
fi

# Boot snapshots WRITABLE via the sd-btrfs-overlayfs initramfs hook (matches
# CachyOS). Only add it when snapper is actually configured (Btrfs root).
if [ -e "$ROOT/etc/limine-snapper-sync.conf" ] || run_target pacman -Qq limine-snapper-sync >/dev/null 2>&1; then
    mkdir -p "$ROOT/etc/mkinitcpio.conf.d"
    cat > "$ROOT/etc/mkinitcpio.conf.d/10-limine-snapper-sync.conf" <<'EOF'
# Genesi OS: required for booting Limine snapshots (writable via overlayfs).
# Do not edit unless you know what you are doing.
HOOKS+=(sd-btrfs-overlayfs)
EOF
fi

# Brand the snapshot menu group with the Genesi name.
if [ -e "$ROOT/etc/limine-snapper-sync.conf" ]; then
    sed -i 's/^TARGET_OS_NAME=.*/TARGET_OS_NAME="Genesi OS"/' \
        "$ROOT/etc/limine-snapper-sync.conf" 2>/dev/null || true
fi

# ---- 2. (re)generate boot entries -------------------------------------------
# limine-update reads the installed kernels + /etc/default/limine and writes the
# boot entries into limine.conf. Non-fatal.
log "running limine-update"
run_target limine-update || warn "limine-update failed (will retry on the next kernel update)"

# If, after limine-update, the menu still has no kernel entry, force the
# limine-mkinitcpio-hook to fire by regenerating the initramfs. This is a safety
# net so the installed system is bootable; mkinitcpio -P is idempotent.
if ! grep -Eq '(^|[[:space:]])(kernel_path|image_path|module_path)[[:space:]]*[:=]' "$limine_conf" 2>/dev/null; then
    warn "no boot entries after limine-update — regenerating initramfs to trigger the Limine hook"
    run_target mkinitcpio -P || warn "mkinitcpio -P failed"
    run_target limine-update || true
fi

# ---- 3. rebrand the finished limine.conf to Genesi (cosmetic, non-fatal) -----
# Done AFTER entry generation so we never disturb the boot entries. All edits are
# in-place replacements only: if limine-update rewrote the file without these
# lines, we simply skip that override — the Genesi wallpaper (copied by the
# bootloader module from limineSplashLogo) and the menu name below still make it
# clearly Genesi. Palette values are graphite/dark to match the Genesi brand and
# are easy to tune here.
log "applying Genesi branding to limine.conf"
# Menu group name: the module writes an OS group header for the base distro.
sed -i 's|^/+CachyOS$|/+Genesi OS|' "$limine_conf" 2>/dev/null || true
# Theme author comment left by the upstream module.
sed -i 's|^# CachyOS Limine theme$|# Genesi OS Limine theme|' "$limine_conf" 2>/dev/null || true
sed -i '\|^# Author: diegons490|d' "$limine_conf" 2>/dev/null || true
# Genesi graphite palette (ANSI: black;red;green;yellow;blue;magenta;cyan;white).
sed -i 's|^term_palette:.*|term_palette: 181a20;e06c75;98c379;e5c07b;61afef;c678dd;56b6c2;abb2bf|' \
    "$limine_conf" 2>/dev/null || true
sed -i 's|^term_palette_bright:.*|term_palette_bright: 2c313a;e06c75;98c379;e5c07b;61afef;c678dd;56b6c2;c8ccd4|' \
    "$limine_conf" 2>/dev/null || true

log "Limine finalization complete"
exit 0
