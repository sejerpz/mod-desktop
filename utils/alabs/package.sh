#!/bin/bash
# Builds a alabs-mod-desktop package: this MOD Desktop, built with its mod-host (the HMI control of
# mod-hw-emulator), its mod-ui (HMI widgets, the HMI line over TCP) and its launcher (the Open Emulator button), and
# mod-hw-emulator (src/mod-hw-emulator) with the firmware of each device. It runs as it is, unpacked anywhere,
# apart from an installed MOD Desktop: mhe-desktop starts it.
#
#   utils/alabs/package.sh TARGET [OUT]
#
# TARGET is linux-x86_64, win64 or macos-universal-10.15, the PawPaw target MOD Desktop was built for, as
# mod-desktop's CI builds it (.github/workflows/alabs.yml does all of it):
#
#   src/PawPaw/.github/workflows/bootstrap-deps.sh TARGET
#   utils/apply-patches.sh
#   src/PawPaw/bootstrap-mod.sh TARGET
#   make                                    # make win64, make PAWPAW_TARGET=macos-universal-10.15
#
# OUT is the archive, alabs-mod-desktop-<os>.tar.xz or .zip by default. macOS: universal (Intel and Apple
# Silicon), ad-hoc signatures only, no Developer ID.

set -e

TARGET=$1
MD=$(cd "$(dirname "$0")/../.." && pwd)
EMU=$MD/src/mod-hw-emulator
RUN="$MD/utils/run.sh $TARGET"
NAME=alabs-mod-desktop
DEVICES="dwarf duox duo"

case "$TARGET" in
    linux-*) OS=linux; DEFAULT=$NAME-$TARGET.tar.xz ;;
    win64) OS=win64; DEFAULT=$NAME-win64.zip ;;
    macos-*) OS=macos; DEFAULT=$NAME-macos.zip ;;
    *) echo "usage: $0 linux-x86_64|win64|macos-universal-10.15 [OUT]" >&2; exit 1 ;;
esac
OUT=${2:-$DEFAULT}
case "$OUT" in /*) ;; *) OUT=$PWD/$OUT ;; esac

if [ ! -f "$EMU/Makefile" ]; then
    echo "no mod-hw-emulator in $EMU: git submodule update --init --recursive src/mod-hw-emulator" >&2
    exit 1
fi
if ! grep -q "tcp://" "$MD/src/mod-ui/mod/hmi.py"; then
    echo "src/mod-ui has no HMI line over TCP: it is not sejerpz/mod-ui devel" >&2
    exit 1
fi

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
PKG=$STAGE/$NAME
mkdir -p "$PKG/skins" "$PKG/devices"

# MOD Desktop as it is built, symlinks resolved, as its own packaging scripts copy it; DESKTOP_DESCRIPTOR is
# MOD Desktop's descriptor, which mhe-desktop rewrites for the device at each start
case $OS in
    linux)
        cp -aL "$MD/build" "$PKG/mod-desktop"
        DESKTOP_DESCRIPTOR=$PKG/mod-desktop/mod-hardware-descriptor.json
        ;;
    win64)
        cp -rL "$MD/build" "$PKG/mod-desktop"
        DESKTOP_DESCRIPTOR=$PKG/mod-desktop/mod-hardware-descriptor.json
        ;;
    macos)
        APP="$PKG/MOD Desktop.app"
        MACOS="$APP/Contents/MacOS"
        cp -RL "$MD/build/mod-desktop.app" "$APP"
        DESKTOP_DESCRIPTOR=$APP/Contents/Resources/mod-hardware-descriptor.json
        # what utils/macos/macos-pkg.sh does to the bundle: the frameworks flattened, the Qt and jack libraries
        # found inside it
        PREFIX=$HOME/PawPawBuilds/targets/$TARGET
        (
            cd "$APP/Contents"
            rm -rf Frameworks/*/*.prl Frameworks/*/Headers Frameworks/*/Versions MacOS/data
            for f in Frameworks/*/Qt* PlugIns/*/libq*.dylib; do
                for q in Core Gui OpenGL PrintSupport Svg Widgets; do
                    install_name_tool -change "@rpath/Qt$q.framework/Versions/5/Qt$q" "@executable_path/../Frameworks/Qt$q.framework/Qt$q" "$f"
                done
            done
            for f in MacOS/lib/libmod_utils.so MacOS/libjack*.dylib; do
                [ -e "$f" ] || continue
                install_name_tool -change "$PREFIX/lib/libjack.0.1.0.dylib" "@executable_path/libjack.0.dylib" "$f"
                install_name_tool -change "$PREFIX/lib/libjackserver.0.1.0.dylib" "@executable_path/libjackserver.0.dylib" "$f"
            done
            for f in MacOS/jackd MacOS/jack/*.so; do
                install_name_tool -change "$PREFIX/lib/libjack.0.1.0.dylib" "@executable_path/libjackserver.0.dylib" "$f"
                install_name_tool -change "$PREFIX/lib/libjackserver.0.1.0.dylib" "@executable_path/libjackserver.0.dylib" "$f"
            done
        )
        ;;
esac

# the emulator, with the Qt of MOD Desktop, and the firmware of each device
case $OS in
    linux)
        $RUN make -C "$EMU" BUILD=build-$TARGET all gui
        for d in $DEVICES; do
            $RUN make -C "$EMU" BUILD=build-$TARGET DEVICE=$d firmware
            cp -L "$EMU/build-$TARGET/fw-$d.so" "$PKG/"
        done
        cp "$EMU/build-$TARGET/mod-hw-emulator" "$EMU/build-$TARGET/mhe-run" "$PKG/"
        ;;
    win64)
        $RUN make -C "$EMU" BUILD=build-$TARGET all gui
        for d in $DEVICES; do
            $RUN make -C "$EMU" BUILD=build-$TARGET DEVICE=$d firmware
            cp "$EMU/build-$TARGET/fw-$d.dll" "$PKG/"
        done
        cp "$EMU"/build-$TARGET/{mod-hw-emulator.exe,mhe-run.exe} "$PKG/"
        mkdir -p "$PKG/platforms"
        PREFIX=$($RUN sh -c 'echo $PAWPAW_PREFIX')
        for dll in Qt5Core Qt5Gui Qt5Widgets; do
            cp "$PREFIX/bin/$dll.dll" "$PKG/" 2> /dev/null || cp "$MD/build/$dll.dll" "$PKG/"
        done
        cp "$PREFIX"/plugins/platforms/qwindows.dll "$PKG/platforms/" 2> /dev/null \
            || cp "$MD"/build/platforms/qwindows.dll "$PKG/platforms/"
        # whatever else the programs need from the toolchain (winpthread, the GCC runtimes when not static)
        for dll in $(x86_64-w64-mingw32-objdump -p "$PKG"/*.exe "$PKG"/*.dll "$PKG"/platforms/*.dll \
                     | awk '/DLL Name/ { print $3 }' | sort -u); do
            [ -e "$PKG/$dll" ] && continue
            for dir in "$PREFIX/bin" "$PREFIX/lib" /usr/x86_64-w64-mingw32/lib /usr/lib/gcc/x86_64-w64-mingw32/*-posix; do
                if [ -e "$dir/$dll" ]; then
                    cp "$dir/$dll" "$PKG/"
                    break
                fi
            done
        done
        ;;
    macos)
        # once per architecture (the Makefile builds one at a time) and joined: the programs in the bundle, with
        # its Qt, the firmwares next to it (ARCH_FLAGS through the environment: run.sh splits its arguments)
        ARCHS="x86_64 arm64"
        MIN_MACOS=10.15
        for a in $ARCHS; do
            export ARCH_FLAGS="-arch $a -mmacosx-version-min=$MIN_MACOS"
            $RUN make -C "$EMU" BUILD=build-macos-$a all gui
            for d in $DEVICES; do
                $RUN make -C "$EMU" BUILD=build-macos-$a DEVICE=$d firmware
            done
        done
        unset ARCH_FLAGS
        join() {
            lipo -create $(for a in $ARCHS; do echo "$EMU/build-macos-$a/$1"; done) -output "$2"
        }
        join mod-hw-emulator "$MACOS/mod-hw-emulator"
        join mhe-run "$MACOS/mhe-run"
        for d in $DEVICES; do
            join "fw-$d.dylib" "$PKG/fw-$d.dylib"
        done
        for q in Core Gui Widgets; do
            install_name_tool -change "@rpath/Qt$q.framework/Versions/5/Qt$q" "@executable_path/../Frameworks/Qt$q.framework/Qt$q" "$MACOS/mod-hw-emulator"
        done
        ;;
esac

# the device's descriptor with its drop-ins (the HMI widget areas); MOD Desktop's keeps what tells the desktop
# apart (name, binaries)
for d in $DEVICES; do
    cp -R "$EMU/devices/$d/skin" "$PKG/skins/$d"
    mkdir -p "$PKG/devices/$d"
    python3 "$EMU/scripts/merge-descriptor.py" "$EMU/devices/$d/mod-hardware-descriptor.json" \
            "$PKG/devices/$d/mod-hardware-descriptor.json"
    python3 "$EMU/scripts/merge-descriptor.py" "$EMU/devices/$d/mod-hardware-descriptor.json" \
            "$PKG/devices/$d/mod-desktop-descriptor.json" "$DESKTOP_DESCRIPTOR"
done
cp "$DESKTOP_DESCRIPTOR" "$PKG/devices/mod-desktop.json"

if [ $OS = win64 ]; then
    cp "$MD/utils/alabs/mhe-desktop.ps1" "$PKG/"
    sed 's/$/\r/' "$MD/utils/alabs/mhe-desktop.cmd" > "$PKG/mhe-desktop.cmd"
else
    cp "$MD/utils/alabs/mhe-desktop.sh" "$PKG/"
    chmod +x "$PKG/mhe-desktop.sh"
fi
cp "$MD/LICENSE" "$PKG/LICENSE"
cp "$EMU/LICENSE" "$PKG/LICENSE-mod-hw-emulator.txt"

if [ $OS = macos ]; then
    # mhe-desktop.sh writes the descriptor of the device here at each start: a link out of the sealed bundle
    rm "$DESKTOP_DESCRIPTOR"
    ln -s ../../../devices/current.json "$DESKTOP_DESCRIPTOR"
    cp "$PKG/devices/mod-desktop.json" "$PKG/devices/current.json"

    # ad-hoc signatures: install_name_tool breaks the ones the linker made, and Apple Silicon runs no unsigned
    # code (the bundle's main program is signed out of the bundle: in it, codesign would seal the whole bundle,
    # and mod-ui's Python files next to the programs are no code it can sign)
    find "$MACOS" "$APP/Contents/Frameworks" "$APP/Contents/PlugIns" "$PKG"/fw-*.dylib -type f \
         ! -path "$MACOS/mod-desktop" > "$STAGE/code.txt"
    while read -r f; do
        if file -b "$f" | grep -q Mach-O; then
            codesign --force -s - "$f"
        fi
    done < "$STAGE/code.txt"
    cp "$MACOS/mod-desktop" "$STAGE/mod-desktop"
    codesign --force -s - "$STAGE/mod-desktop"
    cp "$STAGE/mod-desktop" "$MACOS/mod-desktop"
    codesign --verify "$MACOS/mod-hw-emulator"
fi

# what it was built from
rev() { git -C "$1" rev-parse HEAD 2> /dev/null || echo unknown; }
describe() { git -C "$1" describe --tags --always --dirty 2> /dev/null || echo unknown; }
case $OS in
    linux) PLATFORM="Linux (${TARGET#linux-})" ;;
    win64) PLATFORM="Windows (x86_64)" ;;
    macos) PLATFORM="macOS (universal: Intel and Apple Silicon, 10.15 or later)" ;;
esac
{
    echo "alabs-mod-desktop $(describe "$MD"), for $PLATFORM"
    echo
    echo "Built from these sources; each is free software under its own license (GPL/AGPL: LICENSE*):"
    echo
    echo "mod-desktop       https://github.com/sejerpz/mod-desktop      $(rev "$MD") (VERSION $(cat "$MD/VERSION"))"
    echo "                  with its submodules (mod-ui and mod-host: sejerpz, branch devel):"
    git -C "$MD" submodule status 2> /dev/null | awk '{ printf "  %-40s %s\n", $2, $1 }'
    echo "mod-hw-emulator, with its submodules (firmwares and mod-system-control: sejerpz, branch devel):"
    git -C "$EMU" submodule status --recursive 2> /dev/null | awk '{ printf "  %-40s %s\n", $2, $1 }'
    echo
    echo "Not an official MOD Audio build: the Tone3000 integration has no client id and does not work."
    [ $OS != macos ] || echo "Not signed with a Developer ID: macOS asks before opening it the first time, see README.txt."
} | if [ $OS = win64 ]; then sed 's/$/\r/'; else cat; fi > "$PKG/SOURCES.txt"

if [ $OS = macos ]; then
    cat > "$PKG/README.txt" << EOF
alabs-mod-desktop for macOS

This package is not signed with an Apple Developer ID. macOS marks what is downloaded from the internet and then
refuses to run it ("damaged" or "cannot be verified"). Once, after unpacking, remove that mark:

    xattr -dr com.apple.quarantine $NAME

then start it from a terminal:

    $NAME/mhe-desktop.sh                  # --device duox for the Duo X, --device duo for the Duo

Its data (pedalboards, user files) is in $NAME/data, apart from an installed MOD Desktop
(--shared-data uses that one's, ~/Documents/MOD Desktop).
EOF
    # plugins of MOD Desktop that did not build for macOS (missing-plugins.txt, written by the release workflow)
    if [ -s "$MD/missing-plugins.txt" ]; then
        {
            echo
            echo "These plugins of MOD Desktop do not build for macOS yet and are not in this package:"
            echo
            sed 's/^/    /' "$MD/missing-plugins.txt"
        } >> "$PKG/README.txt"
    fi
fi

rm -f "$OUT"
case $OS in
    linux) tar cJf "$OUT" -C "$STAGE" $NAME ;;
    win64) (cd "$STAGE" && zip -qr -9 "$OUT" $NAME) ;;
    macos) (cd "$STAGE" && ditto -c -k --keepParent $NAME "$OUT") ;;
esac
echo "$OUT"
