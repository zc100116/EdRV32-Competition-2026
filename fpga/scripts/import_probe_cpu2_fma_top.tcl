# File: import_probe_cpu2_fma_top.tcl
# Run in the PDS project directory; the checkout is ../../EdRV32-Competition-2026.
# GTP_APM_E2 comes from the device library; no IP Compiler output is required.
set edrv32_repo [file normalize ../../EdRV32-Competition-2026]
set edrv32_top edrv32_fpga_probe_cpu2_fma_top
set edrv32_include_dirs [file join $edrv32_repo rtl include]
set edrv32_defines [list FPGA_MODE]
set edrv32_list [file join $edrv32_repo rtl filelists cpu2_probe_fma.f]
set edrv32_fh [open $edrv32_list r]
set edrv32_lines [split [read $edrv32_fh] "\n"]
close $edrv32_fh
foreach line $edrv32_lines {
    set line [string trim $line]
    if {$line eq "" || [string match "+incdir+*" $line]} {
        continue
    }
    add_design [file normalize [file join [file dirname $edrv32_list] $line]]
}
add_constraint [file join $edrv32_repo fpga constraints edrv32_fpga_probe_cpu2_fma_top.fdc]
compile \
    -top_module $edrv32_top \
    -include_path $edrv32_include_dirs \
    -compiler_directives $edrv32_defines
puts "edrv32: imported $edrv32_top (150 MHz, 2 APMs)"
