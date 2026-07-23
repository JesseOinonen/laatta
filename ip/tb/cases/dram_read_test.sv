// DRAM read test: preload the AXI4 slave memory model with a draw descriptor
// and a couple of vertices (the layout the golden model writes — see
// memory_map.h), then start the GPU. With real RTL the vertex-fetch unit
// bursts these in and axi4_monitor logs the traffic. Until then, the backdoor
// self-check below still verifies the memory model itself.
class dram_read_vseq extends gpu_vseq_base;

    `uvm_object_utils(dram_read_vseq)

    function new(string name = "dram_read_vseq");
        super.new(name);
    endfunction

    task body();
        logic [63:0] rb;

        #10ns;

        // --- Backdoor-preload DRAM ---
        // Draw descriptor at CMD_BASE: magic, vtx_count=3, idx_count=3, bases...
        dram.poke_word(`MMAP_CMD_BASE + 32'h00, {32'd3, `DRAW_MAGIC});          // idx? -> counts
        dram.poke_word(`MMAP_CMD_BASE + 32'h08, {`MMAP_VB_BASE, 32'd3});        // vb_base, idx_count
        dram.poke_word(`MMAP_CMD_BASE + 32'h10, {32'd32, `MMAP_IB_BASE});       // ib_base, stride
        // One 32 B vertex at VB_BASE (px..pz, nx..nz, u, v as raw words).
        dram.poke_word(`MMAP_VB_BASE + 32'h00, 64'h0000_0000_3F80_0000);        // px=1.0
        dram.poke_word(`MMAP_VB_BASE + 32'h08, 64'h0000_0000_0000_0000);
        dram.poke_word(`MMAP_VB_BASE + 32'h10, 64'h0000_0000_0000_0000);
        dram.poke_word(`MMAP_VB_BASE + 32'h18, 64'h0000_0000_0000_0000);
        // Alternatively, load straight from the golden model output:
        //   dram.load_bin("../../../model/output/vertex_buffer.bin", `MMAP_VB_BASE);
        //   dram.load_bin("../../../model/output/index_buffer.bin",  `MMAP_IB_BASE);

        // --- Self-check the memory model (passes with no DUT) ---
        rb = dram.peek_word(`MMAP_CMD_BASE);
        if (rb[31:0] !== `DRAW_MAGIC)
            `uvm_error("DRAM_TEST", $sformatf("Draw magic mismatch: exp 0x%08h got 0x%08h", `DRAW_MAGIC, rb[31:0]))
        else
            `uvm_info("DRAM_TEST", "Draw descriptor magic OK in DRAM model", UVM_LOW)

        rb = dram.peek_word(`MMAP_VB_BASE);
        if (rb !== 64'h0000_0000_3F80_0000)
            `uvm_error("DRAM_TEST", $sformatf("Vertex[0] mismatch: got 0x%016h", rb))
        else
            `uvm_info("DRAM_TEST", "Vertex buffer preload OK in DRAM model", UVM_LOW)

        // --- Program CSRs and kick the pipeline ---
        csr_write(`GPU_CMD_BASE, `MMAP_CMD_BASE);
        csr_write(`GPU_VB_BASE,  `MMAP_VB_BASE);
        csr_write(`GPU_IB_BASE,  `MMAP_IB_BASE);
        csr_write(`GPU_CTRL,     32'h1); // start_frame

        #1us; // let the GPU issue its DRAM read bursts (once RTL exists)

        `uvm_info("DRAM_TEST", "dram_read_testcase completed", UVM_LOW)
    endtask

endclass

class dram_read_test extends gpu_test_base;
    `uvm_component_utils(dram_read_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    virtual task run_test_body(uvm_phase phase);
        dram_read_vseq vseq = dram_read_vseq::type_id::create("vseq");
        bind_vseq(vseq);
        vseq.start(null);
    endtask

endclass
