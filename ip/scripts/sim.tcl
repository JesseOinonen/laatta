# Configure a GUI simulation for a given test. Run from ip/build/laatta.
open_project ./laatta.xpr
set_property top top [get_filesets sim_1]

# First argument = test name, default csr_test.
if {[llength $argv] > 0} {
    set test_name [lindex $argv 0]
} else {
    set test_name "csr_test"
}

set_property -name {xsim.compile.xvlog.more_options}   -value {-L uvm}                               -objects [get_filesets sim_1]
set_property -name {xsim.elaborate.xelab.more_options} -value {-L uvm}                               -objects [get_filesets sim_1]
set_property -name {xsim.simulate.xsim.more_options}   -value "-testplusarg UVM_TESTNAME=$test_name" -objects [get_filesets sim_1]

puts "======================================"
puts "Test configured: $test_name"
puts "Run 'launch_simulation' in the Tcl console to start."
puts "======================================"
