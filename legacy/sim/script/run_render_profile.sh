#!/bin/sh
set -eu

case_name=${1:?usage: run_render_profile.sh render-gallery [PARAMETER=VALUE]}
parameter=${2:-}
case_file="sim/cases/vision/$case_name/files.f"
case_dir="sim/build/cases/vision/$case_name"
if [ -n "$parameter" ]; then
    variant=$(printf '%s' "$parameter" | tr '=/' '--')
    profile_dir="sim/build/profile/$case_name-$variant"
else
    profile_dir="sim/build/profile/$case_name"
fi

test -f "$case_file"
top=$(sed -n 's/^[[:space:]]*-s[[:space:]]*//p' "$case_file" | head -n 1)
test -n "$top"
if [ -n "$parameter" ]; then
    set -- "-P$top.$parameter"
else
    set --
fi
mkdir -p "$case_dir" "$profile_dir"
sed '/^[[:space:]]*-s[[:space:]]/d' "$case_file" > "$profile_dir/files.f"

# Project source paths contain no whitespace. Keep the case's normal file list
# so the profiler observes exactly the RTL used by its functional test.
# shellcheck disable=SC2046
iverilog -g2012 "-DPROFILE_TB=$top" -s "$top" -s tb_render_profile "$@" \
    -o "$profile_dir/sim.vvp" \
    $(cat "$profile_dir/files.f") sim/script/render_profile.sv
vvp "$profile_dir/sim.vvp" | tee "$profile_dir/run.log"
