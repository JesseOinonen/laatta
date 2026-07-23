// AXI4 full slave: a behavioural DRAM model.
//
// The GPU is the AXI4 master. This component owns the slave side of the DRAM
// port (the dram_* signals in axi_if) and answers the GPU's read/write bursts
// out of a byte-addressed associative memory.
//
// It supports:
//   * INCR read bursts  — vertex / index / param / draw-descriptor fetch
//   * INCR write bursts — framebuffer / tile writeback
//   * backdoor preload  — load the golden model's *.bin buffers before a test
//
// FIXED/WRAP bursts are not modelled (INCR is all the pipeline needs); an
// unexpected burst type is flagged rather than silently mis-served.
class axi4_slave extends uvm_component;

    `uvm_component_utils(axi4_slave)

    virtual axi_if axi_vif;

    // Byte-addressed backing store. Unwritten bytes read back as 0x00.
    local logic [7:0] mem[int];

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual axi_if)::get(this, "", "axi_vif", axi_vif))
            `uvm_fatal("AXI_IF_NOT_FOUND", "Virtual interface not found in configuration database")
    endfunction

    // -------------------------------------------------------------------
    // Backdoor access (call before/after a run, e.g. from the vseq)
    // -------------------------------------------------------------------
    function void poke_byte(input logic [31:0] addr, input logic [7:0] b);
        mem[addr] = b;
    endfunction

    function logic [7:0] peek_byte(input logic [31:0] addr);
        return mem.exists(addr) ? mem[addr] : 8'h00;
    endfunction

    // Little-endian 64-bit word helpers.
    function void poke_word(input logic [31:0] addr, input logic [63:0] data);
        for (int i = 0; i < 8; i++) mem[addr + i] = data[8*i +: 8];
    endfunction

    function logic [63:0] peek_word(input logic [31:0] addr);
        logic [63:0] w = '0;
        for (int i = 0; i < 8; i++) w[8*i +: 8] = peek_byte(addr + i);
        return w;
    endfunction

    // Load a raw binary buffer (e.g. model/output/vertex_buffer.bin) at `base`.
    function void load_bin(input string path, input logic [31:0] base);
        int   fd, c, n;
        fd = $fopen(path, "rb");
        if (fd == 0) begin
            `uvm_error("AXI4_SLV", $sformatf("Cannot open %s", path))
            return;
        end
        n = 0;
        c = $fgetc(fd);
        while (c != -1) begin
            mem[base + n] = c[7:0];
            n++;
            c = $fgetc(fd);
        end
        $fclose(fd);
        `uvm_info("AXI4_SLV", $sformatf("Loaded %0d bytes from %s at 0x%08h", n, path, base), UVM_LOW)
    endfunction

    // -------------------------------------------------------------------
    // Bus service
    // -------------------------------------------------------------------
    task run_phase(uvm_phase phase);
        // Drive slave-side outputs to a benign idle state.
        axi_vif.dram_arready <= 0;
        axi_vif.dram_rvalid  <= 0;
        axi_vif.dram_rlast   <= 0;
        axi_vif.dram_rdata   <= '0;
        axi_vif.dram_rresp   <= 2'b00;
        axi_vif.dram_rid     <= '0;
        axi_vif.dram_awready <= 0;
        axi_vif.dram_wready  <= 0;
        axi_vif.dram_bvalid  <= 0;
        axi_vif.dram_bresp   <= 2'b00;
        axi_vif.dram_bid     <= '0;

        fork
            read_server();
            write_server();
        join_none
    endtask

    // Serves one read burst at a time (sufficient for the pipeline's use).
    task read_server();
        logic [31:0] addr;
        logic [7:0]  len;
        logic [2:0]  size;
        logic [3:0]  id;
        int          bytes;
        forever begin
            @(posedge axi_vif.clk);
            if (axi_vif.dram_arvalid) begin
                addr = axi_vif.dram_araddr;
                len  = axi_vif.dram_arlen;
                size = axi_vif.dram_arsize;
                id   = axi_vif.dram_arid;
                if (axi_vif.dram_arburst != 2'b01)
                    `uvm_warning("AXI4_SLV", "Only INCR read bursts are modelled")
                // Accept the address.
                axi_vif.dram_arready <= 1;
                @(posedge axi_vif.clk);
                axi_vif.dram_arready <= 0;
                // Return the data beats.
                bytes = 1 << size;
                for (int i = 0; i <= len; i++) begin
                    axi_vif.dram_rid    <= id;
                    axi_vif.dram_rdata  <= peek_word(addr);
                    axi_vif.dram_rresp  <= 2'b00; // OKAY
                    axi_vif.dram_rlast  <= (i == len);
                    axi_vif.dram_rvalid <= 1;
                    @(posedge axi_vif.clk iff axi_vif.dram_rready);
                    addr = addr + bytes;
                end
                axi_vif.dram_rvalid <= 0;
                axi_vif.dram_rlast  <= 0;
            end
        end
    endtask

    // Serves one write burst at a time.
    task write_server();
        logic [31:0] addr;
        logic [7:0]  len;
        logic [2:0]  size;
        logic [3:0]  id;
        int          bytes;
        forever begin
            @(posedge axi_vif.clk);
            if (axi_vif.dram_awvalid) begin
                addr = axi_vif.dram_awaddr;
                len  = axi_vif.dram_awlen;
                size = axi_vif.dram_awsize;
                id   = axi_vif.dram_awid;
                if (axi_vif.dram_awburst != 2'b01)
                    `uvm_warning("AXI4_SLV", "Only INCR write bursts are modelled")
                axi_vif.dram_awready <= 1;
                @(posedge axi_vif.clk);
                axi_vif.dram_awready <= 0;
                // Accept the data beats.
                bytes = 1 << size;
                axi_vif.dram_wready <= 1;
                for (int i = 0; i <= len; i++) begin
                    @(posedge axi_vif.clk iff axi_vif.dram_wvalid);
                    for (int b = 0; b < bytes; b++)
                        if (axi_vif.dram_wstrb[b])
                            mem[addr + b] = axi_vif.dram_wdata[8*b +: 8];
                    addr = addr + bytes;
                end
                axi_vif.dram_wready <= 0;
                // Write response.
                axi_vif.dram_bid    <= id;
                axi_vif.dram_bresp  <= 2'b00; // OKAY
                axi_vif.dram_bvalid <= 1;
                @(posedge axi_vif.clk iff axi_vif.dram_bready);
                axi_vif.dram_bvalid <= 0;
            end
        end
    endtask

endclass
