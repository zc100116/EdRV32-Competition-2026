#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"
OUT_DIR="${PROJECT_ROOT}/out/sw/baseline/smoke"

if [[ -n "${RISCV_TOOL_PREFIX:-}" ]]; then
    TOOL_PREFIX="${RISCV_TOOL_PREFIX}"
elif command -v riscv64-unknown-elf-gcc >/dev/null 2>&1; then
    TOOL_PREFIX="riscv64-unknown-elf-"
elif command -v riscv32-unknown-elf-gcc >/dev/null 2>&1; then
    TOOL_PREFIX="riscv32-unknown-elf-"
else
    echo "ERROR: no RISC-V bare-metal GCC toolchain found" >&2
    exit 2
fi

mkdir -p "${OUT_DIR}"
"${TOOL_PREFIX}gcc" \
    -march=rv32im -mabi=ilp32 -nostdlib -nostartfiles \
    -Wl,--build-id=none \
    -T "${PROJECT_ROOT}/sw/test/baseline/core-smoke/link/smoke.ld" \
    -o "${OUT_DIR}/smoke.elf" \
    "${PROJECT_ROOT}/sw/test/baseline/core-smoke/src/smoke.S"
"${TOOL_PREFIX}objcopy" -O binary "${OUT_DIR}/smoke.elf" "${OUT_DIR}/smoke.bin"
python3 "${PROJECT_ROOT}/sw/script/gen_memimage.py" \
    "${OUT_DIR}/smoke.bin" "${OUT_DIR}/smoke.hex"
"${TOOL_PREFIX}objdump" -d "${OUT_DIR}/smoke.elf" > "${OUT_DIR}/smoke.dis"

echo "Built ${OUT_DIR}/smoke.hex"
