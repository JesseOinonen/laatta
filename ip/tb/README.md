# Laatta GPU — UVM testbench

Ported from the zynq-networking-dataplane UVM environment and retargeted to the
GPU IP. Same shape (single package, agent/env/test split, `make regression`),
different interfaces.

## Interfaces modelled

| Interface | Direction | Model | Purpose |
|---|---|---|---|
| **AXI4-Stream** | block ↔ block | `axi_stream_agent` (driver + monitor) | inter-stage fabric; inject/capture beats |
| **AXI4 full** | GPU master → TB slave | `axi4_agent` (`axi4_slave` memory model + monitor) | DRAM: vertex/index/param reads, framebuffer writeback, burst-level traffic monitoring |
| **AXI4-Lite** | TB master → GPU slave | `axi_lite_agent` + `axi_lite_scoreboard` | CSR control/status — **optional**, drop if the GPU ends up register-less |

The DRAM model is byte-addressed and supports backdoor preload
(`dram.poke_word`, `dram.load_bin`) so a test can drop the golden model's
`output/*.bin` buffers straight into memory (`memory_map.h` layout).

## Layout

```
tb/
  top/    top.sv (DUT + config_db), axi_if.sv (all signals + BFM tasks),
          submodules.sv (clk/rst), register.svh (CSR map, mirrors memory_map.h)
  uvm/    gpu_pkg.sv — the ONLY compilation unit; `include`s everything below
          agents, seq_items, sequences, gpu_env / gpu_test_base / gpu_vseq_base
  cases/  csr_test, stream_test, dram_read_test, datapath_test
```

## Running

The TB instantiates `laatta_gpu_top` — it compiles and runs once that RTL top
exists in `ip/rtl` with the port list in `top/top.sv`. Then:

```
cd ip
make build              # create the Vivado project
make sim  TEST=csr_test # one test
make regression         # all tests in $(TESTS)
make testcase-foo       # scaffold cases/foo_test.sv + wire it up
```

`dram_read_test` also backdoor-self-checks the DRAM model, so its memory logic
is verifiable even before the DUT exists.

## Ported fixes

- `top.sv` no longer initialises DUT-driven signals (the original set `ARREADY`,
  a slave output — a multi-driver conflict). TB only drives TB-owned signals.
