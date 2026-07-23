// Base virtual sequence: gives tests one place to reach every interface —
// CSR read/write, stream injection, output capture, and DRAM backdoor preload.
class gpu_vseq_base extends uvm_sequence #(uvm_sequence_item);

    `uvm_object_utils(gpu_vseq_base)

    uvm_sequencer #(axi_lite_seq_item)   axi_lite_seqr;
    uvm_sequencer #(axi_stream_seq_item) axi_stream_seqr;
    virtual axi_if                       axi_vif;   // direct access for stream_recv
    axi4_slave                           dram;      // DRAM backdoor preload

    function new(string name = "gpu_vseq_base");
        super.new(name);
    endfunction

    // --- CSR (AXI4-Lite) ---
    task csr_write(input logic [31:0] addr, input logic [31:0] data);
        axi_lite_write_seq wr_seq;
        wr_seq      = axi_lite_write_seq::type_id::create("wr_seq");
        wr_seq.addr = addr;
        wr_seq.data = data;
        wr_seq.start(axi_lite_seqr);
    endtask

    task csr_read(input logic [31:0] addr, output logic [31:0] data);
        axi_lite_read_seq rd_seq;
        rd_seq      = axi_lite_read_seq::type_id::create("rd_seq");
        rd_seq.addr = addr;
        rd_seq.start(axi_lite_seqr);
        data = rd_seq.data;
    endtask

    // --- Output stream capture ---
    task stream_recv(output logic [63:0] data_out[], output int beat_count);
        axi_vif.stream_recv(data_out, beat_count);
    endtask

    task body();
    endtask

endclass
