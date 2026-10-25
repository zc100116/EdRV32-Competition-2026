#!/bin/sh
# Lint the given Verilog source arguments (including -f file lists).
set -eu
exec verilator --lint-only -Wall "$@"
