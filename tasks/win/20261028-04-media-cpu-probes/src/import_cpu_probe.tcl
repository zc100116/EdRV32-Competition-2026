# File: import_cpu_probe.tcl
# Task: 20261028-04-media-cpu-probes part B (cpu-plan C-W6).
# Same as fpga/scripts/import_cpu_sys_top.tcl, except that every source file which has a
# copy under src/<version>/ (same path relative to the repository root) is replaced by
# that copy, and versions p2/p3 also add src/<version>/fpga/constraints/
# edrv32_fpga_cpu_sys_top_probe.fdc. The copies are the probe commits 15d21f8 (p1),
# 2ec4170 (p2) and 3615a7e (p3) from origin/probe/cpu-timing; measurement only.
# Run from EdRV32-FPGA/EdRV32 in the PDS Tcl console, choosing the version first:
#   set edrv32_probe p1
#   source ../../EdRV32-Competition-2026/tasks/win/20261028-04-media-cpu-probes/src/import_cpu_probe.tcl

set edrv32_repo [file normalize ../../EdRV32-Competition-2026]
set edrv32_probe_dir [file join $edrv32_repo tasks win 20261028-04-media-cpu-probes src $edrv32_probe]
if {![file isdirectory $edrv32_probe_dir]} {
    error "edrv32: probe version '$edrv32_probe' not found at $edrv32_probe_dir"
}
puts "edrv32: repo $edrv32_repo, probe $edrv32_probe"
set edrv32_top edrv32_fpga_cpu_sys_top
set edrv32_include_dirs [list \
    [file join $edrv32_repo rtl include] \
    [file normalize .]]
set edrv32_defines [list FPGA_MODE]

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

set edrv32_sources [concat \
    [edrv32_filelist [file join $edrv32_repo rtl filelists cpu_subsys.f]] \
    [edrv32_filelist [file join $edrv32_repo rtl filelists sys_subsys.f]]]
lappend edrv32_sources [file join $edrv32_repo fpga rtl edrv32_fpga_cpu_sys_top.v]

set edrv32_replaced 0
set edrv32_final {}
set edrv32_repo_len [string length $edrv32_repo]
foreach f $edrv32_sources {
    set rel [string range $f [expr {$edrv32_repo_len + 1}] end]
    set copy [file join $edrv32_probe_dir $rel]
    if {[file exists $copy]} {
        lappend edrv32_final $copy
        incr edrv32_replaced
        puts "edrv32: probe $edrv32_probe replaces $rel"
    } else {
        lappend edrv32_final $f
    }
}

foreach f $edrv32_final {
    add_design $f
}
add_constraint [file join $edrv32_repo fpga constraints edrv32_fpga_cpu_sys_top.fdc]
set edrv32_probe_fdc [file join $edrv32_probe_dir fpga constraints edrv32_fpga_cpu_sys_top_probe.fdc]
if {[file exists $edrv32_probe_fdc]} {
    add_constraint $edrv32_probe_fdc
    puts "edrv32: probe constraints $edrv32_probe_fdc"
}

compile \
    -top_module $edrv32_top \
    -include_path $edrv32_include_dirs \
    -compiler_directives $edrv32_defines

puts "edrv32: added [llength $edrv32_final] sources ($edrv32_replaced from probe $edrv32_probe)"
