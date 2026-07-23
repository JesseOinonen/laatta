// Generic stream stimulus: drives a caller-supplied queue of beats onto the
// DUT stream input. TLAST is asserted on the final beat automatically.
// Load `beats` (and optionally `keeps`) before start(), or subclass body().
class stream_pkt_seq extends uvm_sequence #(axi_stream_seq_item);

    `uvm_object_utils(stream_pkt_seq)

    logic [63:0] beats[$];
    logic [7:0]  keeps[$];   // optional; defaults to 0xFF per beat

    function new(string name = "stream_pkt_seq");
        super.new(name);
    endfunction

    protected task send_beat(logic [63:0] data, logic [7:0] keep, logic last);
        axi_stream_seq_item beat;
        beat = axi_stream_seq_item::type_id::create("beat");
        start_item(beat);
        beat.tdata = data;
        beat.tkeep = keep;
        beat.tlast = last;
        finish_item(beat);
    endtask

    task body();
        foreach (beats[i])
            send_beat(beats[i],
                      (i < keeps.size()) ? keeps[i] : 8'hFF,
                      (i == beats.size() - 1));
    endtask

endclass
