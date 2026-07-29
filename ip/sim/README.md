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
