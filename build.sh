#!/usr/bin/env bash
set -euo pipefail

# --- prerequisites ---
command -v git >/dev/null 2>&1 || { echo "ERROR: git not found"; exit 1; }
command -v cmake >/dev/null 2>&1 || { echo "ERROR: cmake not found"; exit 1; }
command -v ninja >/dev/null 2>&1 || { echo "ERROR: ninja not found"; exit 1; }
command -v curl >/dev/null 2>&1 || { echo "ERROR: curl not found"; exit 1; }

# --- variables ---
ASEPRITE_DIR="$HOME/aseprite"
BUILD_DIR="$HOME/aseprite/build"
ASEPRITE_VERSION="${ASEPRITE_VERSION:-}" # optionally set externally
SKIA_DIR="$HOME/skia"
SKIA_OUT_DIR="$SKIA_DIR/out/Release-x64"

# --- clone/update aseprite repo ---
if [ ! -d "$ASEPRITE_DIR/.git" ]; then
    rm -rf "$ASEPRITE_DIR"
    git clone --recursive --tags https://github.com/aseprite/aseprite.git "$ASEPRITE_DIR"
else
    git -C "$ASEPRITE_DIR" fetch --tags
fi

mkdir -p "$BUILD_DIR"

# --- get newest tag if ASEPRITE_VERSION not set ---
if [ -z "$ASEPRITE_VERSION" ]; then
    ASEPRITE_VERSION=$(git -C "$ASEPRITE_DIR" tag --sort=creatordate | tail -n1)
fi
echo "Building Aseprite version $ASEPRITE_VERSION"

# --- export version to GitHub Actions if running in workflow ---
if [ -n "$GITHUB_OUTPUT" ]; then
    echo "ASEPRITE_VERSION=$ASEPRITE_VERSION" >> "$GITHUB_OUTPUT"
fi

# --- update local repo to selected tag ---
git -C "$ASEPRITE_DIR" clean -fdx
git -C "$ASEPRITE_DIR" submodule foreach --recursive git clean -xfd
git -C "$ASEPRITE_DIR" fetch --depth=1 origin "refs/tags/$ASEPRITE_VERSION:refs/tags/$ASEPRITE_VERSION"
git -C "$ASEPRITE_DIR" reset --hard "$ASEPRITE_VERSION"
git -C "$ASEPRITE_DIR" submodule update --init --recursive

# --- patch version in CMakeLists.txt ---
python3 - <<EOF
v = open('$ASEPRITE_DIR/src/ver/CMakeLists.txt').read()
open('$ASEPRITE_DIR/src/ver/CMakeLists.txt', 'w').write(v.replace('1.x-dev', '${ASEPRITE_VERSION#1}'))
EOF

# --- download Skia if missing ---
if [ ! -d "$SKIA_DIR" ]; then
    mkdir -p "$SKIA_DIR"
    curl -sfLO https://github.com/aseprite/skia/releases/download/m124/Skia-Linux-Release-x64.zip
    unzip -q Skia-Linux-Release-x64.zip -d "$SKIA_DIR"
    rm Skia-Linux-Release-x64.zip
fi

# --- build aseprite ---
rm -rf "$BUILD_DIR"
cmake -S "$ASEPRITE_DIR" -B "$BUILD_DIR" \
    -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DLAF_BACKEND=skia \
    -DSKIA_DIR="$SKIA_DIR" \
    -DSKIA_OUT_DIR="$SKIA_OUT_DIR" \
    -DSKSHAPER_LIBRARY="$SKIA_OUT_DIR/libskshaper.a" \
    -DSKUNICODE_LIBRARY="$SKIA_OUT_DIR/libskunicode.a" \
    -DJPEG_LIBRARY=/usr/lib/x86_64-linux-gnu/libjpeg.so \
    -DJPEG_INCLUDE_DIR=/usr/include \
    -DFREETYPE_LIBRARY=/usr/lib/x86_64-linux-gnu/libfreetype.so \
    -DFREETYPE_INCLUDE_DIR=/usr/include/freetype2 \
    -DGIFLIB_LIBRARY=/usr/lib/x86_64-linux-gnu/libgif.so \
    -DGIFLIB_INCLUDE_DIR=/usr/include

ninja -C "$BUILD_DIR"

# --- package portable aseprite ---
OUTPUT_DIR="$HOME/aseprite-$ASEPRITE_VERSION"
rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

echo "# This file is here so Aseprite behaves as a portable program" > "$OUTPUT_DIR/aseprite.ini"
cp -r "$ASEPRITE_DIR/docs" "$OUTPUT_DIR/docs"
cp -r "$BUILD_DIR/bin/aseprite" "$OUTPUT_DIR/"
cp -r "$BUILD_DIR/bin/data" "$OUTPUT_DIR/data"

echo "Aseprite $ASEPRITE_VERSION build complete at $OUTPUT_DIR"

# --- copy to github directory if running in workflow ---
if [ -n "$GITHUB_WORKSPACE" ]; then
    GITHUB_DIR="$GITHUB_WORKSPACE/github"
    rm -rf "$GITHUB_DIR"
    cp -r "$OUTPUT_DIR" "$GITHUB_DIR"
    echo "Copied to $GITHUB_DIR for artifact upload"
fi
