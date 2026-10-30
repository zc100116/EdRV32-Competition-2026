# File: import_board_vision_top.tcl
# Spec: Task B3-7; CLAUDE.md 8, 10.
# In the open PG2L200H-6/FBB676 PDS project, generate the IPs from fpga/ip first.
# Required generated IP (fpga/ip/README.md): ip_pll_sys, ip_pll_video, ip_pll_eth, ip_ddr3;
# ip_ram_icache_tag, ip_ram_icache_data, ip_ram_dcache_tag, ip_ram_dcache_data,
# ip_mul_s33x33, ip_rom_boot, ip_ram_sram, ip_ram_mem_xbar_r, ip_ram_mem_xbar_w,
# ip_ram_vin_wfifo, ip_ram_pix_line, ip_ram_geo_src, ip_ram_eth_buf, ip_ram_eth_fifo,
# ip_ram_disp_scan (two instances, DISP v0.3 L0/L1).
# TMDS/RGMII and DDR reference use device primitives listed in fpga/ip/README.md.
# No NPU/RND IP; ip_pll_eth is instantiated inside edrv32_fpga_rgmii.
# Run in the PDS Tcl console from the FPGA project directory EdRV32-FPGA/<project>.
# The source checkout is its sibling under codex_project (Windows builds B3I, B3V).
set edrv32_repo [file normalize ../../EdRV32-Competition-2026]
puts "edrv32: repo $edrv32_repo"
set edrv32_top edrv32_fpga_board_vision_top
# PDS adds the project directory; pass only the repository header directory.
set edrv32_include_dirs [file join $edrv32_repo rtl include]
puts "edrv32: include $edrv32_include_dirs"
set edrv32_defines [list FPGA_MODE]

# Filelists use -f, +incdir+ and source tokens, with # comments. Resolve each
# relative path at its containing list. Preserve first source occurrence exactly
# as tools/regress.py expand_files does (do not sort the sources).
proc edrv32_vision_filelist {path} {
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
            set files [concat $files [edrv32_vision_filelist $sub]]
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
foreach list {cpu_subsys sys_subsys mem_subsys vin pix geo disp eth} {
    foreach f [edrv32_vision_filelist [file join $edrv32_repo rtl filelists $list.f]] {
        if {[lsearch -exact $edrv32_sources $f] < 0} {
            lappend edrv32_sources $f
        }
    }
}
foreach name {
    edrv32_fpga_ddr_adapter.v
    edrv32_fpga_rgmii.v
    edrv32_fpga_tmds.v
    edrv32_fpga_board_vision_top.v
} {
    lappend edrv32_sources [file join $edrv32_repo fpga rtl $name]
}
foreach f $edrv32_sources {
    add_design $f
}
add_constraint [file join $edrv32_repo fpga constraints edrv32_fpga_board_vision_top.fdc]
compile \
    -top_module $edrv32_top \
    -include_path $edrv32_include_dirs \
    -compiler_directives $edrv32_defines \
    -force_to_run
puts "edrv32: added [llength $edrv32_sources] sources; top $edrv32_top; FPGA_MODE"
