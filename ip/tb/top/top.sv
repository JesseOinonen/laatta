import uvm_pkg::*;
import gpu_pkg::*;
`include "uvm_macros.svh"

`timescale 1ns/1ps

// TB top for the Laatta GPU IP.
//
// NOTE: this instantiates `laatta_gpu_top`, the (yet-to-be-written) RTL top in
// ip/rtl. The TB elaborates and runs once that module exists with the port list
// below. Adjust the port names here to match the real top when it lands.
module top;
    logic clk;
    logic rst;

    rst_gen u_rst_gen (.rst(rst));
    clk_gen100MHz u_clk_gen (.clk(clk));

    axi_if tb_axi(clk, rst);

    laatta_gpu_top #(.DATA_WIDTH(64)) u_dut (
        .clk         (clk),
        .rst         (rst),

        // ---- AXI4-Lite CSR (GPU slave) ----
        .AWADDR      (tb_axi.AWADDR),
        .AWPROT      (tb_axi.AWPROT),
        .AWVALID     (tb_axi.AWVALID),
        .AWREADY     (tb_axi.AWREADY),
        .WDATA       (tb_axi.WDATA),
        .WSTRB       (tb_axi.WSTRB),
        .WVALID      (tb_axi.WVALID),
        .WREADY      (tb_axi.WREADY),
        .BRESP       (tb_axi.BRESP),
        .BVALID      (tb_axi.BVALID),
        .BREADY      (tb_axi.BREADY),
        .ARADDR      (tb_axi.ARADDR),
        .ARPROT      (tb_axi.ARPROT),
        .ARVALID     (tb_axi.ARVALID),
        .ARREADY     (tb_axi.ARREADY),
        .RDATA       (tb_axi.RDATA),
        .RRESP       (tb_axi.RRESP),
        .RVALID      (tb_axi.RVALID),
        .RREADY      (tb_axi.RREADY),

        // ---- AXI4 full DRAM (GPU master) ----
        .dram_arid   (tb_axi.dram_arid),
        .dram_araddr (tb_axi.dram_araddr),
        .dram_arlen  (tb_axi.dram_arlen),
        .dram_arsize (tb_axi.dram_arsize),
        .dram_arburst(tb_axi.dram_arburst),
        .dram_arvalid(tb_axi.dram_arvalid),
        .dram_arready(tb_axi.dram_arready),
        .dram_rid    (tb_axi.dram_rid),
        .dram_rdata  (tb_axi.dram_rdata),
        .dram_rresp  (tb_axi.dram_rresp),
        .dram_rlast  (tb_axi.dram_rlast),
        .dram_rvalid (tb_axi.dram_rvalid),
        .dram_rready (tb_axi.dram_rready),
        .dram_awid   (tb_axi.dram_awid),
        .dram_awaddr (tb_axi.dram_awaddr),
        .dram_awlen  (tb_axi.dram_awlen),
        .dram_awsize (tb_axi.dram_awsize),
        .dram_awburst(tb_axi.dram_awburst),
        .dram_awvalid(tb_axi.dram_awvalid),
        .dram_awready(tb_axi.dram_awready),
        .dram_wdata  (tb_axi.dram_wdata),
        .dram_wstrb  (tb_axi.dram_wstrb),
        .dram_wlast  (tb_axi.dram_wlast),
        .dram_wvalid (tb_axi.dram_wvalid),
        .dram_wready (tb_axi.dram_wready),
        .dram_bid    (tb_axi.dram_bid),
        .dram_bresp  (tb_axi.dram_bresp),
        .dram_bvalid (tb_axi.dram_bvalid),
        .dram_bready (tb_axi.dram_bready),

        // ---- AXI4-Stream fabric ----
        .tvalid_in   (tb_axi.tvalid_in),
        .tdata_in    (tb_axi.tdata_in),
        .tkeep_in    (tb_axi.tkeep_in),
        .tlast_in    (tb_axi.tlast_in),
        .tready_in   (tb_axi.tready_in),
        .tvalid_out  (tb_axi.tvalid_out),
        .tdata_out   (tb_axi.tdata_out),
        .tkeep_out   (tb_axi.tkeep_out),
        .tlast_out   (tb_axi.tlast_out),
        .tready_out  (tb_axi.tready_out)
    );

    initial begin
        // Drive only TB-owned signals to a known idle state.
        // (DUT outputs — AWREADY/WREADY/ARREADY/BVALID/RVALID/RDATA/... and the
        //  dram_* slave-side signals — are driven by the DUT / axi4_slave, never
        //  here. Initialising a DUT output creates a multi-driver conflict.)
        tb_axi.AWADDR    = '0;
        tb_axi.WDATA     = '0;
        tb_axi.ARADDR    = '0;
        tb_axi.AWVALID   = 0;
        tb_axi.WVALID    = 0;
        tb_axi.ARVALID   = 0;
        tb_axi.RREADY    = 0;
        tb_axi.BREADY    = 0;
        tb_axi.WSTRB     = '0;
        tb_axi.AWPROT    = '0;
        tb_axi.ARPROT    = '0;

        tb_axi.tvalid_in = 0;
        tb_axi.tdata_in  = '0;
        tb_axi.tkeep_in  = '0;
        tb_axi.tlast_in  = 0;
        tb_axi.tready_out = 1; // output stream sink ready by default

        uvm_config_db#(virtual axi_if)::set(null, "uvm_test_top", "axi_vif", tb_axi);

        // Test selected via +UVM_TESTNAME=<name>
        run_test();
    end

endmodule
