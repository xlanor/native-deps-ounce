#!/usr/bin/env bash

toolchain_architectures() { printf '%s\n' aarch64; }

toolchain_check_config() {
  jq -e '.config.toolchain | (.image | type) == "string" and (.gcc | type) == "string"
           and (.packages | type) == "array" and (.packages | all(type == "string"))' \
    "$(_manifest_json)" >/dev/null || die "config/$PLATFORM.toml: [toolchain] needs string image and gcc and a packages list"
  config_get '.config.toolchain.gcc' | grep -qE '^[0-9]+$' \
    || die "config/$PLATFORM.toml: toolchain.gcc must be a major version like 16"
}

toolchain_gcc() { printf '%s/devkitA64/bin/aarch64-none-elf-gcc' "${DEVKITPRO:-/opt/devkitpro}"; }

toolchain_sdk_version() { sed -n 's/^ounce-sdk //p' "${DEVKITPRO:-/opt/devkitpro}/ounce-sdk-version.txt" 2>/dev/null; }

toolchain_id() {
  printf 'devkitA64 gcc %s ounce-sdk %s cmake %s' \
    "$("$(toolchain_gcc)" -dumpfullversion 2>/dev/null)" \
    "$(toolchain_sdk_version)" \
    "$(cmake --version 2>/dev/null | sed -n '1s/^cmake version //p')"
}

toolchain_setup() {
  local tool wanted_gcc bin ounce cpu
  [ "$(uname -s)" = Linux ] || die "ounce builds must run on Linux, inside $(config_get '.config.toolchain.image')"
  [ "$ARCH" = aarch64 ] || die "ounce builds target aarch64 only"
  DEVKITPRO=${DEVKITPRO:-/opt/devkitpro}
  ounce="$DEVKITPRO/libounce"
  [ -f "$ounce/lib/libounce.a" ] || die "libounce not found under $DEVKITPRO; build inside $(config_get '.config.toolchain.image')"
  [ -n "$(toolchain_sdk_version)" ] || die "$DEVKITPRO/ounce-sdk-version.txt is missing; install the ounce SDK again"
  for tool in make cmake ninja python3 perl patch git; do need "$tool"; done
  bin="$DEVKITPRO/devkitA64/bin"
  export PATH="$bin:$PATH"
  [ -x "$(toolchain_gcc)" ] || die "aarch64-none-elf-gcc not found in $bin"
  wanted_gcc=$(config_get '.config.toolchain.gcc')
  [ "$("$(toolchain_gcc)" -dumpversion | cut -d. -f1)" = "$wanted_gcc" ] \
    || die "devkitA64 gcc $("$(toolchain_gcc)" -dumpfullversion) found but the pin is gcc $wanted_gcc; build inside $(config_get '.config.toolchain.image')"
  cpu=$(sed -n 's/^SWITCH2_CPU[[:space:]]*:=[[:space:]]*//p' "$ounce/switch2_cpu.mk")
  [ -n "$cpu" ] || die "no SWITCH2_CPU in $ounce/switch2_cpu.mk"

  MIN=""
  SDK_NAME=""
  SDK_PATH=""
  MIN_FLAG=""
  CC="$bin/aarch64-none-elf-gcc"
  CXX="$bin/aarch64-none-elf-g++"
  MESON_SYSTEM=horizon
  MESON_CPU_FAMILY=aarch64
  ARCH_FLAGS="$cpu -mtp=soft -fPIE -ftls-model=local-exec -ffunction-sections -fdata-sections -D__SWITCH__ -D__SWITCH2__ -isystem $ounce/include -isystem $DEVKITPRO/portlibs/switch2/include -O2"
  ARCH_LDFLAGS="-specs=$ounce/switch.specs -L$ounce/lib -L$DEVKITPRO/portlibs/switch2/lib"
  HOST_TRIPLE=aarch64-none-elf
  HOST_PKGCONFIG="$DEVKITPRO/portlibs/switch2/lib/pkgconfig"
  OPENSSL_TARGET=""
  OPENSSL_FLAGS=""
}

toolchain_cross() { return 0; }

toolchain_cmake_args() {
  printf -- '-G Ninja -DCMAKE_TOOLCHAIN_FILE=%s/libounce/cmake/Switch2.cmake -DCMAKE_FIND_ROOT_PATH_MODE_PACKAGE=BOTH -DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=BOTH -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=BOTH' "${DEVKITPRO:-/opt/devkitpro}"
}

toolchain_host_cmake_args() { :; }

toolchain_meson_args() { :; }

toolchain_dep_ldflags() { printf -- '-L%s' "$1"; }

toolchain_release_notes() {
  local pools=$1
  echo "| Container | \`$(config_get '.config.toolchain.image')\` |"
  echo "| GCC | $(config_get '.config.toolchain.gcc') |"
  echo "| Toolchain | $(for i in "$pools"/*/BUILD-INFO "$pools"/*/*/BUILD-INFO "$pools"/*/*/*/BUILD-INFO; do [ -f "$i" ] && jq -r '.toolchain' "$i"; done | sort -u | paste -s -d';' - | sed 's/;/<br>/g') |"
}
