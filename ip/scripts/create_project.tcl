# Create the Vivado project for the Laatta GPU IP.
# Run from the build directory (ip/build/laatta).
create_project laatta . -part xc7z020clg400-1 -force
source ../../scripts/add_files.tcl
