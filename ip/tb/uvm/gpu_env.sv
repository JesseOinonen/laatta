class gpu_env extends uvm_env;

    `uvm_component_utils(gpu_env)

    axi_lite_agent      csr_agent;    // CSR master (optional — drop if register-less)
    axi_stream_agent    stream_agent; // block-to-block fabric stimulus/monitor
    axi4_agent          dram_agent;   // AXI4 full DRAM memory model
    axi_lite_scoreboard sb;           // CSR shadow/check

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        csr_agent    = axi_lite_agent::type_id::create("csr_agent", this);
        stream_agent = axi_stream_agent::type_id::create("stream_agent", this);
        dram_agent   = axi4_agent::type_id::create("dram_agent", this);
        sb           = axi_lite_scoreboard::type_id::create("sb", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        csr_agent.ap.connect(sb.ap);
    endfunction

endclass
