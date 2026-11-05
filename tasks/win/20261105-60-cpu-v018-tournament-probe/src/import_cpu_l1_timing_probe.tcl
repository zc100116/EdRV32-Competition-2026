# File: import_cpu_l1_timing_probe.tcl
# Card 60: import edrv32_cpu_l1_timing_probe into an open PG2L200H-6/FBB676 PDS project.
# Required generated IP: ip_ram_icache_tag, ip_ram_icache_data, ip_ram_dcache_tag,
# ip_ram_dcache_data, ip_mul_s33x33, ip_lutram_cpu_btb, ip_lutram_cpu_direction,
# ip_lutram_cpu_local_history and ip_lutram_cpu_tournament (fpga/ip/ of the card checkout).
# Run in the PDS Tcl console from the probe project directory. Set edrv32_repo to the
# card checkout and edrv32_card to this card's directory before sourcing.
puts "edrv32: repo $edrv32_repo"
puts "edrv32: card $edrv32_card"
set edrv32_top edrv32_cpu_l1_timing_probe
set edrv32_defines [list FPGA_MODE]

# Same expansion as fpga/scripts/import_board_full_top.tcl: first occurrence kept, order kept.
proc edrv32_full_filelist {path} {
    set dir [file dirname $path]
    set fh [open $path r]
    set contents [read $fh]
    close $fh
    set tokens {}
    foreach line [split $contents "\n"] {
        set line [lindex [split $line "#"] 0]
        foreach token [regexp -all -inline {\S+} $line] {
            lappend tokens $token
        }
    }
    set files {}
    for {set idx 0} {$idx < [llength $tokens]} {incr idx} {
        set token [lindex $tokens $idx]
        if {$token eq "-f"} {
            incr idx
            set sub [file join $dir [lindex $tokens $idx]]
            set files [concat $files [edrv32_full_filelist $sub]]
        } elseif {[string match "+incdir+*" $token]} {
            continue
        } else {
            lappend files [file normalize [file join $dir $token]]
        }
    }
    return $files
}

set edrv32_sources [edrv32_full_filelist [file join $edrv32_repo rtl filelists cpu_subsys.f]]
lappend edrv32_sources [file normalize [file join $edrv32_repo rtl common edrv32_reset_sync.v]]
lappend edrv32_sources [file join $edrv32_card src edrv32_cpu_l1_timing_probe.v]
foreach f $edrv32_sources {
    add_design $f
}
add_constraint [file join $edrv32_card src edrv32_cpu_l1_timing_probe.fdc]
compile \
    -top_module $edrv32_top \
    -include_path "[file join $edrv32_repo rtl include]\t" \
    -compiler_directives $edrv32_defines \
    -force_to_run
puts "edrv32: added [llength $edrv32_sources] sources; top $edrv32_top; FPGA_MODE"
