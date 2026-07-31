--------------------------------------
-- Laatta GPU
-- Vertex shading module
-- Author: Jesse Oinonen
--------------------------------------
library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

library work;
use work.laatta_pkg.all;

entity vertex_shader is
    port ( clk_in       : in  std_logic;
           rst          : in  std_logic;
           -- AXI stream input signals
           tdata_in     : in  std_logic_vector(C_AXIS_DATA_W-1 downto 0);
           tvalid_in    : in  std_logic;
           tready_in    : out std_logic;
           tlast_in     : in  std_logic;
           -- AXI stream output signals
           tdata_out    : out std_logic_vector(C_AXIS_DATA_W-1 downto 0);
           tvalid_out   : out std_logic;
           tready_out   : in  std_logic;
           tlast_out    : out std_logic;
           -- Control signals
           mvp_matrix   : in  std_logic_vector(511 downto 0);
           model_matrix : in  std_logic_vector(511 downto 0);
           light_dir    : in  std_logic_vector( 95 downto 0);
           start        : in  std_logic  -- Start pulse
        );
end vertex_shader;

architecture RTL of vertex_shader is
    signal clk  : std_logic;
    signal busy : std_logic;
    signal done : std_logic;
begin

    process(clk_in, rst_n)
    begin
        if rst_n = '0' then
            busy <= '0';
        elsif rising_edge(clk_in) then
            if start = '1' then
                busy <= '1';
            elsif done = '1' then
                busy <= '0';
            end if;
        end if;
    end process;

    
    cg_inst : entity work.cg
        port map (
            clk     => clk_in,
            en      => busy,
            clk_out => clk
        );

    
        
end RTL;