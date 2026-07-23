// End-to-end datapath test (placeholder): preload a scene in DRAM, program the
// frame geometry, start a render, and compare the framebuffer the GPU writes
// back against the golden image. The comparison is TBD until the RTL top and
// its framebuffer writeback exist.
class datapath_vseq extends gpu_vseq_base;

    `uvm_object_utils(datapath_vseq)

    function new(string name = "datapath_vseq");
        super.new(name);
    endfunction

    task body();
        #10ns;

        // Scene: load the golden model's buffers straight into DRAM.
        //   dram.load_bin("../../../model/output/vertex_buffer.bin", `MMAP_VB_BASE);
        //   dram.load_bin("../../../model/output/index_buffer.bin",  `MMAP_IB_BASE);

        // Frame geometry (documentation.md: 720p, 32x32 tiles).
        csr_write(`GPU_RES_X,     32'd1280);
        csr_write(`GPU_RES_Y,     32'd720);
        csr_write(`GPU_TILE_SIZE, 32'd32);
        csr_write(`GPU_VB_BASE,   `MMAP_VB_BASE);
        csr_write(`GPU_IB_BASE,   `MMAP_IB_BASE);
        csr_write(`GPU_FB_BASE,   `MMAP_FB_BASE);

        // Kick the render.
        csr_write(`GPU_CTRL, 32'h1); // start_frame

        #10us;

        // TBD: poll GPU_STATUS.frame_done, then read back FB_BASE from the DRAM
        // model and compare pixel-for-pixel against model/output/render_tbdr.png.

        `uvm_info("DATAPATH_TEST", "datapath_testcase completed", UVM_LOW)
    endtask

endclass

class datapath_test extends gpu_test_base;
    `uvm_component_utils(datapath_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    virtual task run_test_body(uvm_phase phase);
        datapath_vseq vseq = datapath_vseq::type_id::create("vseq");
        bind_vseq(vseq);
        vseq.start(null);
    endtask

endclass
