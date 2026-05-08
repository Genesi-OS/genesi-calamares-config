#!/bin/bash
# Genesi OS - Prepare pacman before pacstrap
#
# Runs ON THE LIVE ISO (host) before pacstrap installs the base system.
# /usr/local/bin/calamares-online.sh has already run `pacman-key --init`
# and `pacman-key --populate archlinux cachyos` before Calamares started,
# so the live keyring is ready and we deliberately do NOT call pacman-key
# here (calling it again was producing "chroot: failed to run command
# '/bin/sh'" because of how Calamares wraps commands).
#
# All steps are best-effort: failures here MUST NOT abort installation.

# Always succeed - we never want to fail the install at this stage.
set +e
exec 2>&1
trap 'exit 0' EXIT

# Calamares passes ROOT as the target mount point (e.g. /tmp/calamares-root-XXX).
# Fall back to /mnt for safety.
ROOT="${ROOT:-/mnt}"

echo "==> Genesi OS: preparing pacman (target=$ROOT)"

# --------------------------------------------------------------------------
# 1. Live ISO: strip dead mirrors from cachyos-mirrorlist files
# --------------------------------------------------------------------------
for ml in /etc/pacman.d/cachyos-mirrorlist \
          /etc/pacman.d/cachyos-v3-mirrorlist \
          /etc/pacman.d/cachyos-v4-mirrorlist; do
    [ -f "$ml" ] || continue
    sed -i -e '/nl\.cachyos\.org/d' \
           -e '/mirror\.lesviallon\.fr/d' "$ml" 2>/dev/null
done

# --------------------------------------------------------------------------
# 2. Live ISO: rewrite [cachyos] / [cachyos-desktop] sections in pacman.conf
#    fix-pacman-repos.sh is provided alongside this script.
# --------------------------------------------------------------------------
if [ -x /etc/calamares/scripts/fix-pacman-repos.sh ]; then
    bash /etc/calamares/scripts/fix-pacman-repos.sh || true
fi

# Strip stale [genesi] section if present (live ISO)
sed -i '/^\[genesi\]/,/^$/d' /etc/pacman.conf 2>/dev/null
sed -i '/genesi/d'           /etc/pacman.conf 2>/dev/null

# --------------------------------------------------------------------------
# 3. Live ISO: refresh mirrorlist
#    NOTE: pacman-key --init / --populate were ALREADY done by
#    calamares-online.sh before Calamares started. Do not run them here.
# --------------------------------------------------------------------------
if [ -x /etc/calamares/scripts/update-mirrorlist ]; then
    bash /etc/calamares/scripts/update-mirrorlist || true
fi

# --------------------------------------------------------------------------
# 4. Live ISO: drop stale package db so pacstrap will re-fetch fresh ones
# --------------------------------------------------------------------------
rm -rf /var/lib/pacman/sync/*.db 2>/dev/null

# --------------------------------------------------------------------------
# 5. Stage host pacman state into the (still empty) target mount point.
#    pacstrap re-creates these but a few of its early-init steps look for
#    /etc/pacman.conf inside the new root, so we copy first.
# --------------------------------------------------------------------------
mkdir -p "$ROOT/etc/pacman.d" 2>/dev/null
mkdir -p "$ROOT/etc"          2>/dev/null

cp /etc/pacman.conf         "$ROOT/etc/pacman.conf"           2>/dev/null
cp /etc/pacman.d/mirrorlist "$ROOT/etc/pacman.d/mirrorlist"   2>/dev/null
cp -a /etc/pacman.d/gnupg   "$ROOT/etc/pacman.d/"             2>/dev/null
cp /etc/resolv.conf         "$ROOT/etc/resolv.conf"           2>/dev/null

# Copy cachyos mirrorlists too if they exist
for ml in cachyos-mirrorlist cachyos-v3-mirrorlist cachyos-v4-mirrorlist; do
    [ -f "/etc/pacman.d/$ml" ] && cp "/etc/pacman.d/$ml" "$ROOT/etc/pacman.d/$ml" 2>/dev/null
done

# Strip [genesi] from the target's pacman.conf as well
sed -i '/^\[genesi\]/,/^$/d' "$ROOT/etc/pacman.conf" 2>/dev/null
sed -i '/genesi/d'           "$ROOT/etc/pacman.conf" 2>/dev/null

# Also strip dead mirrors from copied mirrorlists in the target
for ml in cachyos-mirrorlist cachyos-v3-mirrorlist cachyos-v4-mirrorlist; do
    [ -f "$ROOT/etc/pacman.d/$ml" ] || continue
    sed -i -e '/nl\.cachyos\.org/d' \
           -e '/mirror\.lesviallon\.fr/d' "$ROOT/etc/pacman.d/$ml" 2>/dev/null
done

echo "==> Genesi OS: pacman prepared"
exit 0
