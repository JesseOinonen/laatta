#!/usr/bin/env bash

set -e

###############################################################################
# FloPoCo wrapper
###############################################################################
flopoco() {
    docker run --rm \
        -v "$(pwd)":/flopoco_workspace \
        flopoco:debian-5.0.0 "$@"
}

###############################################################################
# Configuration
###############################################################################
F=200
T=Kintex7

###############################################################################
# Output directory
###############################################################################
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="$ROOT_DIR/rtl/common/fp/gen"

mkdir -p "$OUT_DIR"
cd "$OUT_DIR"

echo "Generating floating point IPs..."
echo "Output directory: $OUT_DIR"

###############################################################################
# Floating point operators
###############################################################################

flopoco outputFile=fp_mul_core.vhdl \
    frequency=$F target=$T \
    name=fp_mul_core \
    FPMult wE=8 wF=23

flopoco outputFile=fp_add_core.vhdl \
    frequency=$F target=$T \
    name=fp_add_core \
    FPAdd wE=8 wF=23

flopoco outputFile=fp_div_core.vhdl \
    frequency=$F target=$T \
    name=fp_div_core \
    FPDiv wE=8 wF=23

flopoco outputFile=fp_sqrt_core.vhdl \
    frequency=$F target=$T \
    name=fp_sqrt_core \
    FPSqrt wE=8 wF=23

flopoco outputFile=in_ieee.vhdl \
    name=in_ieee \
    InputIEEE wEIn=8 wFIn=23 wEOut=8 wFOut=23

flopoco outputFile=out_ieee.vhdl \
    name=out_ieee \
    OutputIEEE wEIn=8 wFIn=23 wEOut=8 wFOut=23

echo
echo "Done."
echo "Generated files:"
ls -1 *.vhdl