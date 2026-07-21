# Phase 0 — golden model

Functional reference implementation of the Laatta pipeline. Plain C++17, no
external dependencies, no simulator. Two jobs:

1. **Answer the architecture questions** — tile size against on-chip BRAM
   against DRAM traffic — before any RTL is written.
2. **Be the golden reference** the RTL is verified against, pixel by pixel.

It is deliberately *not* timed. Cycle counts come from RTL simulation; this
model answers "how many bytes cross the chip boundary", which is what the
architecture decisions actually hinge on.

## Build and run

    make render     # render the scene, compare TBDR against immediate mode
    make sweep      # tile-size sweep -> output/sweep.csv
    make plots      # sweep + charts (needs matplotlib)

    make render SCENE=path/to/other.obj

Outputs land in `output/`:

| File | Contents |
|---|---|
| `render_tbdr.png` | tile-based render — the golden image |
| `render_imr.png` | immediate-mode render, must be pixel-identical |
| `render_diff.png` | differing pixels in red, matching ones dimmed |
| `vertex_buffer.bin`, `index_buffer.bin` | scene in the exact DRAM layout, for the RTL testbench |
| `sweep.csv`, `sweep.png` | design-space data |

## Structure

    src/memory/     memory_map.h   address map and buffer formats, shared with RTL
                    dram_model     memory contents + burst-granular traffic accounting
    src/tools/      obj_loader     .obj -> de-indexed triangle list -> DRAM
    src/render/     math3d.h       vectors, matrices, projection
                    transform      shading, near clipping, culling, viewport
                    binner         triangles -> tile lists
                    raster*        the rasteriser inner loop (shared by both paths)
                    renderer       TBDR and immediate-mode paths + traffic accounting
    tools/          plot_sweep.py  charts from sweep.csv

## How it checks itself

The tiled and immediate-mode paths call the **same** `raster_triangle`
template, so any difference in the output image means the tiling logic is
broken rather than the rasteriser. `make render` fails if a single pixel
differs. The .obj round trip through DRAM is verified byte-for-byte on every
run as well.

## What is deliberately simplified

- Colour interpolation is screen-space linear, not perspective correct. This
  matches simple fixed-function hardware and keeps the path in integers.
- Only the near plane is clipped; the other five are handled by clamping the
  screen bounding box, as a guard-band rasteriser does.
- Binning is by bounding box, not exact edge tests.
- Vertex fetch is accounted as if a post-transform cache catches all reuse.
  The uncached figure is reported next to it so the difference is visible.

## Precision

Screen coordinates are snapped to 1/16 pixel (`SUBPIXEL_BITS`) and edge
functions are exact `int64` arithmetic, so coverage is deterministic and
reproducible in RTL. Depth is 16-bit unsigned, 0 = near.

`attic/systemc/` holds the earlier SystemC pipeline sketch, kept for reference
and not built.
