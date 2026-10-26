# File: import_cpu_sys_top.tcl
# Task: 20261025-01-cpu-sys-synth (cpu-plan C-W2, sys-subsys-plan S-P1).
# Adds the CPU + system subsystem sources and the board constraints to an open PDS
# project whose 7 IPs are already generated in the project, then compiles with the
# include directory rtl/include and the macro FPGA_MODE. Synthesis and
# implementation are run afterwards in PDS (see the task card).
# Usage, in the PDS Tcl console: source <repo>/fpga/scripts/import_cpu_sys_top.tcl

set edrv32_repo [file normalize [file join [file dirname [info script]] .. ..]]
set edrv32_top edrv32_fpga_cpu_sys_top
set edrv32_include_dirs [list [file join $edrv32_repo rtl include]]
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

set edrv32_sources [concat \
    [edrv32_filelist [file join $edrv32_repo rtl filelists cpu_subsys.f]] \
    [edrv32_filelist [file join $edrv32_repo rtl filelists sys_subsys.f]]]
lappend edrv32_sources [file join $edrv32_repo fpga rtl edrv32_fpga_cpu_sys_top.v]

foreach f $edrv32_sources {
    add_design $f
}
add_constraint [file join $edrv32_repo fpga constraints edrv32_fpga_cpu_sys_top.fdc]

compile \
    -top_module $edrv32_top \
    -include_path $edrv32_include_dirs \
    -compiler_directives $edrv32_defines

puts "edrv32: added [llength $edrv32_sources] sources from $edrv32_repo"
puts "edrv32: top $edrv32_top, include path $edrv32_include_dirs, defines $edrv32_defines"
