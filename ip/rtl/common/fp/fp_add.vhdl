--------------------------------------
-- Floating point addition wrapper
-- FloPoCo Open-Source IP instance
-- Author: Jesse Oinonen
--------------------------------------
library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity fp_add_wrapper is
    port ( clk        : in  std_logic;                     -- System clock
           rst_n      : in  std_logic;                     -- Active low reset
           a_in       : in  std_logic_vector(31 downto 0); -- First input operand
           b_in       : in  std_logic_vector(31 downto 0); -- Second input operand
           valid_in   : in  std_logic;                     -- Operand valid signal
           result_out : out std_logic_vector(31 downto 0); -- Result output
           valid_out  : out std_logic                      -- Result valid signal
        );
end fp_add_wrapper;

architecture RTL of fp_add_wrapper is
    signal valid_shift_r : std_logic_vector(2 downto 0);
    signal a, b, result  : std_logic_vector(33 downto 0);
begin

    in_ieee_inst_a : entity work.in_ieee
        port map (
            X => a_in,
            R => a
        );

    in_ieee_inst_b : entity work.in_ieee
        port map (
            X => b_in,
            R => b
        );
    
    fp_add_inst : entity work.fp_add_core
        port map (
            clk => clk,
            X   => a,
            Y   => b,
            R   => result
        );

    out_ieee_inst : entity work.out_ieee
        port map (
            X => result,
            R => result_out
        );

    --------------------------------
    -- fp_add_core pipeline depth is 3
    -- so data is valid after 3 clock cycles
    valid_process : process(clk, rst_n)
    begin
        if rst_n = '0' then
            valid_shift_r <= (others => '0');
        elsif rising_edge(clk) then
            valid_shift_r <= valid_shift_r(1 downto 0) & valid_in;
        end if;
    end process valid_process;

    valid_out  <= valid_shift_r(2);

end RTL;