#!/usr/bin/env python3
"""Plots the tile-size sweep produced by output/sweep.

The C++ model owns correctness; this only draws what it measured. Keeping the
analysis in a different language is deliberate: an independent implementation
that agrees is far stronger evidence than one that agrees with itself.
"""

import csv
import sys
from pathlib import Path

try:
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
except ImportError:
    sys.exit("matplotlib not installed:  pip install matplotlib")

OUT = Path("output")


def read_sweep(path):
    with open(path) as f:
        return [{k: float(v) for k, v in row.items()} for row in csv.DictReader(f)]


def main():
    csv_path = OUT / "sweep.csv"
    if not csv_path.exists():
        sys.exit(f"{csv_path} missing — run 'make sweep' first")

    rows = read_sweep(csv_path)
    tile = [r["tile_size"] for r in rows]
    kib = 1024.0

    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(12, 4.5))

    # Left: the actual trade-off. On-chip cost against off-chip traffic.
    ax1.plot(tile, [r["total_dram"] / kib for r in rows], "o-", label="total DRAM")
    ax1.plot(tile, [r["param_read"] / kib for r in rows], "s--", label="parameter read")
    ax1.plot(tile, [r["param_write"] / kib for r in rows], "^--", label="parameter write")
    ax1.set_xscale("log", base=2)
    ax1.set_xticks(tile)
    ax1.set_xticklabels([int(t) for t in tile])
    ax1.set_xlabel("tile size (pixels per side)")
    ax1.set_ylabel("DRAM traffic (KiB)")
    ax1.set_title("Off-chip traffic vs. tile size")
    ax1.grid(alpha=0.3)
    ax1.legend()

    ax2b = ax2.twinx()
    ax2.plot(tile, [r["bram_bytes"] / kib for r in rows], "o-", color="tab:red",
             label="tile buffer BRAM")
    ax2b.plot(tile, [r["tiles_per_triangle"] for r in rows], "s--", color="tab:blue",
              label="tiles per triangle")
    ax2.set_xscale("log", base=2)
    ax2.set_xticks(tile)
    ax2.set_xticklabels([int(t) for t in tile])
    ax2.set_xlabel("tile size (pixels per side)")
    ax2.set_ylabel("on-chip tile buffer (KiB)", color="tab:red")
    ax2b.set_ylabel("tiles touched per triangle", color="tab:blue")
    ax2.set_title("On-chip cost vs. binning overhead")
    ax2.grid(alpha=0.3)

    fig.tight_layout()
    out = OUT / "sweep.png"
    fig.savefig(out, dpi=130)
    print(f"wrote {out}")


if __name__ == "__main__":
    main()
