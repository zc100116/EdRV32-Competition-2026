# File: check_import.tcl
# Spec: Task T-PMRM acceptance; fpga/scripts/README.md; CLAUDE.md 12.3.
# Description: Run the import from a simulated EdRV32-FPGA/P project directory.
# Clock domain: none (host tool; no PDS implementation).
set repo [file normalize [file join [file dirname [info script]] ../../..]]
set tmp [file join $repo build board_render import_check tmp]
file delete -force $tmp
file mkdir [file join $tmp EdRV32-FPGA P]
file link -symbolic [file join $tmp EdRV32-Competition-2026] $repo
cd [file join $tmp EdRV32-FPGA P]
set sources {}
proc add_design {path} {
    if {![file isfile $path]} {error "missing source: $path"}
    lappend ::sources $path
}
proc add_constraint {path} {
    if {![file isfile $path]} {error "missing constraint: $path"}
    set ::constraint $path
}
proc compile {args} {
    puts "compile $args"
}
source ../../EdRV32-Competition-2026/fpga/scripts/import_board_render_top.tcl
if {[llength $sources] != 102} {
    error "source count: expected 102, actual [llength $sources]"
}
puts "PASS: all [llength $sources] imported RTL files and constraint exist"
# Tcl syntax check only; these mocks do not validate the PDS netlist or timing.
proc get_ports {args} {return $args}
proc get_pins {args} {return $args}
proc get_clocks {args} {return $args}
set clocks 0
proc create_clock {args} {incr ::clocks}
proc create_generated_clock {args} {incr ::clocks}
proc set_multicycle_path {args} {}
proc set_clock_uncertainty {args} {}
proc define_attribute {args} {}
proc define_global_attribute {args} {}
proc set_clock_groups {args} {}
proc set_false_path {args} {}
source $constraint
puts "PASS: constraint Tcl syntax, $clocks clock definitions"
