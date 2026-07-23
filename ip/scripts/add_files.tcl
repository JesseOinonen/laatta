# Adds/upserts design and testbench sources into the open Vivado project.
# Idempotent — Vivado ignores already-added files. Run from ip/build/laatta.

# RTL sources (ip/rtl and any subdirectories). Guarded so an empty rtl/ is OK.
set rtl_files [glob -nocomplain ../../rtl/*.sv ../../rtl/**/*.sv]
if {[llength $rtl_files] > 0} {
    add_files $rtl_files
}

# Testbench: top/*.sv are independent modules (interface, clk/rst gen, TB top).
add_files -fileset sim_1 [glob ../../tb/top/*.sv]
# gpu_pkg.sv is the ONLY UVM compilation unit — it `include`s everything under
# uvm/ and cases/, so those files must NOT be added separately.
add_files -fileset sim_1 ../../tb/uvm/gpu_pkg.sv

# Include dirs for `include resolution inside gpu_pkg.sv (absolute paths).
set tb_dir [file normalize [file join [get_property DIRECTORY [current_project]] ../../tb]]
set_property include_dirs [list \
    [file join $tb_dir uvm] \
    [file join $tb_dir cases] \
    [file join $tb_dir top] \
] [get_filesets sim_1]

# Top modules.
if {[llength $rtl_files] > 0} {
    set_property top laatta_gpu_top [current_fileset]  ;# synthesis top
}
set_property top top [get_fileset sim_1]               ;# simulation top

puts "Laatta project file list updated (add_files.tcl)"
