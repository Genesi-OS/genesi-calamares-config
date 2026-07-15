#!/usr/bin/env bash
# Finalize the installed Genesi GRUB menu after Calamares installs the loader.
# The active menu is never replaced until its candidate has passed validation.
set -euo pipefail
exec 2>&1

ROOT="${ROOT:-/mnt}"
defaults="$ROOT/etc/default/grub"
candidate=/boot/grub/.grub.cfg.genesi-install

echo "==> Genesi OS: finalizing and validating GRUB in $ROOT"
mkdir -p "$ROOT/etc/default" "$ROOT/boot/grub"
[ -f "$defaults" ] || : > "$defaults"

set_kv() {
    local key="$1" value="$2"
    if grep -q "^[#[:space:]]*${key}=" "$defaults"; then
        sed -i "s|^[#[:space:]]*${key}=.*|${key}=${value}|" "$defaults"
    else
        printf '%s=%s\n' "$key" "$value" >> "$defaults"
    fi
}

set_kv GRUB_DISTRIBUTOR '"Genesi OS"'
[ -f "$ROOT/usr/share/grub/themes/genesi/theme.txt" ] \
    || { echo "==> ERROR: Genesi GRUB theme is missing"; exit 1; }
[ -f "$ROOT/usr/share/grub/themes/genesi/background.png" ] \
    || { echo "==> ERROR: Genesi GRUB background is missing"; exit 1; }
set_kv GRUB_THEME '"/usr/share/grub/themes/genesi/theme.txt"'
set_kv GRUB_BACKGROUND '"/usr/share/grub/themes/genesi/background.png"'
set_kv GRUB_COLOR_NORMAL '"light-gray/black"'
set_kv GRUB_COLOR_HIGHLIGHT '"white/dark-gray"'
set_kv GRUB_TERMINAL_OUTPUT '"gfxterm"'
set_kv GRUB_GFXMODE '"1024x768,1280x720,1920x1080,auto"'

[ -x "$ROOT/usr/bin/grub-mkconfig" ] \
    || { echo "==> ERROR: grub-mkconfig is missing"; exit 1; }
[ -x "$ROOT/usr/bin/grub-script-check" ] \
    || { echo "==> ERROR: grub-script-check is missing"; exit 1; }

if command -v arch-chroot >/dev/null 2>&1; then
    run_target() { arch-chroot "$ROOT" "$@"; }
else
    run_target() { chroot "$ROOT" "$@"; }
fi

rm -f "$ROOT$candidate"
trap 'rm -f "$ROOT/boot/grub/.grub.cfg.genesi-install"' EXIT
run_target grub-mkconfig -o "$candidate" 2>&1 | sed 's/^/[grub] /'
run_target grub-script-check "$candidate"
grep -Eq '^[[:space:]]*(menuentry|submenu)[[:space:]]' "$ROOT$candidate" \
    || { echo "==> ERROR: generated GRUB menu has no entries"; exit 1; }
grep -Eq '(^|[[:space:]])(linux|linuxefi)[[:space:]].*(vmlinuz|/boot/)' "$ROOT$candidate" \
    || { echo "==> ERROR: generated GRUB menu has no Linux kernel"; exit 1; }

if [ -s "$ROOT/boot/grub/grub.cfg" ] \
   && run_target grub-script-check /boot/grub/grub.cfg >/dev/null 2>&1; then
    cp -a "$ROOT/boot/grub/grub.cfg" "$ROOT/boot/grub/grub.cfg.genesi-last-good"
fi
chmod 600 "$ROOT$candidate"
mv -f "$ROOT$candidate" "$ROOT/boot/grub/grub.cfg"
trap - EXIT

echo "==> Genesi OS: validated GRUB menu installed atomically"
