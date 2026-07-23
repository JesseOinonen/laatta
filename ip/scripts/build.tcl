# Create project if missing, otherwise just refresh the file list.
# Run from the build directory (ip/build/laatta).
if {[file exists ./laatta.xpr]} {
    open_project ./laatta.xpr
    source ../../scripts/add_files.tcl
} else {
    source ../../scripts/create_project.tcl
}
quit
