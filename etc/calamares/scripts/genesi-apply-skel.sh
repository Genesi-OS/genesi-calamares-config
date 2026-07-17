#!/bin/bash
# Defense-in-depth: if any /home/<user> already exists when copy_genesi
# runs (e.g. someone re-orders the Calamares sequence and puts users
# before copy_genesi), apply /etc/skel content into each user home and
# fix ownership. In the current sequence copy_genesi runs BEFORE users,
# so /home is empty and this loop is a no-op — but it costs nothing.
#
# Called from shellprocess@copy_genesi (dontChroot: true), which passes the
# target rootMountPoint as the first argument (Calamares expands ${ROOT} in
# the command string only — it does NOT export ROOT into the environment).
set -u
ROOT="${1:-${ROOT:-/mnt}}"

shopt -s nullglob
for home in "$ROOT"/home/*; do
    [ -d "$home" ] || continue
    user=$(basename "$home")
    cp -rf "$ROOT/etc/skel/." "$home/" 2>/dev/null || true
    uid=$(awk -F: -v u="$user" '$1==u{print $3}' "$ROOT/etc/passwd")
    gid=$(awk -F: -v u="$user" '$1==u{print $4}' "$ROOT/etc/passwd")
    if [ -n "$uid" ] && [ -n "$gid" ]; then
        chown -R "$uid:$gid" "$home" 2>/dev/null || true
    fi
done
echo "[apply-skel] done"
exit 0
