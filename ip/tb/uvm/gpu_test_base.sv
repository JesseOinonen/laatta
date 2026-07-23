class gpu_test_base extends uvm_test;

    `uvm_component_utils(gpu_test_base)

    gpu_env        env;
    virtual axi_if axi_vif;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        // Keep report_phase reachable so the pass/fail summary always prints.
        uvm_top.set_report_severity_action(UVM_FATAL, UVM_DISPLAY | UVM_LOG | UVM_COUNT);
        if (!uvm_config_db#(virtual axi_if)::get(this, "", "axi_vif", axi_vif))
            `uvm_fatal("VIF_NOT_FOUND", "Virtual interface not found in config db")
        uvm_config_db#(virtual axi_if)::set(this, "env.csr_agent.*",    "axi_vif", axi_vif);
        uvm_config_db#(virtual axi_if)::set(this, "env.stream_agent.*", "axi_vif", axi_vif);
        uvm_config_db#(virtual axi_if)::set(this, "env.dram_agent.*",   "axi_vif", axi_vif);
        env = gpu_env::type_id::create("env", this);
    endfunction

    task run_phase(uvm_phase phase);
        phase.raise_objection(this);
        wait (axi_vif.rst === 1'b0); // wait for reset deassertion
        run_test_body(phase);
        phase.drop_objection(this);
    endtask

    virtual task run_test_body(uvm_phase phase);
    endtask

    // Wire the shared sequencer / interface / DRAM handles into a vseq.
    protected function void bind_vseq(gpu_vseq_base vseq);
        vseq.axi_lite_seqr   = env.csr_agent.seqr;
        vseq.axi_stream_seqr = env.stream_agent.seqr;
        vseq.axi_vif         = axi_vif;
        vseq.dram            = env.dram_agent.slave;
    endfunction

    function void report_phase(uvm_phase phase);
        uvm_report_server svr = uvm_report_server::get_server();
        int err_count = svr.get_severity_count(UVM_ERROR) +
                        svr.get_severity_count(UVM_FATAL);
        if (err_count > 0) begin
            `uvm_info("TEST_STATUS",
                $sformatf("TEST FAILED: %0d error(s)", err_count), UVM_NONE)
            $finish;
        end else begin
            `uvm_info("TEST_STATUS", "TEST PASSED", UVM_NONE)
        end
    endfunction

endclass
