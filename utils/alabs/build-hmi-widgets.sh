#!/bin/bash
# Builds the example plugins of the aLabs HMI widgets (src/alabs-hmi-widgets/examples) into DEST, with the
# specification bundle they refer to. It runs in the environment of a PawPaw target, which gives the compiler, its
# flags (macOS universal: both architectures at once) and the LV2 headers:
#
#   utils/run.sh TARGET utils/alabs/build-hmi-widgets.sh TARGET SRC DEST

set -e

TARGET=$1
SRC=$2
DEST=$3

case "$TARGET" in
    win*) EXT=.dll; SHARED=-shared ;;
    macos*) EXT=.dylib; SHARED=-dynamiclib ;;
    *) EXT=.so; SHARED="-shared -fPIC" ;;
esac

mkdir -p "$DEST"
cp -R "$SRC/alabs-hmi-widgets.lv2" "$DEST/"

for dir in "$SRC"/examples/*/; do
    name=$(basename "$dir")
    bundle=$DEST/$name.lv2
    rm -rf "$bundle"
    mkdir -p "$bundle"
    cp "$dir/$name.lv2"/*.ttl "$bundle/"
    sed -i.bak "s/$name\.so>/$name$EXT>/" "$bundle/manifest.ttl"
    rm -f "$bundle/manifest.ttl.bak"
    ${CC:-cc} ${CFLAGS} -O2 -std=gnu99 -fvisibility=hidden -I"$SRC/alabs-hmi-widgets.lv2" \
        "$dir/$name.c" $SHARED -o "$bundle/$name$EXT" ${LDFLAGS} -lm
    echo "$bundle/$name$EXT"
done
