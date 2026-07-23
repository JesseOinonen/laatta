// AXI4 full DRAM agent: the slave memory model plus a passive monitor.
// No sequencer/driver — the slave is reactive (it answers the GPU master).
class axi4_agent extends uvm_agent;

    `uvm_component_utils(axi4_agent)

    axi4_slave                        slave;
    axi4_monitor                      mon;
    uvm_analysis_port #(axi4_seq_item) ap;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        slave = axi4_slave::type_id::create("slave", this);
        mon   = axi4_monitor::type_id::create("mon", this);
        ap    = new("ap", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        mon.ap.connect(ap);
    endfunction

endclass
