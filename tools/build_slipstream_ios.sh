#!/usr/bin/env bash
#
# build_slipstream_ios.sh
#
# Cross-compiles the Slipstream client as a STATIC LIBRARY for iOS (arm64) and
# macOS (arm64, x86_64), then packages everything into an xcframework for SPM.
#
# The Slipstream client is embedded in-process (like C-Tor) — not as a separate
# executable, because iOS does not allow posix_spawn of child processes.
#
# Prerequisites:
#   - Xcode (with iOS SDK) installed
#   - Meson + Ninja installed (brew install meson ninja)
#   - CMake + pkg-config installed (brew install cmake pkg-config)
#   - Git (to clone Slipstream source)
#
# Usage:
#   ./tools/build_slipstream_ios.sh
#
# Output:
#   localPackages/Slipstream/Frameworks/slipstream-client.xcframework
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$PROJECT_ROOT/build/slipstream"
SLIPSTREAM_SRC="$BUILD_DIR/slipstream"
OUTPUT_DIR="$BUILD_DIR/output"
XCFW_OUTPUT="$PROJECT_ROOT/localPackages/Slipstream/Frameworks/slipstream-client.xcframework"

# Slipstream repo (official)
SLIPSTREAM_REPO="https://github.com/EndPositive/slipstream.git"
SLIPSTREAM_BRANCH="main"

# iOS deployment target
IOS_MIN_VERSION="15.0"
MACOS_MIN_VERSION="12.0"

# OpenSSL version for cross-compilation
OPENSSL_VERSION="3.3.2"

# ── Validation ──────────────────────────────────────────────────────────

if ! command -v meson &>/dev/null; then
    echo "ERROR: meson not found. Install via: brew install meson"
    exit 1
fi
if ! command -v ninja &>/dev/null; then
    echo "ERROR: ninja not found. Install via: brew install ninja"
    exit 1
fi
if ! command -v cmake &>/dev/null; then
    echo "ERROR: cmake not found. Install via: brew install cmake"
    exit 1
fi
if ! command -v xcrun &>/dev/null; then
    echo "ERROR: Xcode tools not found. Install Xcode."
    exit 1
fi

# Detect SDK paths
IOS_SDK=$(xcrun --sdk iphoneos --show-sdk-path 2>/dev/null || echo "")
MACOS_SDK=$(xcrun --sdk macosx --show-sdk-path 2>/dev/null || echo "")

echo "═══════════════════════════════════════════════════════════"
echo " Slipstream iOS/macOS — Static Library Build"
echo "═══════════════════════════════════════════════════════════"
echo " iOS SDK:   $IOS_SDK"
echo " macOS SDK: $MACOS_SDK"
echo " Output:    $XCFW_OUTPUT"
echo "═══════════════════════════════════════════════════════════"

# ── Clone / Update Slipstream source ────────────────────────────────────

mkdir -p "$BUILD_DIR"

if [ -d "$SLIPSTREAM_SRC/.git" ]; then
    echo "→ Updating Slipstream source..."
    cd "$SLIPSTREAM_SRC"
    git fetch origin
    git checkout "$SLIPSTREAM_BRANCH"
    git pull --ff-only origin "$SLIPSTREAM_BRANCH" || true
    git submodule update --init --recursive
else
    echo "→ Cloning Slipstream..."
    git clone --recursive -b "$SLIPSTREAM_BRANCH" "$SLIPSTREAM_REPO" "$SLIPSTREAM_SRC"
fi

cd "$SLIPSTREAM_SRC"

# ── Patch source for iOS in-process embedding ───────────────────────────
# The upstream Slipstream client calls exit(EXIT_FAILURE) on socket errors,
# which terminates the entire iOS app. Replace with graceful return -1.
# Also close the TCP listen socket on normal exit to prevent bind() failures
# when restarting (the upstream code leaks the socket).
echo "→ Patching Slipstream source for in-process embedding..."
sed -i '' 's/exit(EXIT_FAILURE);/picoquic_free(quic); return -1;/' src/slipstream_client.c
sed -i '' 's/printf("Client exit, ret = %d\\n", ret);/close(client_ctx.listen_sock); printf("Client exit, ret = %d\\n", ret);/' src/slipstream_client.c

# ── Cross-compile OpenSSL ───────────────────────────────────────────────

OPENSSL_SRC="$BUILD_DIR/openssl-src"
OPENSSL_TARBALL="$BUILD_DIR/openssl-${OPENSSL_VERSION}.tar.gz"

if [ ! -f "$OPENSSL_TARBALL" ]; then
    echo "→ Downloading OpenSSL ${OPENSSL_VERSION}..."
    curl -L -o "$OPENSSL_TARBALL" \
        "https://www.openssl.org/source/openssl-${OPENSSL_VERSION}.tar.gz"
fi

if [ ! -d "$OPENSSL_SRC" ]; then
    echo "→ Extracting OpenSSL..."
    tar -xzf "$OPENSSL_TARBALL" -C "$BUILD_DIR"
    mv "$BUILD_DIR/openssl-${OPENSSL_VERSION}" "$OPENSSL_SRC"
fi

build_openssl() {
    local PLATFORM="$1"
    local ARCH="$2"
    local SDK_PATH="$3"
    local MIN_FLAG="$4"
    local OPENSSL_INSTALL="$BUILD_DIR/openssl-${PLATFORM}-${ARCH}"

    if [ -f "$OPENSSL_INSTALL/lib/libssl.a" ]; then
        echo "→ OpenSSL for $PLATFORM-$ARCH already built, skipping."
        return
    fi

    echo "→ Building OpenSSL for $PLATFORM-$ARCH..."

    local OPENSSL_BUILD="$BUILD_DIR/openssl-build-${PLATFORM}-${ARCH}"
    rm -rf "$OPENSSL_BUILD"
    cp -r "$OPENSSL_SRC" "$OPENSSL_BUILD"
    cd "$OPENSSL_BUILD"

    local OPENSSL_TARGET
    if [ "$PLATFORM" = "ios" ] && [ "$ARCH" = "arm64" ]; then
        OPENSSL_TARGET="ios64-xcrun"
    elif [ "$PLATFORM" = "macos" ] && [ "$ARCH" = "arm64" ]; then
        OPENSSL_TARGET="darwin64-arm64-cc"
    elif [ "$PLATFORM" = "macos" ] && [ "$ARCH" = "x86_64" ]; then
        OPENSSL_TARGET="darwin64-x86_64-cc"
    fi

    local EXTRA_FLAGS=""
    if [ "$PLATFORM" = "ios" ]; then
        EXTRA_FLAGS="-isysroot $SDK_PATH $MIN_FLAG"
    fi

    ./Configure "$OPENSSL_TARGET" \
        --prefix="$OPENSSL_INSTALL" \
        no-shared no-tests no-ui-console \
        $EXTRA_FLAGS \
        2>&1 | tail -3

    make -j"$(sysctl -n hw.ncpu)" 2>&1 | tail -3
    make install_sw 2>&1 | tail -3

    cd "$SLIPSTREAM_SRC"
    echo "✓ OpenSSL for $PLATFORM-$ARCH installed at $OPENSSL_INSTALL"
}

# ── Build target and produce a merged .a ────────────────────────────────

build_target() {
    local PLATFORM="$1"
    local ARCH="$2"
    local SDK_PATH="$3"
    local MIN_VERSION_FLAG="$4"

    local BUILD_ABI_DIR="$BUILD_DIR/build-${PLATFORM}-${ARCH}"
    local CROSS_FILE="$BUILD_DIR/cross-${PLATFORM}-${ARCH}.ini"
    local OPENSSL_INSTALL="$BUILD_DIR/openssl-${PLATFORM}-${ARCH}"
    local LIB_OUT="$OUTPUT_DIR/${PLATFORM}-${ARCH}"

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo " Building Slipstream for $PLATFORM ($ARCH)"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    local CPU_FAMILY="$ARCH"
    if [ "$ARCH" = "arm64" ]; then
        CPU_FAMILY="aarch64"
    fi

    local SYSTEM="darwin"

    # CMake init script for OpenSSL paths and DTrace suppression
    local CMAKE_INIT="$BUILD_DIR/cmake-init-${PLATFORM}-${ARCH}.cmake"
    cat > "$CMAKE_INIT" <<CMAKEOF
set(DTRACE "DTRACE-NOTFOUND" CACHE FILEPATH "" FORCE)
set(OPENSSL_ROOT_DIR "${OPENSSL_INSTALL}" CACHE PATH "" FORCE)
set(OPENSSL_INCLUDE_DIR "${OPENSSL_INSTALL}/include" CACHE PATH "" FORCE)
set(OPENSSL_CRYPTO_LIBRARY "${OPENSSL_INSTALL}/lib/libcrypto.a" CACHE FILEPATH "" FORCE)
set(OPENSSL_SSL_LIBRARY "${OPENSSL_INSTALL}/lib/libssl.a" CACHE FILEPATH "" FORCE)
set(OPENSSL_USE_STATIC_LIBS TRUE CACHE BOOL "" FORCE)
CMAKEOF

    cat > "$CROSS_FILE" <<CROSSEOF
[binaries]
c = 'clang'
cpp = 'clang++'
ar = 'ar'
strip = 'strip'
pkgconfig = '$(command -v pkg-config)'
cmake = '$(command -v cmake)'

[built-in options]
c_args = ['-arch', '$ARCH', '-isysroot', '$SDK_PATH', '$MIN_VERSION_FLAG']
cpp_args = ['-arch', '$ARCH', '-isysroot', '$SDK_PATH', '$MIN_VERSION_FLAG']
c_link_args = ['-arch', '$ARCH', '-isysroot', '$SDK_PATH', '$MIN_VERSION_FLAG']
cpp_link_args = ['-arch', '$ARCH', '-isysroot', '$SDK_PATH', '$MIN_VERSION_FLAG']

[host_machine]
system = '$SYSTEM'
cpu_family = '$CPU_FAMILY'
cpu = '$ARCH'
endian = 'little'

[cmake]
CMAKE_PROJECT_INCLUDE = '${CMAKE_INIT}'
CMAKE_SYSTEM_NAME = 'Generic'
CROSSEOF

    rm -rf "$BUILD_ABI_DIR"

    echo "→ Configuring Meson for $PLATFORM-$ARCH..."
    meson setup "$BUILD_ABI_DIR" "$SLIPSTREAM_SRC" \
        --cross-file "$CROSS_FILE" \
        --buildtype=release \
        --strip \
        -Ddefault_library=static \
        2>&1 | tail -15

    echo "→ Building for $PLATFORM-$ARCH..."
    ninja -C "$BUILD_ABI_DIR" -j"$(sysctl -n hw.ncpu)" 2>&1 | tail -5

    # ── Merge all static libs + client .o files into one .a ──────────

    echo "→ Creating merged static library for $PLATFORM-$ARCH..."
    mkdir -p "$LIB_OUT"

    local LIBS_TO_MERGE=()

    # Client object files (EXCLUDE the CLI entry point — we provide our own via CSlipstreamHost.c)
    local CLIENT_OBJ_DIR="$BUILD_ABI_DIR/slipstream-client.p"
    if [ -d "$CLIENT_OBJ_DIR" ]; then
        local CLIENT_OBJS=()
        for obj in "$CLIENT_OBJ_DIR"/*.o; do
            local basename=$(basename "$obj")
            # Skip the CLI entry point (contains main())
            if [ "$basename" = "src_slipstream_client_cli.cpp.o" ]; then
                echo "  Skipping CLI entry point: $basename"
                continue
            fi
            CLIENT_OBJS+=("$obj")
        done
        if [ ${#CLIENT_OBJS[@]} -gt 0 ]; then
            ar rcs "$LIB_OUT/libslipstream_client_objs.a" "${CLIENT_OBJS[@]}"
            LIBS_TO_MERGE+=("$LIB_OUT/libslipstream_client_objs.a")
        fi
    fi

    # picoquic and picotls static libraries
    for lib in \
        "$BUILD_ABI_DIR/subprojects/picoquic/libpicoquic_core.a" \
        "$BUILD_ABI_DIR/subprojects/picoquic/libpicotls_core.a" \
        "$BUILD_ABI_DIR/subprojects/picoquic/libpicotls_minicrypto.a" \
        "$BUILD_ABI_DIR/subprojects/picoquic/libpicotls_openssl.a"; do
        if [ -f "$lib" ]; then
            LIBS_TO_MERGE+=("$lib")
        fi
    done

    # OpenSSL static libraries
    if [ -f "$OPENSSL_INSTALL/lib/libssl.a" ]; then
        LIBS_TO_MERGE+=("$OPENSSL_INSTALL/lib/libssl.a")
    fi
    if [ -f "$OPENSSL_INSTALL/lib/libcrypto.a" ]; then
        LIBS_TO_MERGE+=("$OPENSSL_INSTALL/lib/libcrypto.a")
    fi

    echo "  Merging ${#LIBS_TO_MERGE[@]} libraries..."
    libtool -static -o "$LIB_OUT/libslipstream.a" "${LIBS_TO_MERGE[@]}" 2>&1 | grep -v "has no symbols" || true

    # Copy required headers for the xcframework
    mkdir -p "$LIB_OUT/include"
    cp "$SLIPSTREAM_SRC/include/slipstream.h" "$LIB_OUT/include/"

    # Also copy picosocks.h (needed for picoquic_get_server_address)
    local PICOSOCKS_H=""
    PICOSOCKS_H=$(find "$BUILD_ABI_DIR" -name "picosocks.h" -type f | head -1)
    if [ -n "$PICOSOCKS_H" ]; then
        cp "$PICOSOCKS_H" "$LIB_OUT/include/"
    fi

    local SIZE=$(du -h "$LIB_OUT/libslipstream.a" | cut -f1)
    echo "✓ $PLATFORM-$ARCH: $LIB_OUT/libslipstream.a ($SIZE)"
}

# ── Phase 1: Build OpenSSL for all targets ──────────────────────────────

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " Phase 1: Building OpenSSL for all targets"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ -n "$IOS_SDK" ]; then
    build_openssl "ios" "arm64" "$IOS_SDK" "-miphoneos-version-min=$IOS_MIN_VERSION"
fi
if [ -n "$MACOS_SDK" ]; then
    build_openssl "macos" "arm64" "$MACOS_SDK" "-mmacosx-version-min=$MACOS_MIN_VERSION"
    build_openssl "macos" "x86_64" "$MACOS_SDK" "-mmacosx-version-min=$MACOS_MIN_VERSION"
fi

# ── Phase 2: Build Slipstream for all targets ───────────────────────────

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " Phase 2: Building Slipstream static libraries"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ -n "$IOS_SDK" ]; then
    build_target "ios" "arm64" "$IOS_SDK" "-miphoneos-version-min=$IOS_MIN_VERSION"
else
    echo "⚠ Skipping iOS build (SDK not found)"
fi

if [ -n "$MACOS_SDK" ]; then
    build_target "macos" "arm64" "$MACOS_SDK" "-mmacosx-version-min=$MACOS_MIN_VERSION"
    build_target "macos" "x86_64" "$MACOS_SDK" "-mmacosx-version-min=$MACOS_MIN_VERSION"
else
    echo "⚠ Skipping macOS builds (SDK not found)"
fi

# ── Phase 3: Create xcframework ─────────────────────────────────────────

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " Phase 3: Creating xcframework"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

rm -rf "$XCFW_OUTPUT"

# Create a fat macOS library (arm64 + x86_64)
MACOS_FAT_DIR="$OUTPUT_DIR/macos-universal"
rm -rf "$MACOS_FAT_DIR"
mkdir -p "$MACOS_FAT_DIR"
if [ -f "$OUTPUT_DIR/macos-arm64/libslipstream.a" ] && [ -f "$OUTPUT_DIR/macos-x86_64/libslipstream.a" ]; then
    echo "→ Creating universal macOS library..."
    lipo -create \
        "$OUTPUT_DIR/macos-arm64/libslipstream.a" \
        "$OUTPUT_DIR/macos-x86_64/libslipstream.a" \
        -output "$MACOS_FAT_DIR/libslipstream.a"
    cp -r "$OUTPUT_DIR/macos-arm64/include" "$MACOS_FAT_DIR/"
elif [ -f "$OUTPUT_DIR/macos-arm64/libslipstream.a" ]; then
    cp "$OUTPUT_DIR/macos-arm64/libslipstream.a" "$MACOS_FAT_DIR/"
    cp -r "$OUTPUT_DIR/macos-arm64/include" "$MACOS_FAT_DIR/"
fi

# Build xcframework arguments
XCFW_ARGS=()

if [ -f "$OUTPUT_DIR/ios-arm64/libslipstream.a" ]; then
    XCFW_ARGS+=(-library "$OUTPUT_DIR/ios-arm64/libslipstream.a" -headers "$OUTPUT_DIR/ios-arm64/include")
fi
if [ -f "$MACOS_FAT_DIR/libslipstream.a" ]; then
    XCFW_ARGS+=(-library "$MACOS_FAT_DIR/libslipstream.a" -headers "$MACOS_FAT_DIR/include")
fi

if [ ${#XCFW_ARGS[@]} -eq 0 ]; then
    echo "ERROR: No libraries built! Cannot create xcframework."
    exit 1
fi

echo "→ Creating xcframework..."
xcodebuild -create-xcframework "${XCFW_ARGS[@]}" -output "$XCFW_OUTPUT"

echo ""
echo "═══════════════════════════════════════════════════════════"
echo " Build complete!"
echo ""
echo " xcframework: $XCFW_OUTPUT"
echo ""
echo " The Slipstream client library is now embedded in the"
echo " localPackages/Slipstream package. Build the app normally."
echo "═══════════════════════════════════════════════════════════"
