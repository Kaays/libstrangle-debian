#!/usr/bin/env bash
# remove-manual-install.sh — Remove a libstrangle that was installed with
# 'sudo make install' (default prefix /usr/local), so it does not clash with
# the .deb package. Safe to run more than once.

set -euo pipefail

files=(
    /usr/local/bin/strangle
    /usr/local/bin/stranglevk
    /usr/local/share/vulkan/implicit_layer.d/libstrangle_vk.json
    /usr/local/lib/libstrangle/lib32/libstrangle.so
    /usr/local/lib/libstrangle/lib32/libstrangle_nodlsym.so
    /usr/local/lib/libstrangle/lib32/libstrangle_vk.so
    /usr/local/lib/libstrangle/lib64/libstrangle.so
    /usr/local/lib/libstrangle/lib64/libstrangle_nodlsym.so
    /usr/local/lib/libstrangle/lib64/libstrangle_vk.so
)

# /etc/ld.so.conf.d/libstrangle.conf is only removed if it points to /usr/local,
# so a file that already belongs to the .deb is left alone.
conf=/etc/ld.so.conf.d/libstrangle.conf
if [ -f "$conf" ] && grep -q '/usr/local' "$conf"; then
    files+=("$conf")
fi

found=()
for f in "${files[@]}"; do
    [ -e "$f" ] && found+=("$f")
done

if [ ${#found[@]} -eq 0 ]; then
    echo "No manual libstrangle installation found under /usr/local."
    exit 0
fi

echo "These files will be removed:"
printf '    %s\n' "${found[@]}"
read -r -p "Continue? [y/N] " answer
case "$answer" in
    y|Y|e|E) ;;
    *) echo "Cancelled."; exit 0 ;;
esac

sudo rm -f "${found[@]}"
sudo rmdir --ignore-fail-on-non-empty \
    /usr/local/lib/libstrangle/lib32 /usr/local/lib/libstrangle/lib64 \
    /usr/local/lib/libstrangle 2>/dev/null || true
sudo ldconfig
hash -r 2>/dev/null || true
echo "Done. The manual installation was removed."
