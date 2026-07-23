// Stream test: inject a burst of beats on the DUT stream input and capture
// whatever comes out. The comparison is left open (TBD) until a real pipeline
// block sits between input and output — this exercises the fabric BFM path.
class stream_vseq extends gpu_vseq_base;

    `uvm_object_utils(stream_vseq)

    function new(string name = "stream_vseq");
        super.new(name);
    endfunction

    task body();
        stream_pkt_seq pkt;
        logic [63:0]   out_beats[];
        int            n;

        #10ns;
        csr_write(`GPU_CTRL, 32'h1);   // start_frame
        #10ns;

        pkt = stream_pkt_seq::type_id::create("pkt");
        pkt.beats = '{64'h0011_2233_4455_6677,
                      64'h8899_AABB_CCDD_EEFF,
                      64'hDEAD_BEEF_CAFE_F00D};
        pkt.start(axi_stream_seqr);

        // Capture the output packet (will time out harmlessly until a DUT
        // actually forwards a stream — swap in a real check then).
        // stream_recv(out_beats, n);
        // foreach (out_beats[i]) `uvm_info("STREAM_TEST",
        //     $sformatf("out[%0d]=0x%016h", i, out_beats[i]), UVM_LOW)

        `uvm_info("STREAM_TEST", "stream stimulus sent", UVM_LOW)
    endtask

endclass

class stream_test extends gpu_test_base;
    `uvm_component_utils(stream_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    virtual task run_test_body(uvm_phase phase);
        stream_vseq vseq = stream_vseq::type_id::create("vseq");
        bind_vseq(vseq);
        vseq.start(null);
    endtask

endclass
