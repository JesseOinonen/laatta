class axi_stream_monitor extends uvm_monitor;

    `uvm_component_utils(axi_stream_monitor)

    virtual axi_if axi_vif;
    uvm_analysis_port #(axi_stream_seq_item) ap;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        ap = new("ap", this);
        if (!uvm_config_db#(virtual axi_if)::get(this, "", "axi_vif", axi_vif))
            `uvm_fatal("AXI_IF_NOT_FOUND", "Virtual interface not found in configuration database")
    endfunction

    // Observes the stream input into the DUT (tvalid_in/tready_in handshake).
    task run_phase(uvm_phase phase);
        axi_stream_seq_item beat;
        forever begin
            @(posedge axi_vif.clk);
            if (axi_vif.tvalid_in && axi_vif.tready_in) begin
                beat       = axi_stream_seq_item::type_id::create("beat");
                beat.tdata = axi_vif.tdata_in;
                beat.tkeep = axi_vif.tkeep_in;
                beat.tlast = axi_vif.tlast_in;
                ap.write(beat);
            end
        end
    endtask

endclass
