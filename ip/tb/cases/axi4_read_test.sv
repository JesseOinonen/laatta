// AXI4 read test: verify the DUT's read path.
//
// Preloads a couple of DRAM addresses with known patterns, then (once the RTL
// master is wired into tb_top) triggers reads of those addresses and checks
// that what comes back on the R channel matches what was preloaded. Until the
// DUT exists the backdoor self-check below still proves the memory model
// returns the right bytes, so the preload half of the test is verifiable now.
//
// Skeleton only: the trigger and the read-vs-expected comparison are marked
// TODO, to be filled in once geometry_fetch (or axi4_read alone) drives the
// dram_* master signals.
class axi4_read_vseq extends gpu_vseq_base;

    `uvm_object_utils(axi4_read_vseq)

    // Two distinct addresses with recognisable data. Kept as members so the
    // trigger/verify step can reuse the same expected values.
    localparam logic [31:0] ADDR_A = `MMAP_VB_BASE + 32'h0000;
    localparam logic [31:0] ADDR_B = `MMAP_VB_BASE + 32'h0040;
    localparam logic [63:0] DATA_A = 64'hDEAD_BEEF_0000_0001;
    localparam logic [63:0] DATA_B = 64'hCAFE_F00D_0000_0002;

    function new(string name = "axi4_read_vseq");
        super.new(name);
    endfunction

    task body();
        logic [63:0] rb;

        #10ns;

        // --- Preload the two addresses (backdoor, no sim time on the bus) ---
        dram.poke_word(ADDR_A, DATA_A);
        dram.poke_word(ADDR_B, DATA_B);

        // --- Self-check the memory model (passes with no DUT) ---
        rb = dram.peek_word(ADDR_A);
        if (rb !== DATA_A)
            `uvm_error("AXI4_RD", $sformatf("Preload A mismatch at 0x%08h: exp 0x%016h got 0x%016h",
                                            ADDR_A, DATA_A, rb))
        else
            `uvm_info("AXI4_RD", "Preload A OK in DRAM model", UVM_LOW)

        rb = dram.peek_word(ADDR_B);
        if (rb !== DATA_B)
            `uvm_error("AXI4_RD", $sformatf("Preload B mismatch at 0x%08h: exp 0x%016h got 0x%016h",
                                            ADDR_B, DATA_B, rb))
        else
            `uvm_info("AXI4_RD", "Preload B OK in DRAM model", UVM_LOW)

        // --- Trigger the DUT to read ADDR_A and ADDR_B ---------------------
        // TODO: once the RTL master is instantiated in tb_top, kick it here.
        //   e.g. csr_write(`GPU_CMD_BASE, ADDR_A); csr_write(`GPU_CTRL, 32'h1);
        //   or pulse the block's start with the address programmed.

        // --- Verify the returned read data --------------------------------
        // TODO: capture the burst from axi4_monitor (dram_agent.ap) and check
        //   the beats equal DATA_A / DATA_B. The monitor already reconstructs
        //   whole read bursts into axi4_seq_item; a small analysis-fifo or a
        //   scoreboard subscriber compares against the expected values above.

        #1us; // room for the DUT's read bursts once it exists

        `uvm_info("AXI4_RD", "axi4_read_testcase completed", UVM_LOW)
    endtask

endclass

class axi4_read_test extends gpu_test_base;

    `uvm_component_utils(axi4_read_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    virtual task run_test_body(uvm_phase phase);
        axi4_read_vseq vseq = axi4_read_vseq::type_id::create("vseq");
        bind_vseq(vseq);
        vseq.start(null);
    endtask

endclass
