import uvm_pkg::*;
import gpu_pkg::*;
`include "uvm_macros.svh"

`timescale 1ns/1ps

// Block-level TB top for the geometry_fetch RTL (VHDL, instantiated mixed
// language). Reuses the UVM env's axi_if + axi4_slave DRAM model: the block's
// AXI4 read master drives the dram_* read channel, and its 256-bit vertex
// stream goes to the wider v_t* signals added to axi_if.
//
// Elaborate with this module as the top (not `top`) and select the test with
// +UVM_TESTNAME=geometry_fetch_test.
module top_geometry_fetch;

    logic clk;
    logic rst;   // active high (rst_gen); the block wants active-low rst_n

    rst_gen       u_rst_gen (.rst(rst));
    clk_gen100MHz u_clk_gen (.clk(clk));

    axi_if tb_axi(clk, rst);

    // VHDL DUT.
    geometry_fetch u_dut (
        .clk_in  (clk),
        .rst_n   (~rst),

        // AXI4 read master -> DRAM read channel of axi_if
        .araddr  (tb_axi.dram_araddr),
        .arvalid (tb_axi.dram_arvalid),
        .arready (tb_axi.dram_arready),
        .arsize  (tb_axi.dram_arsize),
        .arburst (tb_axi.dram_arburst),
        .arlen   (tb_axi.dram_arlen),
        .rdata   (tb_axi.dram_rdata),
        .rvalid  (tb_axi.dram_rvalid),
        .rready  (tb_axi.dram_rready),
        .rlast   (tb_axi.dram_rlast),
        .rresp   (tb_axi.dram_rresp),

        // 256-bit vertex stream -> block bring-up signals
        .tdata   (tb_axi.v_tdata),
        .tvalid  (tb_axi.v_tvalid),
        .tready  (tb_axi.v_tready),
        .tlast   (tb_axi.v_tlast),

        .start   (tb_axi.start)
    );

    initial begin
        // Tie off the DRAM write channel (the block never writes) and the
        // read-ID input the block does not drive, so the slave sees clean 0s.
        tb_axi.dram_arid   = '0;
        tb_axi.dram_awvalid = 0;
        tb_axi.dram_wvalid  = 0;
        tb_axi.dram_bready  = 0;

        tb_axi.start    = 0;
        tb_axi.v_tready = 1;

        uvm_config_db#(virtual axi_if)::set(null, "uvm_test_top", "axi_vif", tb_axi);
        run_test();
    end

endmodule
