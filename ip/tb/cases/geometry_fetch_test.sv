// Geometry-fetch block test (black box).
//
// Preloads DRAM with a draw descriptor, an index buffer and a vertex buffer in
// the memory_map.h layout, pulses start, then checks the 256-bit vertices that
// come out of the AXI4-Stream port. What goes in / what must come out:
//
//   * output vertex k must equal vb[indices[k]]  (descriptor unpack + index
//     indirection + 4-beat vertex assembly all correct)
//   * tlast is asserted on the last vertex only
//
// The index list is non-identity with a repeat (vertex 1 fetched twice), so the
// indirection and the (uncached) re-fetch paths are both exercised.
//
// Needs the geometry_fetch DUT wired into a block-level top (top_geometry_fetch)
// and the block-bring-up signals in axi_if (start, v_t*). Run with:
//   +UVM_TESTNAME=geometry_fetch_test  and elaboration top = top_geometry_fetch
class geometry_fetch_vseq extends gpu_vseq_base;

    `uvm_object_utils(geometry_fetch_vseq)

    localparam int N_VTX = 4;
    localparam int N_IDX = 4;

    function new(string name = "geometry_fetch_vseq");
        super.new(name);
    endfunction

    // Draw order: which vertex each index points at.
    function int idx_of(int k);
        case (k)
            0: return 1;
            1: return 3;
            2: return 1;   // repeat -> re-fetch
            default: return 0;
        endcase
    endfunction

    // 64-bit DRAM beat b of vertex j : {j, b} (high word = j, low word = b).
    function logic [63:0] vbeat(int j, int b);
        return {j[31:0], b[31:0]};
    endfunction

    // The assembled 256-bit vertex j : beat3 & beat2 & beat1 & beat0.
    function logic [255:0] vvertex(int j);
        return {vbeat(j,3), vbeat(j,2), vbeat(j,1), vbeat(j,0)};
    endfunction

    task body();
        logic [255:0] got [$];
        logic         got_last [$];
        int           n;

        #20ns;

        // --- Backdoor-preload DRAM (memory_map.h layout) ---
        // Draw descriptor at CMD_BASE (little-endian 64-bit words):
        dram.poke_word(`MMAP_CMD_BASE + 32'd0,  {32'd4,           `DRAW_MAGIC});   // vcount | magic
        dram.poke_word(`MMAP_CMD_BASE + 32'd8,  {`MMAP_VB_BASE,   32'd4});         // vb_base | idx_count
        dram.poke_word(`MMAP_CMD_BASE + 32'd16, {32'd32,          `MMAP_IB_BASE}); // stride | ib_base
        dram.poke_word(`MMAP_CMD_BASE + 32'd24, 64'd0);                            // flags | tex_base

        // Index buffer at IB_BASE : indices {1,3,1,0}, two per 64-bit word.
        dram.poke_word(`MMAP_IB_BASE + 32'd0, {32'd3, 32'd1});
        dram.poke_word(`MMAP_IB_BASE + 32'd8, {32'd0, 32'd1});

        // Vertex buffer at VB_BASE : 4 vertices x 4 beats.
        for (int j = 0; j < N_VTX; j++)
            for (int b = 0; b < 4; b++)
                dram.poke_word(`MMAP_VB_BASE + j*32 + b*8, vbeat(j, b));

        // --- Pulse start ---
        axi_vif.start = 0;
        @(posedge axi_vif.clk);
        axi_vif.start = 1;
        @(posedge axi_vif.clk);
        axi_vif.start = 0;

        // --- Capture the vertex stream ---
        axi_vif.v_tready = 1;
        n = 0;
        fork
            begin : capture
                forever begin
                    @(posedge axi_vif.clk);
                    if (axi_vif.v_tvalid && axi_vif.v_tready) begin
                        got.push_back(axi_vif.v_tdata);
                        got_last.push_back(axi_vif.v_tlast);
                        n++;
                        if (n == N_IDX) break;
                    end
                end
            end
            begin : watchdog
                #50us;
                `uvm_error("GF", "timeout waiting for vertices (DUT never produced the stream)")
            end
        join_any
        disable fork;

        // --- Check ---
        if (got.size() != N_IDX) begin
            `uvm_error("GF", $sformatf("got %0d of %0d vertices", got.size(), N_IDX))
        end else begin
            for (int k = 0; k < N_IDX; k++) begin
                // Data: vertex k must be vb[indices[k]].
                if (got[k] !== vvertex(idx_of(k)))
                    `uvm_error("GF", $sformatf(
                        "vertex %0d: expected vb[%0d]=%h, got %h",
                        k, idx_of(k), vvertex(idx_of(k)), got[k]))
                else
                    `uvm_info("GF", $sformatf("vertex %0d OK (vb[%0d])", k, idx_of(k)), UVM_LOW)

                // tlast: last vertex only.
                if ((k == N_IDX-1) && (got_last[k] !== 1'b1))
                    `uvm_error("GF", "tlast not set on the last vertex")
                if ((k != N_IDX-1) && (got_last[k] !== 1'b0))
                    `uvm_error("GF", $sformatf("tlast set early on vertex %0d", k))
            end
        end

        #200ns;
    endtask

endclass


class geometry_fetch_test extends gpu_test_base;

    `uvm_component_utils(geometry_fetch_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    virtual task run_test_body(uvm_phase phase);
        geometry_fetch_vseq vseq = geometry_fetch_vseq::type_id::create("vseq");
        bind_vseq(vseq);
        vseq.start(null);
    endtask

endclass
