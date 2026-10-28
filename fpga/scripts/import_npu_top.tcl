# File: import_npu_top.tcl
# Task: 20261028-02-npu-synth (npu-plan N-W2).
# Adds the complete NPU sources (rtl/filelists/npu.f), the measurement top and its
# constraints to an open PDS
# project whose 9 NPU IPs are already generated in the project, then compiles with the
# include directory rtl/include and the macro FPGA_MODE. Synthesis and
# implementation are run afterwards in PDS (see the task card).
# Run from EdRV32-FPGA/EdRV32-NPU in the PDS Tcl console:
# source ../../EdRV32-Competition-2026/fpga/scripts/import_npu_top.tcl

# The FPGA project and source checkout are siblings under codex_project.
set edrv32_repo [file normalize ../../EdRV32-Competition-2026]
puts "edrv32: repo $edrv32_repo"
set edrv32_top edrv32_fpga_npu_top
# Match the previous Windows build: pass the source header directory and the
# FPGA project directory explicitly to PDS through compile -include_path.
set edrv32_include_dirs [list \
    [file join $edrv32_repo rtl include] \
    [file normalize .]]
set edrv32_defines [list FPGA_MODE]

# Expand a filelist: "-f x.f" recurses, "+incdir+" lines are covered by
# edrv32_include_dirs, other lines are source paths relative to the list's directory.
proc edrv32_filelist {path} {
    set dir [file dirname $path]
    set fh [open $path r]
    set lines [split [read $fh] "\n"]
    close $fh
    set files {}
    foreach line $lines {
        set line [string trim $line]
        if {$line eq "" || [string match "+incdir+*" $line]} {
            continue
        }
        if {[string match "-f *" $line]} {
            set sub [string trim [string range $line 3 end]]
            set files [concat $files [edrv32_filelist [file join $dir $sub]]]
        } else {
            lappend files [file normalize [file join $dir $line]]
        }
    }
    return $files
}

set edrv32_sources [edrv32_filelist [file join $edrv32_repo rtl filelists npu.f]]
lappend edrv32_sources [file join $edrv32_repo rtl common edrv32_reset_sync.v]
lappend edrv32_sources [file join $edrv32_repo fpga rtl edrv32_fpga_npu_top.v]

foreach f $edrv32_sources {
    add_design $f
}
add_constraint [file join $edrv32_repo fpga constraints edrv32_fpga_npu_top.fdc]

compile \
    -top_module $edrv32_top \
    -include_path $edrv32_include_dirs \
    -compiler_directives $edrv32_defines

puts "edrv32: added [llength $edrv32_sources] sources from $edrv32_repo"
puts "edrv32: top $edrv32_top, include path $edrv32_include_dirs, defines $edrv32_defines"
