#!/bin/bash
# Genesi OS - write os-release / lsb-release / GRUB_DISTRIBUTOR in the target
# so the boot menu and userspace identify the install as "Genesi OS"
# regardless of what the live ISO inherited from CachyOS / Arch.

set +e
exec 2>&1
trap 'exit 0' EXIT

ROOT="${ROOT:-/mnt}"

echo "==> Genesi OS: writing branding files to $ROOT"

mkdir -p "$ROOT/etc" "$ROOT/etc/default"

# /etc/os-release
cat > "$ROOT/etc/os-release" << 'EOF'
NAME="Genesi OS"
PRETTY_NAME="Genesi OS"
ID=genesi
ID_LIKE="cachyos arch"
BUILD_ID=rolling
ANSI_COLOR="38;2;23;147;209"
HOME_URL="https://github.com/zFreshy/GenesiOS"
DOCUMENTATION_URL="https://github.com/zFreshy/GenesiOS"
SUPPORT_URL="https://github.com/zFreshy/GenesiOS/issues"
BUG_REPORT_URL="https://github.com/zFreshy/GenesiOS/issues"
LOGO=genesi
EOF

# /etc/lsb-release
cat > "$ROOT/etc/lsb-release" << 'EOF'
DISTRIB_ID="Genesi OS"
DISTRIB_RELEASE="rolling"
DISTRIB_DESCRIPTION="Genesi OS"
EOF

# Force GRUB_DISTRIBUTOR. grubcfg module will run after this and may also
# set it, but writing it here guarantees correct value even if grubcfg is
# misconfigured or skipped.
GRUB_DEFAULT="$ROOT/etc/default/grub"
if [ -f "$GRUB_DEFAULT" ]; then
    if grep -q '^GRUB_DISTRIBUTOR=' "$GRUB_DEFAULT"; then
        sed -i 's|^GRUB_DISTRIBUTOR=.*|GRUB_DISTRIBUTOR="Genesi OS"|' "$GRUB_DEFAULT"
    else
        echo 'GRUB_DISTRIBUTOR="Genesi OS"' >> "$GRUB_DEFAULT"
    fi
else
    cat > "$GRUB_DEFAULT" << 'EOF'
GRUB_DEFAULT=saved
GRUB_TIMEOUT=5
GRUB_DISTRIBUTOR="Genesi OS"
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash"
GRUB_CMDLINE_LINUX=""
GRUB_DISABLE_RECOVERY=true
GRUB_DISABLE_SUBMENU=y
GRUB_TERMINAL_OUTPUT=console
EOF
fi


# Force graphical.target as default and enable SDDM in the target.
# services-systemd module should already do this, but enabling it via
# direct symlinks is idempotent and avoids relying on detection logic.
mkdir -p "$ROOT/etc/systemd/system"
ln -sf /usr/lib/systemd/system/graphical.target "$ROOT/etc/systemd/system/default.target"

# Enable sddm.service for graphical.target
mkdir -p "$ROOT/etc/systemd/system/display-manager.service.d"
ln -sf /usr/lib/systemd/system/sddm.service "$ROOT/etc/systemd/system/display-manager.service" 2>/dev/null

echo "==> Genesi OS: branding files written"
exit 0
