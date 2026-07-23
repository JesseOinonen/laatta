// CSR smoke test: write/read-back a control register over AXI4-Lite.
// (Rename/retarget once the real register file exists; this only proves the
//  CSR path and the scoreboard shadow are wired up.)
class csr_vseq extends gpu_vseq_base;

    `uvm_object_utils(csr_vseq)

    function new(string name = "csr_vseq");
        super.new(name);
    endfunction

    task body();
        logic [31:0] rdata;

        #10ns;
        // Program the DRAM base registers from the model's memory map.
        csr_write(`GPU_VB_BASE, `MMAP_VB_BASE);
        csr_write(`GPU_IB_BASE, `MMAP_IB_BASE);
        csr_write(`GPU_FB_BASE, `MMAP_FB_BASE);

        // Read one back and check.
        csr_read(`GPU_VB_BASE, rdata);
        if (rdata !== `MMAP_VB_BASE)
            `uvm_error("CSR_TEST", $sformatf("VB_BASE mismatch: exp 0x%08h got 0x%08h", `MMAP_VB_BASE, rdata))
        else
            `uvm_info("CSR_TEST", $sformatf("VB_BASE read-back OK: 0x%08h", rdata), UVM_LOW)
    endtask

endclass

class csr_test extends gpu_test_base;
    `uvm_component_utils(csr_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    virtual task run_test_body(uvm_phase phase);
        csr_vseq vseq = csr_vseq::type_id::create("vseq");
        bind_vseq(vseq);
        vseq.start(null);
    endtask

endclass
