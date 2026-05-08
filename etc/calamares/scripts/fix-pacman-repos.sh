#!/bin/bash
# Fix pacman.conf repositories - remove bad entries and write known-good
# CachyOS repo. CachyOS only ships [cachyos] / [cachyos-v3] / [cachyos-v4];
# there is NO [cachyos-desktop] repo and the cdn-77.cachyos.org host does
# not resolve, so both must be stripped.

set +e

clean_conf() {
    local conf="$1"
    [ -f "$conf" ] || return 0

    # Drop any pre-existing [cachyos*] section so we can rewrite cleanly.
    sed -i '/^\[cachyos-desktop\]/,/^\[/{/^\[cachyos-desktop\]/d;/^\[/!d}' "$conf"
    sed -i '/^\[cachyos\]/,/^\[/{/^\[cachyos\]/d;/^\[/!d}' "$conf"

    # Drop cdn-77 (DNS does not resolve) and the dead nl/lesviallon mirrors
    # that may be referenced inline.
    sed -i '/cdn-77\.cachyos\.org/d'        "$conf"
    sed -i '/nl\.cachyos\.org/d'            "$conf"
    sed -i '/mirror\.lesviallon\.fr/d'      "$conf"

    # Insert a clean [cachyos] section before [core].
    sed -i '/^\[core\]/i \
[cachyos]\
SigLevel = Never\
Server = https://mirror.cachyos.org/repo/$arch/$repo\
Server = https://build.cachyos.org/repo/$arch/$repo\
' "$conf"
}

clean_conf /etc/pacman.conf

if [ -n "$ROOT" ] && [ -f "$ROOT/etc/pacman.conf" ]; then
    clean_conf "$ROOT/etc/pacman.conf"
fi

# Also strip cdn-77 / nl / lesviallon from any cachyos-mirrorlist files.
for ml in /etc/pacman.d/cachyos-mirrorlist \
          /etc/pacman.d/cachyos-v3-mirrorlist \
          /etc/pacman.d/cachyos-v4-mirrorlist; do
    [ -f "$ml" ] || continue
    sed -i -e '/cdn-77\.cachyos\.org/d' \
           -e '/nl\.cachyos\.org/d' \
           -e '/mirror\.lesviallon\.fr/d' "$ml"
done

echo "Pacman repos fixed: only [cachyos] with mirror.cachyos.org + build.cachyos.org"
exit 0
