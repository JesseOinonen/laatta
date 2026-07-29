#!/usr/bin/env bash
#------------------------------------------------------------------------------
# Generic block-level simulation flow (Vivado xsim, no Vivado project).
#
# Reusable across every block: point it at a block name and it compiles that
# block's RTL, the shared UVM testbench, and the block's top, then runs the
# block's test. Direct xsim tools only — the Vivado project flow (make build)
# stays available separately for sharing / GUI project work.
#
#   scripts/sim.sh <block> [compile|elab|sim|gui|clean]
#
# Examples:
#   scripts/sim.sh geometry_fetch          # compile + elaborate + run (default)
#   scripts/sim.sh geometry_fetch gui      # open the waveform GUI
#   scripts/sim.sh geometry_fetch clean
#   TEST=my_other_test scripts/sim.sh geometry_fetch
#
# To add a new block <b>, provide three things (see ip/sim/README.md):
#   ip/sim/<b>.f            RTL file list (compile order, paths relative to ip/)
#   ip/tb/top/top_<b>.sv    block-level TB top named top_<b>
#   ip/tb/cases/<b>_test.sv UVM test named <b>_test (included from gpu_pkg.sv)
#------------------------------------------------------------------------------
set -euo pipefail

IP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VIVADO_BIN="${VIVADO_BIN:-/opt/2025.2/Vivado/bin}"

BLOCK="${1:-}"
ACTION="${2:-sim}"

list_blocks() {
    echo "available blocks:"
    ls "$IP_DIR"/sim/*.f 2>/dev/null | xargs -r -n1 basename | sed 's/\.f$//; s/^/  /'
}

if [ -z "$BLOCK" ]; then
    echo "usage: $0 <block> [compile|elab|sim|gui|clean]"
    list_blocks
    exit 1
fi

FLIST="$IP_DIR/sim/$BLOCK.f"
if [ ! -f "$FLIST" ]; then
    echo "no file list: $FLIST"
    list_blocks
    exit 1
fi

TOP="top_$BLOCK"
TEST="${TEST:-${BLOCK}_test}"
WORK="$IP_DIR/sim/build/$BLOCK"

XVHDL="$VIVADO_BIN/xvhdl"
XVLOG="$VIVADO_BIN/xvlog"
XELAB="$VIVADO_BIN/xelab"
XSIM="$VIVADO_BIN/xsim"

# Split the block's RTL list into VHDL and (System)Verilog, preserving order.
RTL_VHDL=(); RTL_SV=()
while IFS= read -r line; do
    case "$line" in
        ""|\#*) continue ;;
    esac
    f="$IP_DIR/$line"
    case "$f" in
        *.vhd|*.vhdl) RTL_VHDL+=("$f") ;;
        *.v|*.sv)     RTL_SV+=("$f") ;;
        *) echo "unknown RTL file type: $f"; exit 1 ;;
    esac
done < "$FLIST"

# Shared testbench: the UVM package (pulls in every agent/env/case via include),
# the interface, the clock/reset generators, and this block's top.
SV_TB=(
    "$IP_DIR/tb/uvm/gpu_pkg.sv"
    "$IP_DIR/tb/top/axi_if.sv"
    "$IP_DIR/tb/top/submodules.sv"
    "$IP_DIR/tb/top/$TOP.sv"
)
INC=(-i "$IP_DIR/tb/uvm" -i "$IP_DIR/tb/cases" -i "$IP_DIR/tb/top")

do_compile() {
    mkdir -p "$WORK"; cd "$WORK"
    if [ ${#RTL_VHDL[@]} -gt 0 ]; then
        echo ">>> Analysing VHDL RTL"
        "$XVHDL" --2008 "${RTL_VHDL[@]}"
    fi
    echo ">>> Analysing (System)Verilog (block RTL + UVM testbench)"
    "$XVLOG" -sv -L uvm "${INC[@]}" "${RTL_SV[@]}" "${SV_TB[@]}"
}

do_elab() {
    cd "$WORK"
    echo ">>> Elaborating $TOP"
    "$XELAB" -L uvm --timescale 1ns/1ps "$TOP" -s "$TOP" --debug typical
}

do_run() {
    cd "$WORK"
    echo ">>> Running test: $TEST"
    "$XSIM" "$TOP" -R -testplusarg "UVM_TESTNAME=$TEST"
}

do_wave() {
    cd "$WORK"
    printf 'log_wave -recursive /%s\nrun all\nexit\n' "$TOP" > .wave_run.tcl
    echo ">>> Logging all signals -> $WORK/$TOP.wdb (test: $TEST)"
    "$XSIM" "$TOP" -testplusarg "UVM_TESTNAME=$TEST" -tclbatch .wave_run.tcl
}

do_gui() {
    cd "$WORK"
    printf 'add_wave -recursive /%s\nrun all\n' "$TOP" > .wave_gui.tcl
    echo ">>> Opening the waveform GUI (all signals added, runs to \$finish)"
    "$XSIM" "$TOP" -gui -tclbatch .wave_gui.tcl -testplusarg "UVM_TESTNAME=$TEST"
}

case "$ACTION" in
    compile) do_compile ;;
    elab)    do_compile; do_elab ;;
    sim)     do_compile; do_elab; do_run ;;
    wave)    do_compile; do_elab; do_wave ;;
    gui)     do_compile; do_elab; do_gui ;;
    clean)   rm -rf "$WORK"; echo "removed $WORK" ;;
    *) echo "unknown action: $ACTION (compile|elab|sim|wave|gui|clean)"; exit 1 ;;
esac
