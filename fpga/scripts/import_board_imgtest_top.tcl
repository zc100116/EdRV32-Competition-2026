# File: import_board_imgtest_top.tcl
# Spec: Task B3-9; CLAUDE.md 8, 10.
# In the open PG2L200H-6/FBB676 PDS project, generate the IPs from fpga/ip first.
# Required existing B2 IP: ip_pll_video, ip_ddr3, ip_ram_mem_xbar_r,
# ip_ram_mem_xbar_w, ip_ram_vin_wfifo, ip_ram_pix_line, ip_ram_geo_src,
# ip_ram_disp_scan (two instances, L1 disabled by the controller).
# TMDS and DDR reference use device primitives listed in fpga/ip/README.md.
# No CPU/sys/NPU/RND/ETH IP and no sensor ROM IP are needed.
# Then source this script; checkout location comes from the script itself.
set edrv32_repo [file normalize [file join [file dirname [info script]] ../..]]
set edrv32_top edrv32_fpga_board_imgtest_top
set edrv32_include_dirs [list [file join $edrv32_repo rtl include] [file normalize .]]
set edrv32_defines [list FPGA_MODE]

# Filelists use -f, +incdir+ and source tokens, with # comments. Resolve each
# relative path at its containing list. Preserve first source occurrence exactly
# as tools/regress.py expand_files does (do not sort the sources).
proc edrv32_imgtest_filelist {path} {
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
            set files [concat $files [edrv32_imgtest_filelist $sub]]
        } elseif {[string match "+incdir+*" $token]} {
            # Each subsystem filelist includes rtl/include, already passed to compile below.
            continue
        } else {
            lappend files [file normalize [file join $dir $token]]
        }
    }
    return $files
}

set edrv32_sources {}
foreach list {mem_subsys vin pix geo disp} {
    foreach f [edrv32_imgtest_filelist [file join $edrv32_repo rtl filelists $list.f]] {
        if {[lsearch -exact $edrv32_sources $f] < 0} {
            lappend edrv32_sources $f
        }
    }
}
foreach name {edrv32_reset_sync.v} {
    set f [file join $edrv32_repo rtl common $name]
    if {[lsearch -exact $edrv32_sources $f] < 0} {
        lappend edrv32_sources $f
    }
}
lappend edrv32_sources [file join $edrv32_repo rtl soc edrv32_soc_reset_ctrl.v]
foreach name {
    edrv32_fpga_ddr_adapter.v
    edrv32_fpga_tmds.v
    edrv32_fpga_imgtest_ctrl.v
    edrv32_fpga_imgtest_cam_init.v
    edrv32_fpga_imgtest_cam_rom.v
    edrv32_fpga_imgtest_sccb.v
    edrv32_fpga_imgtest_keys.v
    edrv32_fpga_board_imgtest_top.v
} {
    lappend edrv32_sources [file join $edrv32_repo fpga rtl $name]
}
foreach f $edrv32_sources {
    add_design $f
}
add_constraint [file join $edrv32_repo fpga constraints edrv32_fpga_board_imgtest_top.fdc]
compile \
    -top_module $edrv32_top \
    -include_path $edrv32_include_dirs \
    -compiler_directives $edrv32_defines \
    -force_to_run
puts "edrv32: added [llength $edrv32_sources] sources; top $edrv32_top; FPGA_MODE"
