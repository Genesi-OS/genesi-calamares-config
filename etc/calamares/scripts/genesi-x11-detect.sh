#!/bin/bash
# Drop /etc/sddm.conf.d/00-display-server.conf forcing X11 into the target
# ONLY when the live ISO runs on a broken Wayland video stack (vmwgfx =
# VirtualBox unsupported hypervisor, vboxvideo, or no KMS driver). On real
# hardware with amdgpu / i915 / nouveau / nvidia we leave SDDM at its
# default so Plasma 6 Wayland features (fractional scaling, HDR, gestures)
# stay available.
#
# Called from shellprocess@copy_genesi (dontChroot: true), which passes the
# target rootMountPoint as the first argument (Calamares expands ${ROOT} in
# the command string only — it does NOT export ROOT into the environment).
set -u
ROOT="${1:-${ROOT:-/mnt}}"

mkdir -p "$ROOT/etc/sddm.conf.d"

need_x11=0
if lsmod 2>/dev/null | grep -Ewq '^(vmwgfx|vboxvideo)'; then
    need_x11=1
elif ! ls /sys/class/drm/card?/device/driver 2>/dev/null \
       | xargs -r -n1 readlink 2>/dev/null \
       | grep -Eq 'amdgpu|i915|nouveau|nvidia|radeon|virtio'; then
    # No recognized KMS driver loaded — safer to fall back to X11.
    need_x11=1
fi

if [ "$need_x11" = 1 ]; then
    printf '[General]\nDisplayServer=x11\n' \
        > "$ROOT/etc/sddm.conf.d/00-display-server.conf"
    echo "[x11-detect] forced SDDM DisplayServer=x11 (unsupported/missing KMS driver)"
else
    echo "[x11-detect] keeping SDDM default (Wayland) — supported KMS driver detected"
fi
exit 0
