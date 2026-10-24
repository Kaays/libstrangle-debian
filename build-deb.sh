#!/usr/bin/env bash
# build-deb.sh — Build a .deb of libstrangle for Debian, Ubuntu and derivatives.
#
# Usage:  ./build-deb.sh [path-to-libstrangle-source]   (default: current directory)
#
# Works with the maintained libstrangle (https://gitlab.com/torkel104/libstrangle),
# which includes the Vulkan layer. Run it as a normal user, NOT with sudo:
# nothing is installed on your system, the result is a .deb in ./dist/.
#
# Environment overrides:
#   VERSION=1.2.3          package version (default: derived from git)
#   MAINTAINER="Name <x@y>" maintainer field (default: from git config)

set -euo pipefail

die()  { printf '\033[1;31mError:\033[0m %s\n' "$*" >&2; exit 1; }
info() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mWarning:\033[0m %s\n' "$*" >&2; }

[ "$(id -u)" -ne 0 ] || die "Do not run this script as root or with sudo. It only builds a package; install it afterwards with 'sudo apt install ./dist/<file>.deb'."

SRC="$(cd "${1:-.}" && pwd)"
cd "$SRC"

[ -f makefile ] || [ -f Makefile ] || die "No makefile in $SRC. Point the script at the libstrangle source directory."
[ -f src/vulkan/overlay.cpp ] || die "src/vulkan/overlay.cpp not found. This needs the maintained libstrangle with Vulkan support: git clone https://gitlab.com/torkel104/libstrangle.git"

# ---------------------------------------------------------------- dependencies
info "Checking build dependencies"
missing=()
for tool in gcc g++ make dpkg-deb; do
    command -v "$tool" >/dev/null 2>&1 || missing+=("$tool")
done
if [ ${#missing[@]} -eq 0 ]; then
    tmp_test="$(mktemp -d)"
    trap 'rm -rf "$tmp_test"' EXIT
    printf 'int main(void){return 0;}\n' > "$tmp_test/t.c"
    printf '#include <cstdio>\nint main(){std::printf("x");return 0;}\n' > "$tmp_test/t.cpp"
    gcc -m32 "$tmp_test/t.c"   -o "$tmp_test/t32"   >/dev/null 2>&1 || missing+=("32-bit C toolchain")
    g++ -m32 "$tmp_test/t.cpp" -o "$tmp_test/t32pp" >/dev/null 2>&1 || missing+=("32-bit C++ toolchain")
fi
if [ ${#missing[@]} -gt 0 ]; then
    printf 'Missing: %s\n\n' "${missing[*]}" >&2
    die "Install the build dependencies first:

    sudo apt install build-essential gcc-multilib g++-multilib libx11-dev libgl-dev libvulkan-dev dpkg-dev
"
fi

# ---------------------------------------------------------------- GCC 15 fix
# Newer GCC/libstdc++ no longer pulls in <cstdio> indirectly, so overlay.cpp
# fails with "'stderr' was not declared in this scope". Idempotent.
if ! grep -q '#include <cstdio>' src/vulkan/overlay.cpp; then
    info "Applying GCC 15 fix (#include <cstdio>) to src/vulkan/overlay.cpp"
    if grep -q '#include "limiter.h"' src/vulkan/overlay.cpp; then
        sed -i '0,/#include "limiter.h"/s//#include "limiter.h"\n#include <cstdio>/' src/vulkan/overlay.cpp
    else
        sed -i '1i #include <cstdio>' src/vulkan/overlay.cpp
    fi
else
    info "GCC 15 fix already present"
fi

# ---------------------------------------------------------------- version
ARCH="$(dpkg --print-architecture)"
if [ -z "${VERSION:-}" ]; then
    if git -C "$SRC" rev-parse --git-dir >/dev/null 2>&1; then
        VERSION="0.0.0+git$(git -C "$SRC" log -1 --format=%cd --date=format:%Y%m%d).$(git -C "$SRC" rev-parse --short HEAD)"
    else
        VERSION="0.0.0+$(date +%Y%m%d)"
    fi
fi
if [ -z "${MAINTAINER:-}" ]; then
    gname="$(git config --get user.name 2>/dev/null || true)"
    gmail="$(git config --get user.email 2>/dev/null || true)"
    if [ -n "$gname" ] && [ -n "$gmail" ]; then
        MAINTAINER="$gname <$gmail>"
    else
        MAINTAINER="libstrangle packager <noreply@localhost>"
    fi
fi
info "Package version: $VERSION ($ARCH)"

# ---------------------------------------------------------------- build
# Debian packages belong in /usr, not /usr/local. Use PREFIX if the makefile has it.
MAKEFILE="makefile"; [ -f makefile ] || MAKEFILE="Makefile"
prefix_args=()
if grep -Eq '^[[:space:]]*PREFIX[[:space:]]*[?:]?=' "$MAKEFILE"; then
    prefix_args=(PREFIX=/usr)
elif grep -Eq '^[[:space:]]*prefix[[:space:]]*[?:]?=' "$MAKEFILE"; then
    prefix_args=(prefix=/usr)
else
    info "The makefile has no PREFIX variable; files will be relocated from /usr/local to /usr after staging."
fi

info "Building (32-bit and 64-bit, OpenGL and Vulkan)"
make clean >/dev/null 2>&1 || rm -rf build
make "${prefix_args[@]}" -j"$(nproc)"

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE" "${tmp_test:-}"' EXIT
ROOT="$STAGE/root"
mkdir -p "$ROOT"

info "Staging files"
# Run as a normal user: if DESTDIR were ignored, this fails with
# "Permission denied" instead of touching your system.
make install DESTDIR="$ROOT" "${prefix_args[@]}" \
    || die "'make install DESTDIR=...' failed. If the error is 'Permission denied', this makefile does not support DESTDIR."

[ -n "$(find "$ROOT" -type f -print -quit)" ] || die "Nothing was staged; the makefile ignored DESTDIR."

# ---------------------------------------------------------------- relocate
# Makefiles with a hard-coded /usr/local: move the files to /usr and fix the
# paths in text files (ld.so.conf entry, Vulkan layer JSON, wrapper scripts).
# Compiled libraries are checked too; if one embeds /usr/local, relocation is
# skipped so the package keeps working.
if [ -d "$ROOT/usr/local" ]; then
    binaries_with_path=""
    while IFS= read -r -d '' f; do
        if ! grep -qI '' "$f" && grep -qa '/usr/local' "$f"; then
            binaries_with_path+="${f#"$ROOT"}"$'\n'
        fi
    done < <(find "$ROOT" -type f -print0)

    if [ -n "$binaries_with_path" ]; then
        warn "These compiled files contain /usr/local, so files stay under /usr/local:"
        printf '%s' "$binaries_with_path" >&2
    else
        info "Relocating /usr/local -> /usr"
        mkdir -p "$ROOT/usr"
        cp -a "$ROOT/usr/local/." "$ROOT/usr/"
        rm -rf "$ROOT/usr/local"
        while IFS= read -r -d '' f; do
            if grep -qI '' "$f" && grep -q '/usr/local' "$f"; then
                sed -i 's|/usr/local|/usr|g' "$f"
            fi
        done < <(find "$ROOT" -type f -print0)
    fi
fi

if grep -rIl '/usr/local' "$ROOT" >/dev/null 2>&1; then
    warn "Some staged files still mention /usr/local:"
    grep -rIl '/usr/local' "$ROOT" | sed "s|$ROOT||" >&2
fi

# ---------------------------------------------------------------- docs
DOCDIR="$ROOT/usr/share/doc/libstrangle"
mkdir -p "$DOCDIR"
# Prefer the upstream usage documentation if the packaging README replaced it.
if [ -f README.upstream.md ]; then
    install -m 0644 README.upstream.md "$DOCDIR/README.md"
elif [ -f README.md ]; then
    install -m 0644 README.md "$DOCDIR/README.md"
fi
[ -f COPYING ]   && install -m 0644 COPYING   "$DOCDIR/copyright"

# ---------------------------------------------------------------- control files
mkdir -p "$ROOT/DEBIAN"
SIZE_KB="$(du -sk --exclude=DEBIAN "$ROOT" | cut -f1)"

cat > "$ROOT/DEBIAN/control" <<EOF
Package: libstrangle
Version: $VERSION
Architecture: $ARCH
Maintainer: $MAINTAINER
Installed-Size: $SIZE_KB
Depends: libc6, libstdc++6
Section: games
Priority: optional
Homepage: https://gitlab.com/torkel104/libstrangle
Description: frame rate limiter for OpenGL and Vulkan games
 libstrangle caps the frame rate of OpenGL and Vulkan applications,
 including Windows games running through Wine/Proton (DXVK, VKD3D).
 .
 Usage in a terminal:  strangle 30 /path/to/game
 Usage in Steam launch options:  strangle 30 %command%
 .
 Includes 32-bit and 64-bit libraries. 32-bit games additionally need the
 i386 C/C++ runtime (libc6:i386, libstdc++6:i386), which Steam already pulls in.
EOF

# Files under /etc are configuration files.
find "$ROOT/etc" -type f 2>/dev/null | sed "s|^$ROOT||" > "$ROOT/DEBIAN/conffiles" || true
[ -s "$ROOT/DEBIAN/conffiles" ] || rm -f "$ROOT/DEBIAN/conffiles"

# Refresh the dynamic linker cache after install/remove.
echo "activate-noawait ldconfig" > "$ROOT/DEBIAN/triggers"

( cd "$ROOT" && find . -path ./DEBIAN -prune -o -type f -print0 \
    | sort -z | xargs -0 md5sum | sed 's|  \./|  |' ) > "$STAGE/md5sums"
mv "$STAGE/md5sums" "$ROOT/DEBIAN/md5sums"

chmod 0755 "$ROOT/DEBIAN"
chmod 0644 "$ROOT/DEBIAN"/*

# ---------------------------------------------------------------- package
OUTDIR="$SRC/dist"
mkdir -p "$OUTDIR"
DEB="$OUTDIR/libstrangle_${VERSION}_${ARCH}.deb"
info "Creating package"
dpkg-deb --root-owner-group --build "$ROOT" "$DEB" >/dev/null

info "Package contents:"
dpkg-deb --contents "$DEB" | awk '{print "    " $6}' | grep -v '/$'

printf '\n\033[1;32mDone:\033[0m %s\n\n' "$DEB"
echo "Install it with:"
echo "    sudo apt install ./dist/$(basename "$DEB")"
echo "Remove it with:"
echo "    sudo apt remove libstrangle"
