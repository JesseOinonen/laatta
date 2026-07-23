// Passive observer of the AXI4 DRAM bus. Publishes each completed read/write
// burst as an axi4_seq_item for logging / a future traffic scoreboard
// (the golden model counts DRAM traffic at burst granularity — see
// documentation.md Phase 0 measurements).
class axi4_monitor extends uvm_monitor;

    `uvm_component_utils(axi4_monitor)

    virtual axi_if axi_vif;
    uvm_analysis_port #(axi4_seq_item) ap;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        ap = new("ap", this);
        if (!uvm_config_db#(virtual axi_if)::get(this, "", "axi_vif", axi_vif))
            `uvm_fatal("AXI_IF_NOT_FOUND", "Virtual interface not found in configuration database")
    endfunction

    task run_phase(uvm_phase phase);
        fork
            monitor_reads();
            monitor_writes();
        join_none
    endtask

    task monitor_reads();
        axi4_seq_item tr;
        forever begin
            @(posedge axi_vif.clk iff (axi_vif.dram_arvalid && axi_vif.dram_arready));
            tr          = axi4_seq_item::type_id::create("rd");
            tr.is_write = 0;
            tr.addr     = axi_vif.dram_araddr;
            tr.len      = axi_vif.dram_arlen;
            tr.size     = axi_vif.dram_arsize;
            tr.burst    = axi_vif.dram_arburst;
            tr.id       = axi_vif.dram_arid;
            // Collect the returned beats.
            for (int i = 0; i <= tr.len; i++) begin
                @(posedge axi_vif.clk iff (axi_vif.dram_rvalid && axi_vif.dram_rready));
                tr.data.push_back(axi_vif.dram_rdata);
            end
            `uvm_info("AXI4_MON", tr.convert2string(), UVM_HIGH)
            ap.write(tr);
        end
    endtask

    task monitor_writes();
        axi4_seq_item tr;
        forever begin
            @(posedge axi_vif.clk iff (axi_vif.dram_awvalid && axi_vif.dram_awready));
            tr          = axi4_seq_item::type_id::create("wr");
            tr.is_write = 1;
            tr.addr     = axi_vif.dram_awaddr;
            tr.len      = axi_vif.dram_awlen;
            tr.size     = axi_vif.dram_awsize;
            tr.burst    = axi_vif.dram_awburst;
            tr.id       = axi_vif.dram_awid;
            for (int i = 0; i <= tr.len; i++) begin
                @(posedge axi_vif.clk iff (axi_vif.dram_wvalid && axi_vif.dram_wready));
                tr.data.push_back(axi_vif.dram_wdata);
            end
            `uvm_info("AXI4_MON", tr.convert2string(), UVM_HIGH)
            ap.write(tr);
        end
    endtask

endclass
