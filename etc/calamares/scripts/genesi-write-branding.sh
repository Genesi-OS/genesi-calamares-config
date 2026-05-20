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

# Set the genesi plymouth theme inside the target so mkinitcpio (which runs
# after this in the Calamares sequence) bakes the right splash into the
# initramfs. Falls back silently if plymouth or the theme is missing.
if [ -x "$ROOT/usr/bin/plymouth-set-default-theme" ] \
   && [ -d "$ROOT/usr/share/plymouth/themes/genesi" ]; then
    if command -v arch-chroot >/dev/null 2>&1; then
        arch-chroot "$ROOT" plymouth-set-default-theme genesi 2>&1 \
            | sed 's/^/[plymouth] /' || true
    else
        chroot "$ROOT" plymouth-set-default-theme genesi 2>&1 \
            | sed 's/^/[plymouth] /' || true
    fi
fi

# Defense-in-depth: if grub.cfg already exists in the target (because
# grubcfg ran out of order, e.g. someone re-orders the sequence later),
# regenerate it so the GRUB_DISTRIBUTOR we just wrote takes effect.
# Normally grubcfg runs AFTER this script so the regeneration is a no-op
# but it costs nothing and avoids "Arch Linux" GRUB titles silently.
if [ -x "$ROOT/usr/bin/grub-mkconfig" ] && [ -f "$ROOT/boot/grub/grub.cfg" ]; then
    if command -v arch-chroot >/dev/null 2>&1; then
        arch-chroot "$ROOT" grub-mkconfig -o /boot/grub/grub.cfg 2>&1 \
            | sed 's/^/[grub-mkconfig] /' || true
    else
        chroot "$ROOT" grub-mkconfig -o /boot/grub/grub.cfg 2>&1 \
            | sed 's/^/[grub-mkconfig] /' || true
    fi
fi

# ---- Defensive SDDM fixes ----------------------------------------------
# These three blocks fix the "black screen after install" reproduced on
# VirtualBox installs:
#   1. genesi-x11-detect.sh may decide vmwgfx isn't critical and skip
#      writing 00-display-server.conf. Wayland on vmwgfx then crashes
#      sddm-greeter -> black screen. Force X11 unconditionally on the
#      installed target. Real-hardware users can `rm` this file to opt
#      back into Wayland.
#   2. The "genesi" SDDM theme works on the live ISO but exits 127 on
#      the installed target (probably a QML/binary dep that ships with
#      cachyos-calamares-next on the live but is absent from the target).
#      Switch the target's SDDM Current= theme to breeze until the genesi
#      theme is fixed properly.
#   3. Remove calamares.desktop from any /home/<user>/Desktop and from
#      /etc/skel/Desktop — that shortcut is a live-ISO Install button,
#      makes zero sense on the installed system. Same for KDE Plasma's
#      "Welcome to Plasma" (Konqi) autostart, which duplicates and clashes
#      with our genesi-welcome.

mkdir -p "$ROOT/etc/sddm.conf.d"
cat > "$ROOT/etc/sddm.conf.d/00-display-server.conf" << 'EOF'
[General]
DisplayServer=x11
EOF
echo "==> Forced SDDM DisplayServer=x11 in target"

if [ -f "$ROOT/etc/sddm.conf.d/genesi-theme.conf" ]; then
    sed -i 's|^Current=genesi|Current=breeze|' \
        "$ROOT/etc/sddm.conf.d/genesi-theme.conf"
    echo "==> Switched SDDM Current=breeze in target (genesi theme exits 127)"
fi

# Strip calamares.desktop from /etc/skel and all existing user homes
rm -f "$ROOT/etc/skel/Desktop/calamares.desktop" 2>/dev/null
for home in "$ROOT"/home/*; do
    [ -d "$home/Desktop" ] || continue
    rm -f "$home/Desktop/calamares.desktop" 2>/dev/null
done
echo "==> Stripped calamares.desktop from /etc/skel and /home/*/Desktop"

# Disable KDE Plasma Welcome (Konqi mascot) — clashes visually with our
# genesi-welcome. Drop a Hidden=true override in /etc/xdg/autostart so it
# applies system-wide for the installed system.
if [ -f "$ROOT/etc/xdg/autostart/org.kde.plasma.welcome.desktop" ]; then
    cat > "$ROOT/etc/xdg/autostart/org.kde.plasma.welcome.desktop" << 'EOF'
[Desktop Entry]
Type=Application
Name=Welcome Center
Hidden=true
X-GNOME-Autostart-enabled=false
EOF
    echo "==> Disabled KDE Plasma Welcome autostart (we have genesi-welcome)"
fi

# ---- Enable genesi-update systemd user units ---------------------------
# The genesi-update package ships:
#   /usr/lib/systemd/user/genesi-update.timer        — periodic update check
#   /usr/lib/systemd/user/genesi-update.service      — one-shot check (called by timer)
#   /usr/lib/systemd/user/genesi-update-tray.service — tray applet
#
# Both ship with preset=enabled but `systemctl --user enable` doesn't work
# globally — it's per-user and the user doesn't exist yet at preset-application
# time. So we manually create the symlinks in /etc/skel (future users) AND in
# every /home/<user> Calamares already populated (current users).
SKEL_TARGETS_DIR="$ROOT/etc/skel/.config/systemd/user"
mkdir -p "$SKEL_TARGETS_DIR/timers.target.wants"
mkdir -p "$SKEL_TARGETS_DIR/default.target.wants"
if [ -f "$ROOT/usr/lib/systemd/user/genesi-update.timer" ]; then
    ln -sf /usr/lib/systemd/user/genesi-update.timer \
        "$SKEL_TARGETS_DIR/timers.target.wants/genesi-update.timer"
    echo "==> Enabled genesi-update.timer in /etc/skel"
fi
if [ -f "$ROOT/usr/lib/systemd/user/genesi-update-tray.service" ]; then
    ln -sf /usr/lib/systemd/user/genesi-update-tray.service \
        "$SKEL_TARGETS_DIR/default.target.wants/genesi-update-tray.service"
    echo "==> Enabled genesi-update-tray.service in /etc/skel"
fi

# Replicate for users Calamares already created.
shopt -s nullglob
for home in "$ROOT"/home/*; do
    [ -d "$home" ] || continue
    user=$(basename "$home")
    uid=$(awk -F: -v u="$user" '$1==u{print $3}' "$ROOT/etc/passwd")
    gid=$(awk -F: -v u="$user" '$1==u{print $4}' "$ROOT/etc/passwd")
    [ -n "$uid" ] && [ -n "$gid" ] || continue
    UDIR="$home/.config/systemd/user"
    mkdir -p "$UDIR/timers.target.wants" "$UDIR/default.target.wants"
    [ -f "$ROOT/usr/lib/systemd/user/genesi-update.timer" ] && \
        ln -sf /usr/lib/systemd/user/genesi-update.timer \
            "$UDIR/timers.target.wants/genesi-update.timer"
    [ -f "$ROOT/usr/lib/systemd/user/genesi-update-tray.service" ] && \
        ln -sf /usr/lib/systemd/user/genesi-update-tray.service \
            "$UDIR/default.target.wants/genesi-update-tray.service"
    chown -R "$uid:$gid" "$home/.config/systemd" 2>/dev/null
    echo "==> Enabled genesi-update units for user '$user'"
done

echo "==> Genesi OS: branding files written"
exit 0
