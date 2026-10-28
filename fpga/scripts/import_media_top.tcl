# File: import_media_top.tcl
# Task: V-W1, complete VIN/DISP/PIX/GEO/ETH resource and timing measurement.
# In PDS GUI create EdRV32-FPGA/EdRV32-MEDIA beside EdRV32-FPGA/EdRV32-NPU,
# generate the six RAM IP types listed in fpga/ip/README.md, and open the project.
# Run from EdRV32-FPGA/EdRV32-MEDIA in the PDS Tcl console:
# source ../../EdRV32-Competition-2026/fpga/scripts/import_media_top.tcl
# This imports sources/constraints and compiles with FPGA_MODE; run synthesis and
# implementation afterwards in PDS to measure hierarchical resources and timing.

set edrv32_repo [file normalize ../../EdRV32-Competition-2026]
puts "edrv32: repo $edrv32_repo"
set edrv32_top edrv32_fpga_media_top
# Match the include list used by the successful CPU project. Keep both the
# source header directory and the current FPGA project directory explicit.
set edrv32_include_dirs [list \
    [file join $edrv32_repo rtl include] \
    [file normalize .]]
set edrv32_defines [list FPGA_MODE]

# Source paths are relative to their filelist; include paths are set above.
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

# Keep the first occurrence of each shared source across the five filelists.
set edrv32_sources {}
foreach name {vin disp pix geo eth} {
    foreach f [edrv32_filelist [file join $edrv32_repo rtl filelists ${name}.f]] {
        if {[lsearch -exact $edrv32_sources $f] < 0} {
            lappend edrv32_sources $f
        }
    }
}
lappend edrv32_sources [file join $edrv32_repo rtl common edrv32_reset_sync.v]
lappend edrv32_sources [file join $edrv32_repo fpga rtl edrv32_fpga_media_top.v]

foreach f $edrv32_sources {
    add_design $f
}
add_constraint [file join $edrv32_repo fpga constraints edrv32_fpga_media_top.fdc]

# Recompile with these include settings even if PDS considers Compile up to date.
compile \
    -top_module $edrv32_top \
    -include_path $edrv32_include_dirs \
    -compiler_directives $edrv32_defines \
    -force_to_run

puts "edrv32: added [llength $edrv32_sources] sources from $edrv32_repo"
puts "edrv32: top $edrv32_top, include path $edrv32_include_dirs, defines $edrv32_defines"
