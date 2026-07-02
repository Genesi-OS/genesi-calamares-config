#!/bin/bash
# Genesi OS — pick the new user's default desktop session based on which DE was
# actually installed (Roadmap 5.1 multi-DE support).
#
# WHY: the Calamares packagechooser lets the user pick Plasma (default) OR
# "Hyprland + caelestia-shell". The session default must follow that choice:
#   * Plasma  -> Plasma X11 (plasmax11.desktop). Plasma 6 defaults to Wayland,
#     which breaks on VirtualBox/VMSVGA and some NVIDIA setups (SDDM bounces back
#     to the greeter). X11 Plasma runs everywhere, so it's the safe default; the
#     Wayland session stays in the SDDM menu for capable hardware.
#   * Hyprland -> hyprland.desktop. Hyprland is Wayland-only (no X11 session
#     exists), so there's nothing to fall back to — we point the user straight at
#     it. (Hyprland in a VM with a broken Wayland stack is a known limitation,
#     same caveat that already applies to Plasma Wayland.)
#
# Detection is by what landed on disk: a Hyprland-only install has /usr/bin/
# Hyprland and no /usr/bin/plasmashell. Anything else (Plasma, or both) keeps the
# previous Plasma-X11 default.
#
# Called from shellprocess@genesi_session (dontChroot: true), AFTER the users
# module, so /home/<user> already exists. Calamares passes the target
# rootMountPoint as $ROOT. Every write is guarded so a hiccup never aborts the
# install.
set -u
ROOT="${ROOT:-/mnt}"

mkdir -p "$ROOT/var/lib/AccountsService/users" 2>/dev/null || true

# Map the installed DE to the user's default session. Detection is by what
# actually landed in the target (a binary that is unique to each DE), because a
# single install only ever has ONE DE group selected in the chooser.
#
#   Session=<file>.desktop  -> read by SDDM/GDM (Wayland-capable greeters).
#   XSession=<name>         -> read by LightDM for X11 sessions (name matches
#                              /usr/share/xsessions/<name>.desktop).
#
# IMPORTANT: if no known DE is detected we leave BOTH lines empty and let the
# display manager pick its own default. We must NOT fall back to a Plasma
# session — on a non-Plasma install (GNOME/Xfce/…) that would point the account
# at plasmax11.desktop, which isn't installed, and the first login would land on
# an empty/failed session.
SESSION_LINE=""
XSESSION_LINE=""
label="display-manager default"
if [ -e "$ROOT/usr/bin/Hyprland" ] && [ ! -e "$ROOT/usr/bin/plasmashell" ]; then
    # Hyprland is Wayland-only; there is no X11 session to fall back to.
    SESSION_LINE="Session=hyprland.desktop"
    label="Hyprland (Wayland)"
elif [ -e "$ROOT/usr/bin/plasmashell" ]; then
    # Plasma 6 defaults to Wayland, which breaks on VirtualBox/VMSVGA and some
    # NVIDIA setups; force the X11 session, which runs everywhere. The Wayland
    # session stays in the SDDM menu for capable hardware.
    SESSION_LINE="Session=plasmax11.desktop"
    XSESSION_LINE="XSession=plasmax11"
    label="Plasma X11"
elif [ -e "$ROOT/usr/bin/gnome-shell" ]; then
    # GNOME (GDM). gnome.desktop is the Wayland session; GDM cleanly falls back
    # to X11 (gnome-xorg) when Wayland can't start, so this is safe on VMs too.
    SESSION_LINE="Session=gnome.desktop"
    label="GNOME"
elif [ -e "$ROOT/usr/bin/cinnamon-session" ]; then
    # Cinnamon on LightDM (X11).
    XSESSION_LINE="XSession=cinnamon"
    label="Cinnamon"
elif [ -e "$ROOT/usr/bin/mate-session" ]; then
    # MATE on LightDM (X11).
    XSESSION_LINE="XSession=mate"
    label="MATE"
elif [ -e "$ROOT/usr/bin/xfce4-session" ]; then
    # Xfce on LightDM (X11).
    XSESSION_LINE="XSession=xfce"
    label="Xfce"
fi

shopt -s nullglob
for home in "$ROOT"/home/*; do
    [ -d "$home" ] || continue
    user=$(basename "$home")
    # Only real login users (uid >= 1000); skip system accounts that may own a
    # /home entry.
    uid=$(awk -F: -v u="$user" '$1==u{print $3}' "$ROOT/etc/passwd" 2>/dev/null)
    [ -n "$uid" ] || continue
    [ "$uid" -ge 1000 ] 2>/dev/null || continue

    f="$ROOT/var/lib/AccountsService/users/$user"
    {
        echo '[User]'
        [ -n "$SESSION_LINE" ] && echo "$SESSION_LINE"
        [ -n "$XSESSION_LINE" ] && echo "$XSESSION_LINE"
        echo 'SystemAccount=false'
    } > "$f" 2>/dev/null || true
    echo "[set-session] $user -> $label"
done
exit 0
