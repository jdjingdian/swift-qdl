#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Default install prefix inside project
PREFIX="${PREFIX:-$ROOT_DIR/third_party}"
JOBS="${JOBS:-$(sysctl -n hw.ncpu)}"

log() { echo "[build_submodules] $*"; }

ensure_prefix() {
  mkdir -p "$PREFIX"
  log "Install prefix: $PREFIX"
}

fix_install_names() {
  local prefix="${1:-$PREFIX}"
  log "Fixing install names in $prefix/lib and $prefix/lib64"
  for libdir in "$prefix/lib" "$prefix/lib64"; do
    [ -d "$libdir" ] || continue
    while IFS= read -r -d $'\0' dylib; do
      name=$(basename "$dylib")
      newid="@rpath/$name"
      log "  setting id of $dylib -> $newid"
      install_name_tool -id "$newid" "$dylib" || log "    install_name_tool -id failed for $dylib"

      # Fix dependencies that point inside the prefix
      otool -L "$dylib" | tail -n +2 | while read -r dep_line; do
        dep_path=$(echo "$dep_line" | awk '{print $1}')
        case "$dep_path" in
          "$prefix"/*)
            dep_name=$(basename "$dep_path")
            new_dep="@rpath/$dep_name"
            log "    changing dep $dep_path -> $new_dep"
            install_name_tool -change "$dep_path" "$new_dep" "$dylib" || log "      install_name_tool -change failed for $dylib"
            ;;
          *) ;;
        esac
      done
    done < <(find "$libdir" -name "*.dylib" -print0)
  done
  log "install_name fixup complete"
}

build_autotools() {
  local src="$1"
  pushd "$src" >/dev/null
  if [ -x ./autogen.sh ]; then
    log "Running autogen.sh in $src"
    ./autogen.sh
  fi
  if [ -x ./configure ] || [ -f ./configure ]; then
    log "Configuring (autotools) $src"
    ./configure --prefix="$PREFIX" || { log "configure failed"; return 1; }
    log "Making (autotools) $src"
    make -j "$JOBS"
    log "Installing (autotools) $src"
    make install
  else
    log "No configure found in $src"
    return 1
  fi
  popd >/dev/null
}

build_meson() {
  local src="$1"
  local builddir="$src/build-meson"
  if ! command -v meson >/dev/null 2>&1; then
    log "meson not installed, skipping meson build for $src"
    return 1
  fi
  pushd "$src" >/dev/null
  log "Running meson setup for $src (builddir: $builddir)"
  rm -rf "$builddir"
  meson setup "$builddir" --prefix="$PREFIX"
  meson compile -C "$builddir" -j "$JOBS"
  meson install -C "$builddir"
  popd >/dev/null
}

build_module() {
  local modpath="$1"
  if [ ! -d "$modpath" ]; then
    log "Module directory not found: $modpath"
    return 1
  fi

  # Prefer meson if meson.build exists
  if [ -f "$modpath/meson.build" ]; then
    build_meson "$modpath" || build_autotools "$modpath"
  else
    build_autotools "$modpath"
  fi
}

usage() {
  cat <<EOF
Usage: $(basename "$0") [--fix]

Environment:
  PREFIX - install destination (default: $ROOT_DIR/third_party)
  JOBS   - parallel jobs for make (default: detected CPU count)
EOF
}

main() {
  local run_fix=0
  if [ "${1-}" = "--fix" ]; then
    run_fix=1
  fi

  ensure_prefix

  log "Building libxml2"
  build_module "$ROOT_DIR/modules/libxml2"

  log "Building libusb"
  build_module "$ROOT_DIR/modules/libusb"

  # Prepare environment so qdl will pick up our built libraries
  log "Configuring environment for qdl to use built libusb/libxml2"
  export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig:$PREFIX/share/pkgconfig:${PKG_CONFIG_PATH:-}"
  export CPPFLAGS="-I$PREFIX/include ${CPPFLAGS:-}"
  export LDFLAGS="-L$PREFIX/lib ${LDFLAGS:-}"

  # Find qdl source: prefer top-level qdl/, fallback to modules/qdl
  if [ -d "$ROOT_DIR/qdl" ]; then
    QDL_SRC="$ROOT_DIR/qdl"
  elif [ -d "$ROOT_DIR/modules/qdl" ]; then
    QDL_SRC="$ROOT_DIR/modules/qdl"
  else
    log "qdl source not found at $ROOT_DIR/qdl or $ROOT_DIR/modules/qdl; skipping qdl build"
    QDL_SRC=""
  fi

  if [ -n "$QDL_SRC" ]; then
    # Create a working copy of qdl to apply patches and build against third-party libs
    THIRD_BUILD="$ROOT_DIR/third_party_build"
    log "Preparing qdl working copy in $THIRD_BUILD (from $QDL_SRC)"
    rm -rf "$THIRD_BUILD"
    mkdir -p "$THIRD_BUILD"
    rsync -a "$QDL_SRC/" "$THIRD_BUILD/qdl/"
  fi

  # If there's a repo patch to enable lib support, apply it inside the working copy
  PATCH_FILE="$ROOT_DIR/patch/0001-add-support-for-lib.patch"
  if [ -n "$QDL_SRC" ] && [ -f "$PATCH_FILE" ]; then
    log "Applying patch $PATCH_FILE to qdl working copy"
    pushd "$THIRD_BUILD/qdl" >/dev/null
    # Try git apply first (handles a/ b/ prefixes); fall back to patch -p1
    if command -v git >/dev/null 2>&1; then
      if git apply --check "$PATCH_FILE" >/dev/null 2>&1; then
        git apply "$PATCH_FILE" || log "git apply failed (non-fatal)"
      else
        # try without check (some patches may still apply)
        git apply "$PATCH_FILE" || {
          log "git apply failed, trying patch -p1"
          patch -p1 < "$PATCH_FILE" || log "patch failed (non-fatal)"
        }
      fi
    else
      patch -p1 < "$PATCH_FILE" || log "patch failed (non-fatal)"
    fi
    popd >/dev/null
  else
    if [ -n "$QDL_SRC" ]; then
      log "No qdl patch found at $PATCH_FILE; building vanilla qdl"
    fi
  fi

  # Build qdl in the working copy and install lib into PREFIX
  if [ -n "$QDL_SRC" ]; then
    log "Building qdl against third-party libs"
    pushd "$THIRD_BUILD/qdl" >/dev/null
  # Try to get pkg-config flags from the prefix so the build links against our built libs
  PKG_CFLAGS="$(PKG_CONFIG_PATH="$PKG_CONFIG_PATH" pkg-config --cflags libxml-2.0 libusb-1.0 2>/dev/null || true)"
  PKG_LIBS="$(PKG_CONFIG_PATH="$PKG_CONFIG_PATH" pkg-config --libs libxml-2.0 libusb-1.0 2>/dev/null || true)"
  # If pkg-config didn't return library flags, fall back to common names
  if [ -z "$PKG_LIBS" ]; then
    PKG_LIBS="-lxml2 -lusb-1.0"
  fi

  # Try to build default target then lib target (Makefile additions may provide 'lib' target)
  make -j "$JOBS" CPPFLAGS="$CPPFLAGS $PKG_CFLAGS" LDFLAGS="$LDFLAGS $PKG_LIBS" PKG_CONFIG_PATH="$PKG_CONFIG_PATH" || {
    log "qdl make failed"
    popd >/dev/null
    exit 1
  }
  # If a lib target exists, build it
  if make -n lib >/dev/null 2>&1; then
    make -j "$JOBS" lib CPPFLAGS="$CPPFLAGS" LDFLAGS="$LDFLAGS" PKG_CONFIG_PATH="$PKG_CONFIG_PATH" || log "make lib failed (non-fatal)"
  fi
  # Install lib if install-lib target exists
  if make -n install-lib >/dev/null 2>&1; then
    make install-lib prefix="$PREFIX" || log "make install-lib failed (non-fatal)"
  else
    # Fallback: copy produced lib files into PREFIX/lib
    mkdir -p "$PREFIX/lib"
    find . -maxdepth 1 -type f -name "libqdl*.dylib" -exec cp -v {} "$PREFIX/lib/" \; || true
  fi
    popd >/dev/null
  else
    log "Skipping qdl build because source not available"
  fi

  log "Build finished. Installed under $PREFIX"

  log "Running internal fix_install_names"
  fix_install_names "$PREFIX"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  if [ "${1-}" = "-h" ] || [ "${1-}" = "--help" ]; then
    usage
    exit 0
  fi
  main "$@"
fi
