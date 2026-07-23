// One observed AXI4 full burst (read or write), published by axi4_monitor.
class axi4_seq_item extends uvm_sequence_item;

    logic [31:0] addr;
    logic [7:0]  len;      // AxLEN: beats - 1
    logic [2:0]  size;     // AxSIZE: log2(bytes/beat)
    logic [1:0]  burst;    // AxBURST: 0=FIXED 1=INCR 2=WRAP
    logic [3:0]  id;
    bit          is_write;
    logic [63:0] data[$];  // one entry per beat

    `uvm_object_utils_begin(axi4_seq_item)
        `uvm_field_int(addr,     UVM_ALL_ON)
        `uvm_field_int(len,      UVM_ALL_ON)
        `uvm_field_int(size,     UVM_ALL_ON)
        `uvm_field_int(burst,    UVM_ALL_ON)
        `uvm_field_int(id,       UVM_ALL_ON)
        `uvm_field_int(is_write, UVM_ALL_ON)
        `uvm_field_queue_int(data, UVM_ALL_ON)
    `uvm_object_utils_end

    function new(string name = "axi4_seq_item");
        super.new(name);
    endfunction

    function string convert2string();
        return $sformatf("AXI4 %s: addr=0x%08h len=%0d size=%0d burst=%0d beats=%0d",
                         is_write ? "WRITE" : "READ", addr, len, size, burst, data.size());
    endfunction

endclass
