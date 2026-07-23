# Compile + elaborate the simulation (no run). Run from ip/build/laatta.
open_project ./laatta.xpr
set_property top top [get_filesets sim_1]

set tb_dir [file normalize [file join [get_property DIRECTORY [current_project]] ../../tb]]
set_property include_dirs [list \
    [file join $tb_dir uvm] \
    [file join $tb_dir cases] \
    [file join $tb_dir top] \
] [get_filesets sim_1]

# UVM library required by xvlog/xelab.
set_property -name {xsim.compile.xvlog.more_options}   -value {-L uvm} -objects [get_filesets sim_1]
set_property -name {xsim.elaborate.xelab.more_options} -value {-L uvm} -objects [get_filesets sim_1]

launch_simulation -step compile
launch_simulation -step elaborate
puts "Compilation and elaboration complete."
quit
