--------------------------------------
-- Common IP
-- Active Low Reset Synchronizer
-- Author: Jesse Oinonen
--------------------------------------
library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity rst_n_sync is
    generic ( C_SYNC_DEPTH : integer := 2 );
    port ( clk              : in  std_logic;
           rst_n            : in  std_logic;
           rst_sync_n       : out std_logic
        );
end rst_n_sync;

architecture RTL of rst_n_sync is
    type t_sync_reg is array (C_SYNC_DEPTH-1 downto 0) of std_logic;
    signal r_sync : t_sync_reg;
begin

    process(clk, rst_n)
    begin
        if rst_n = '0' then
            r_sync <= (others => '0');
        elsif rising_edge(clk) then
            r_sync <= r_sync(r_sync'high-1 downto 0) & '1';
        end if;
    end process;

    rst_sync_n <= r_sync(r_sync'high);

end RTL;