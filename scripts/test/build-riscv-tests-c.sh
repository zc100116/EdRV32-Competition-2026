#!/usr/bin/env bash
# ============================================================================
# File        : build-riscv-tests-c.sh
# Author      : Edward ZC
# Description : Build the official riscv-tests rv32uc-p-rvc test without
#               writing generated files into the upstream source checkout.
# Notes       : The riscv-tests tree must include its env submodule. Outputs
#               are written below out/ and include provenance/tool hashes.
# ============================================================================
set -eu

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RVT="${RVT:-$ROOT/out/third-party-work/riscv-tests}"
OUT_DIR="${OUT_DIR:-$ROOT/out/sw/riscv-tests-build/rv32uc}"
MARCH="${MARCH:-rv32imc_zicsr}"
MABI="${MABI:-ilp32}"

if [ -n "${RISCV_PREFIX:-}" ]; then
    GCC="${RISCV_PREFIX}gcc"
else
    GCC="$(find "$HOME/.local" -maxdepth 5 -type f \
        -path '*/bin/riscv-none-elf-gcc' 2>/dev/null | sort -V | tail -n 1)"
    if [ -z "$GCC" ] && command -v riscv64-unknown-elf-gcc >/dev/null 2>&1; then
        GCC="$(command -v riscv64-unknown-elf-gcc)"
    fi
fi

if [ -z "${GCC:-}" ] || [ ! -x "$GCC" ]; then
    echo "ERROR: RISC-V bare-metal GCC not found; set RISCV_PREFIX" >&2
    exit 2
fi

PREFIX="${GCC%gcc}"
OBJCOPY="${PREFIX}objcopy"
OBJDUMP="${PREFIX}objdump"
SRC="$RVT/isa/rv32uc/rvc.S"
LINKER="$RVT/env/p/link.ld"

if [ ! -f "$SRC" ] || [ ! -f "$LINKER" ]; then
    echo "ERROR: official riscv-tests checkout or env submodule is incomplete: $RVT" >&2
    exit 2
fi

mkdir -p "$OUT_DIR"
ELF="$OUT_DIR/rv32uc-p-rvc.elf"
BIN="$OUT_DIR/rv32uc-p-rvc.bin"
HEX="$OUT_DIR/rv32uc-p-rvc.hex"
LOG="$OUT_DIR/rv32uc-p-rvc.cc.log"
INFO="$OUT_DIR/build-info.txt"

"$GCC" \
    -march="$MARCH" \
    -mabi="$MABI" \
    -static \
    -mcmodel=medany \
    -fvisibility=hidden \
    -nostdlib \
    -nostartfiles \
    -fno-pic \
    -Wl,--build-id=none \
    -I "$RVT/env/p" \
    -I "$RVT/isa/macros/scalar" \
    -T "$LINKER" \
    "$SRC" \
    -o "$ELF" > "$LOG" 2>&1

"$OBJCOPY" -O binary "$ELF" "$BIN"
python3 "$ROOT/sw/script/gen_memimage.py" "$BIN" "$HEX" >/dev/null

TOHOST="$($OBJDUMP -t "$ELF" | awk '/[[:space:]]tohost$/ {print "0x"$1; exit}')"
if [ -z "$TOHOST" ]; then
    echo "ERROR: generated ELF has no tohost symbol" >&2
    exit 1
fi

{
    echo "source_url=https://github.com/riscv-software-src/riscv-tests.git"
    echo "source_commit=$(git -C "$RVT" rev-parse HEAD)"
    echo "env_commit=$(git -C "$RVT" rev-parse HEAD:env)"
    echo "march=$MARCH"
    echo "mabi=$MABI"
    echo "gcc=$GCC"
    echo "gcc_version=$($GCC --version | head -n 1)"
    echo "tohost=$TOHOST"
    sha256sum "$ELF" "$BIN" "$HEX"
} > "$INFO"

echo "RV32UC_BUILD_PASS elf=$ELF tohost=$TOHOST"
echo "RV32UC_BUILD_INFO $INFO"
