# Block-level simulation

A lightweight, project-agnostic simulation flow for individual RTL blocks,
driven by `ip/scripts/sim.sh`. It uses the Vivado xsim command-line tools
(`xvhdl` / `xvlog` / `xelab` / `xsim`) directly — no Vivado project — so a block
can be compiled and simulated in one command. The Vivado *project* flow
(`make build` / `make sim` in `ip/`) stays available separately for GUI project
work and sharing.

## Running

```
scripts/sim.sh <block>            # compile + elaborate + run the block's test
scripts/sim.sh <block> rtl        # analyse + elaborate the RTL alone, no TB
scripts/sim.sh <block> compile    # analyse RTL + testbench only
scripts/sim.sh <block> elab       # up to elaboration
scripts/sim.sh <block> gui        # open the waveform GUI
scripts/sim.sh <block> clean      # remove the build dir
```

Override the test or the Vivado location:

```
TEST=some_test           scripts/sim.sh <block>
VIVADO_BIN=/opt/.../bin  scripts/sim.sh <block>
```

Build artefacts land in `ip/sim/build/<block>/` (gitignored). The waveform GUI
reuses the snapshot built there, so `gui` works without rebuilding.

## Checking RTL while a block is still being written

`rtl` is the odd one out: it analyses the block's RTL and elaborates the entity
named after the block, with no testbench and no UVM. It therefore needs only
the file list, not a top or a test, which makes it the check to run on a block
that does not compile yet. It is wired into the `ip/` Makefile:

```
make check-vertex_shader   # one block
make check                 # every block that has a file list
```

`make check` is the one that catches a change to `laatta_pkg` breaking a block
you were not working on. It fails the build if any block fails.

## Adding a block

Three things, by convention:

| File | Purpose |
|---|---|
| `ip/sim/<block>.f` | RTL file list, in compile order, paths relative to `ip/`. `.vhdl` → `xvhdl`, `.sv`/`.v` → `xvlog`. |
| `ip/tb/top/top_<block>.sv` | Block-level TB top, module named `top_<block>`. Instantiates the DUT, wires it to the shared `axi_if`, and calls `run_test()`. |
| `ip/tb/cases/<block>_test.sv` | UVM test named `<block>_test`, `` `include ``d from `gpu_pkg.sv`. |

The shared testbench (`gpu_pkg.sv`, `axi_if.sv`, `submodules.sv`) and the UVM
agents/env are reused for every block, so a new block only needs its RTL list,
its top, and its test.

Only the first of the three is needed for `scripts/sim.sh <block> rtl`, so a
block can be checked from its very first line of RTL and gains its top and test
once it is worth simulating.

## Example: `geometry_fetch`

- `ip/sim/geometry_fetch.f` — `laatta_pkg.vhdl`, `common/cg.vhdl`,
  `geometry_fetch.vhdl`
- `ip/tb/top/top_geometry_fetch.sv` — wires the block's AXI4 read master to the
  DRAM model and its 256-bit vertex stream to `axi_if.v_t*`
- `ip/tb/cases/geometry_fetch_test.sv` — preloads a scene, pulses `start`,
  checks the output vertices against `vb[indices[k]]`

```
scripts/sim.sh geometry_fetch
```

## Example: `vertex_shader`

RTL only so far — `ip/sim/vertex_shader.f` lists the package, the clock gate,
the FloPoCo cores and fp wrappers, `dot_product` and the block itself. It has no
top or test yet, so `rtl` is the action it supports:

```
make check-vertex_shader
```
