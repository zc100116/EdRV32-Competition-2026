# File: check_import.tcl
# Spec: Task B3-9 acceptance; CLAUDE.md 12.3.
# Description: Execute the import script and constraints with read-only Tcl mocks.
# Clock domain: none (host tool).
set sources {}
proc add_design {path} {
    if {![file isfile $path]} {error "missing source: $path"}
    lappend ::sources $path
}
proc add_constraint {path} {
    if {![file isfile $path]} {error "missing constraint: $path"}
    set ::constraint $path
}
proc compile {args} {puts "compile $args"}
source [file join [file dirname [info script]] ../../../fpga/scripts/import_board_imgtest_top.tcl]
puts "PASS: all [llength $sources] imported RTL files and constraint exist"
proc get_ports {args} {return $args}
proc get_pins {args} {return $args}
proc get_clocks {args} {return $args}
set clocks 0
proc create_clock {args} {incr ::clocks}
proc create_generated_clock {args} {incr ::clocks}
proc set_multicycle_path {args} {}
proc set_clock_uncertainty {args} {}
proc define_attribute {args} {}
proc set_clock_groups {args} {}
proc set_false_path {args} {}
source $constraint
puts "PASS: constraint Tcl syntax, $clocks clock definitions"
