// Single UVM compilation unit for the Laatta GPU testbench.
// Everything under uvm/ and cases/ is `include`d here — those files must NOT
// be added to the simulator file list separately.
package gpu_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"
    `include "register.svh"

    // Sequence items
    `include "axi_lite_seq_item.sv"
    `include "axi_stream_seq_item.sv"
    `include "axi4_seq_item.sv"

    // AXI4-Lite CSR agent (optional)
    `include "axi_lite_driver.sv"
    `include "axi_lite_monitor.sv"
    `include "axi_lite_scoreboard.sv"
    `include "axi_lite_agent.sv"

    // AXI4-Stream fabric agent
    `include "axi_stream_driver.sv"
    `include "axi_stream_monitor.sv"
    `include "axi_stream_agent.sv"

    // AXI4 full DRAM agent (slave memory model)
    `include "axi4_slave.sv"
    `include "axi4_monitor.sv"
    `include "axi4_agent.sv"

    // Sequences
    `include "axi_lite_seq.sv"
    `include "stream_pkt_seq.sv"

    // Virtual sequence base
    `include "gpu_vseq_base.sv"

    // Environment and test base
    `include "gpu_env.sv"
    `include "gpu_test_base.sv"

    // Tests
    `include "csr_test.sv"
    `include "stream_test.sv"
    `include "dram_read_test.sv"
    `include "axi4_read_test.sv"
    `include "geometry_fetch_test.sv"
    `include "datapath_test.sv"
endpackage
