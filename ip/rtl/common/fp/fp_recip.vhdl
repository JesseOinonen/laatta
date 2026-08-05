--------------------------------------
-- Floating point reciprocal wrapper
-- FloPoCo Open-Source IP instance
-- Author: Jesse Oinonen
--------------------------------------
library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity fp_recip_wrapper is
    port ( clk        : in  std_logic;                     -- System clock
           rst_n      : in  std_logic;                     -- Active low reset
           a_in       : in  std_logic_vector(31 downto 0); -- First input operand
           valid_in   : in  std_logic;                     -- Operand valid signal
           result_out : out std_logic_vector(31 downto 0); -- Result output
           valid_out  : out std_logic                      -- Result valid signal
        );
end fp_recip_wrapper;

architecture RTL of fp_recip_wrapper is
    signal valid_shift_r : std_logic_vector(4 downto 0);
    signal a, result  : std_logic_vector(33 downto 0);
begin

    in_ieee_inst : entity work.in_ieee
        port map (
            X => a_in,
            R => a
        );
    
    fp_div_inst : entity work.fp_div_core
        port map (
            clk => clk,
            X   => "01" & "0" & "01111111" & "00000000000000000000000", -- in FloPoCo format, = 1.0
            Y   => a,
            R   => result
        );

    out_ieee_inst : entity work.out_ieee
        port map (
            X => result,
            R => result_out
        );

    --------------------------------
    -- fp_div_core pipeline depth is 5
    -- so data is valid after 5 clock cycles
    valid_process : process(clk, rst_n)
    begin
        if rst_n = '0' then
            valid_shift_r <= (others => '0');
        elsif rising_edge(clk) then
            valid_shift_r <= valid_shift_r(3 downto 0) & valid_in;
        end if;
    end process valid_process;

    valid_out  <= valid_shift_r(4);

end RTL;