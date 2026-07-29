--------------------------------------
-- Common IP
-- Clock gate
-- Author: Jesse Oinonen
--------------------------------------
library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity cg is
    port ( clk              : in  std_logic;
           en               : in  std_logic;
           clk_out          : out std_logic
        );
end cg;

architecture RTL of cg is
    signal en_latched : std_logic;
begin

    process(clk, en)
    begin
        if clk = '0' then
            en_latched <= en;
        end if;
    end process;

    clk_out <= clk and en_latched;
end RTL;