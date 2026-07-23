// Independent clock and reset generators for the TB top.

module clk_gen100MHz (output logic clk);
    initial begin
        clk = 0;
        forever #5ns clk = ~clk; // 100 MHz PL clock (Arty Z7)
    end
endmodule

module rst_gen (output logic rst);
    initial begin
        rst = 1;
        #100ns;
        rst = 0;
    end
endmodule
