# Laatta — a small tile-based GPU

A mobile-style tile-based deferred rendering (TBDR) GPU, built from scratch,
following the architectural philosophy of ARM Mali / Imagination PowerVR: bin
triangles into small tiles, keep tile color/depth on-chip in SRAM for the full
processing time, and minimize off-chip DRAM traffic.

Prototyped on a Digilent Arty Z7 (Zynq-7000), but written **ASIC-first**: the
RTL is kept identical to what would be taped out (single clock domain,
active-low async-assert / sync-deassert reset), with an OpenROAD / OpenLane flow
as the eventual target.

This is a learning project focused on **architecture-level decision-making**
(tile size, on-chip SRAM budget, binning strategy, float-vs-fixed precision,
floating-point unit strategy) rather than only RTL implementation. Every
non-obvious choice is recorded as a measured decision (D-01 … D-11) in
[`docs/documentation.tex`](docs/documentation.tex).

## Why this project

- Data movement dominates arithmetic cost in modern SoC/accelerator design — a
  TBDR GPU makes that trade-off concrete and measurable.

## Repository layout

| Path | Contents |
|---|---|
| `model/` | C++ golden model — pixel-accurate reference and design-space measurements |
| `ip/rtl/` | VHDL RTL — pipeline blocks, shared package, common cells, FloPoCo FP wrappers |
| `ip/tb/` | UVM testbench — shared environment, agents, per-block tests |
| `ip/scripts/`, `ip/sim/` | Command-line block simulation flow (Vivado xsim) |
| `docs/` | Architecture / micro-architecture spec, decisions, diagrams |

## Roadmap

- [x] **Phase 0 — Architecture model.** C++ model of the geometry and tile
      paths, used for design-space exploration (tile size vs. SRAM budget vs.
      memory traffic) and as the golden reference. Decisions measured and
      recorded (D-01 … D-11).
- [ ] **Phase 1 — Fixed-function pipeline** *(in progress)*. Vertex transform,
      clip / cull, binner, tile buffer (SRAM), rasterizer, HSR / depth, blend.
      No shaders.
- [ ] **Phase 2 — Scalar shader core.** Single ALU, single thread, no warps —
      closer to a small VLIW / scalar unit than a GPU.
- [ ] **Phase 3 — SIMD.** Multiple lanes (e.g. 4) executing the same
      instruction in lockstep.
- [ ] **Phase 4 — SIMT.** Warp / active-lane masks, divergence stack,
      reconvergence — where it starts looking like a real GPU shader core.

## Status — Phase 1 bring-up

- **Geometry fetch** — implemented and **verified** against a block-level UVM
  test (descriptor read → index / vertex fetch → 256-bit vertex stream).
- **Floating-point units** — `fp_mul`, `fp_add`, `fp_recip` ($1/x$) and
  `fp_rsqrt` ($1/\sqrt{x}$) wrappers around FloPoCo-generated cores, behind a
  stable `fp_*` interface (interim per D-11; hand-written units later).
- **Vertex shader / clip-cull** — in design (MVP transform + Gouraud lighting;
  perspective divide, viewport, back-face and off-screen culling).

## Architecture (high level)

![Architecture](docs/architecture.png)

## Verification

- **Golden model:** the Phase 0 C++ model is the pixel-accurate reference.
- **Block-level UVM:** a shared UVM environment with per-block tests. A
  lightweight command-line flow (`ip/scripts/sim.sh <block>`) compiles a block's
  RTL plus the testbench and runs its test with Vivado xsim — no Vivado project
  required.

## Platform and tools

- Digilent Arty Z7 (Zynq-7000 XC7Z020) — FPGA prototype
- Vivado / xsim, UVM (mixed VHDL + SystemVerilog)
- FloPoCo — floating-point core generation (interim FP units)
- OpenROAD / OpenLane — target ASIC flow
- C++ — Phase 0 golden model

## References

- ARM Mali GPU Architecture Overview whitepapers (developer.arm.com)
- Imagination PowerVR TBDR patents (Google Patents — "tile based deferred
  rendering hidden surface removal")
