// Testbench interface for the Laatta GPU IP.
//
// Three groups of signals, one per external interface of the GPU top:
//   1. AXI4-Lite (CSR)     — TB is master, GPU is slave. Control/status regs.
//                            Optional; drop it if the GPU ends up register-less.
//   2. AXI4 full  (DRAM)   — GPU is master, TB is slave (a DRAM memory model).
//                            Vertex/index/param reads and framebuffer writes.
//   3. AXI4-Stream (fabric)— point-to-point stream between pipeline blocks.
//                            Used by block-level tests to inject/capture beats.
//
// The AXI-Lite and AXI-Stream master-side BFM tasks live here (same style as
// the original dataplane TB). The AXI4 DRAM slave is serviced by the
// axi4_slave UVM component, which only touches the dram_* signals below.

interface axi_if(input logic clk, input logic rst);

// ---------------------------------------------------------------------------
// 1. AXI4-Lite CSR  (TB master -> GPU slave)
// ---------------------------------------------------------------------------
logic [31:0] AWADDR, WDATA, ARADDR, RDATA;
logic        AWVALID, WVALID, ARVALID, RREADY, BREADY;
logic        AWREADY, WREADY, ARREADY, RVALID, BVALID;
logic [3:0]  WSTRB;
logic [1:0]  BRESP, RRESP;
logic [2:0]  AWPROT, ARPROT;

// ---------------------------------------------------------------------------
// 2. AXI4 full DRAM  (GPU master -> TB slave / memory model)
//    64-bit data (matches the Zynq PS HP port and the 64 B DRAM burst).
// ---------------------------------------------------------------------------
// Read address channel
logic [3:0]  dram_arid;
logic [31:0] dram_araddr;
logic [7:0]  dram_arlen;
logic [2:0]  dram_arsize;
logic [1:0]  dram_arburst;
logic        dram_arvalid;
logic        dram_arready;
// Read data channel
logic [3:0]  dram_rid;
logic [63:0] dram_rdata;
logic [1:0]  dram_rresp;
logic        dram_rlast;
logic        dram_rvalid;
logic        dram_rready;
// Write address channel
logic [3:0]  dram_awid;
logic [31:0] dram_awaddr;
logic [7:0]  dram_awlen;
logic [2:0]  dram_awsize;
logic [1:0]  dram_awburst;
logic        dram_awvalid;
logic        dram_awready;
// Write data channel
logic [63:0] dram_wdata;
logic [7:0]  dram_wstrb;
logic        dram_wlast;
logic        dram_wvalid;
logic        dram_wready;
// Write response channel
logic [3:0]  dram_bid;
logic [1:0]  dram_bresp;
logic        dram_bvalid;
logic        dram_bready;

// ---------------------------------------------------------------------------
// 3. AXI4-Stream  (block <-> block fabric)
// ---------------------------------------------------------------------------
// Stream into the DUT (TB drives)
logic        tvalid_in;
logic [63:0] tdata_in;
logic [7:0]  tkeep_in;
logic        tlast_in;
logic        tready_in;
// Stream out of the DUT (TB sinks)
logic        tvalid_out;
logic [63:0] tdata_out;
logic [7:0]  tkeep_out;
logic        tlast_out;
logic        tready_out;

// ---------------------------------------------------------------------------
// 4. Block bring-up (geometry_fetch): direct start + 256-bit vertex stream.
//    The full-GPU fabric above is 64-bit; a single block emits whole 256-bit
//    vertices, so it gets its own wider stream here until the shader consumes it.
// ---------------------------------------------------------------------------
logic         start;       // start pulse into the block
logic [255:0] v_tdata;     // one 32 B vertex per beat
logic         v_tvalid;
logic         v_tready;
logic         v_tlast;

// ===========================================================================
// AXI4-Lite master BFM tasks
// ===========================================================================
task automatic write(input logic [31:0] addr, input logic [31:0] data);
    @(posedge clk);
    AWADDR  = addr;
    AWVALID = 1;
    WDATA   = data;
    WSTRB   = 4'b1111;
    WVALID  = 1;

    // AW and W channels are independent — handle them in parallel
    fork
        begin : aw_channel
            fork
                begin
                    @(posedge clk iff (AWVALID && AWREADY));
                    AWVALID = 0;
                end
                begin
                    #500ns;
                    $error("Timeout waiting for AWREADY");
                end
            join_any
            disable fork;
        end
        begin : w_channel
            fork
                begin
                    @(posedge clk iff (WVALID && WREADY));
                    WVALID = 0;
                end
                begin
                    #500ns;
                    $error("Timeout waiting for WREADY");
                end
            join_any
            disable fork;
        end
    join

    // Write response — assert BREADY before waiting for BVALID
    BREADY = 1;
    fork
        begin
            @(posedge clk iff (BVALID && BREADY));
            BREADY = 0;
        end
        begin
            #500ns;
            $error("Timeout waiting for BVALID");
        end
    join_any
    disable fork;
endtask

task automatic read(input logic [31:0] addr, output logic [31:0] data);
    @(posedge clk);
    ARADDR  = addr;
    ARVALID = 1;
    RREADY  = 1;

    fork
        begin
            @(posedge clk iff (ARVALID && ARREADY));
            ARVALID = 0;
        end
        begin
            #500ns;
            $error("Timeout waiting for ARREADY");
        end
    join_any
    disable fork;

    fork
        begin
            @(posedge clk iff (RVALID && RREADY));
            data   = RDATA;
            RREADY = 0;
        end
        begin
            #500ns;
            $error("Timeout waiting for RVALID");
        end
    join_any
    disable fork;
endtask

// ===========================================================================
// AXI4-Stream master BFM tasks
// ===========================================================================
// Drive one beat into the DUT stream input.
task automatic stream_send(input logic [63:0] data, input logic [7:0] keep, input logic last);
    tdata_in  = data;
    tkeep_in  = keep;
    tlast_in  = last;
    tvalid_in = 1;
    fork
        begin
            @(posedge clk iff tready_in);
            tvalid_in = 0;
        end
        begin
            #500ns;
            $error("Timeout waiting for tready_in");
        end
    join_any
    disable fork;
endtask

// Sink one full packet from the DUT stream output.
task automatic stream_recv(output logic [63:0] data_out[], output int beat_count);
    logic [63:0] pkt[1024];
    int          n;
    n          = 0;
    tready_out = 1;
    fork
        begin
            forever begin
                @(posedge clk);
                if (tvalid_out && tready_out) begin
                    pkt[n] = tdata_out;
                    n++;
                    if (tlast_out) break;
                end
            end
            tready_out = 0;
        end
        begin
            #50us;
            $error("Timeout waiting for output packet");
        end
    join_any
    disable fork;
    beat_count = n;
    data_out   = new[n];
    foreach (data_out[i]) data_out[i] = pkt[i];
endtask

endinterface
