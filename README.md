# libstrangle for Debian / Ubuntu

Build scripts that turn [libstrangle](https://gitlab.com/torkel104/libstrangle), a frame rate limiter for OpenGL and Vulkan games (including Proton/DXVK/VKD3D), into a proper `.deb` package for Debian, Ubuntu, Kubuntu, Linux Mint, Pop!_OS and other derivatives.

libstrangle is not packaged in the Debian or Ubuntu repositories, and the upstream source no longer builds with GCC 15. This kit fixes that.

## What this kit does

- **Fixes the GCC 15 build error** in `src/vulkan/overlay.cpp` (`'stderr' was not declared in this scope`) by adding the missing `#include <cstdio>`.
- **Builds 32-bit and 64-bit** libraries, for both OpenGL and Vulkan.
- **Installs to `/usr`** instead of `/usr/local`, as Debian packages should.
- **Produces a `.deb`**, so you can install, update and remove libstrangle with `apt`, and the dynamic linker cache is refreshed automatically.

The build runs as a normal user and never touches your system. Only `apt install` at the end needs `sudo`.

## Build from source

```sh
# 1. Build dependencies
sudo apt install git build-essential gcc-multilib g++-multilib \
                 libx11-dev libgl-dev libvulkan-dev dpkg-dev

# 2. Upstream source
git clone https://gitlab.com/torkel104/libstrangle.git
cd libstrangle

# 3. Build the package (put build-deb.sh in this directory first)
./build-deb.sh

# 4. Install
sudo apt install ./dist/libstrangle_*.deb
```

## Prebuilt package

A `.deb` is attached to the releases of this repository. It was built on **Ubuntu 26.04 / Kubuntu 26.04**.

A package built on a newer distribution can fail to load on an older one (glibc version). If the prebuilt package does not work on your system, build it from source with the steps above. That takes about a minute.

## Usage

Steam launch options (right-click the game → Properties → Launch Options):

```
strangle 30 %command%
```

For Vulkan only (also covers Proton games through DXVK/VKD3D):

```
stranglevk 30 %command%
```

From a terminal:

```sh
strangle 60 /path/to/game
```

See the upstream README (installed to `/usr/share/doc/libstrangle/README.md`) for more options such as VSync control.

## If you installed with `sudo make install` before

A manual install puts files under `/usr/local`, which takes priority over the package. Remove it first:

```sh
./remove-manual-install.sh
```

The script lists the files, asks for confirmation and runs `ldconfig`.

## Uninstall

```sh
sudo apt remove libstrangle
```

## Options

| Variable | Default | Purpose |
|---|---|---|
| `VERSION` | taken from the git commit | package version |
| `MAINTAINER` | taken from `git config` | maintainer field |

Example: `VERSION=1.0 ./build-deb.sh`

## Credits and license

libstrangle is developed upstream at <https://gitlab.com/torkel104/libstrangle>; all credit for the limiter itself goes to its authors. It is licensed under the GNU GPL v3; these packaging scripts are released under the same license.
