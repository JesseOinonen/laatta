--------------------------------------
-- Laatta GPU Top Module
-- Author: Jesse Oinonen
--------------------------------------
library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

library work;
use work.laatta_pkg.all;

entity laatta_gpu_top is
    port ( clk              : in  std_logic;
           rst_n_in         : in  std_logic;
           -- AXI4 READ ADDRESS CHANNEL
           araddr           : out std_logic_vector(C_AXI_ADDR_W-1 downto 0);
           arvalid          : out std_logic;
           arready          : in  std_logic;
           arsize           : out std_logic_vector(2 downto 0);
           arburst          : out std_logic_vector(1 downto 0);
           arlen            : out std_logic_vector(7 downto 0);
           -- AXI4 READ DATA CHANNEL
           rdata            : in  std_logic_vector(C_AXI_DATA_W-1 downto 0);
           rvalid           : in  std_logic;
           rready           : out std_logic;
           rlast            : in  std_logic;
           rresp            : in  std_logic_vector(1 downto 0);
           -- Control signals
           start            : in  std_logic  -- Start pulse to begin fetching a draw descriptor, index buffer and vertex buffer.
           -- TBD NOT IMPLEMENTED
        );
end laatta_gpu_top;

architecture RTL of laatta_gpu_top is
    signal rst_n     : std_logic;

    -- AXI-Stream from geometry fetch module
    signal tdata_gf  : std_logic_vector(C_AXIS_DATA_W-1 downto 0);
    signal tvalid_gf : std_logic;
    signal tready_gf : std_logic;
    signal tlast_gf  : std_logic;

    -- AXI-Stream from clipping & culling module
    signal tdata_cc  : std_logic_vector(C_AXIS_DATA_W-1 downto 0);
    signal tvalid_cc : std_logic;
    signal tready_cc : std_logic;
    signal tlast_cc  : std_logic;
begin

    rst_n_sync_inst : entity work.rst_n_sync
        generic map ( C_SYNC_DEPTH => 2 )
        port map (
            clk         => clk,
            rst_n       => rst_n_in,
            rst_sync_n  => rst_n
        );

    geometry_fetch_inst : entity work.geometry_fetch
        port map (
            clk_in      => clk,
            rst_n       => rst_n,
            araddr      => araddr,
            arvalid     => arvalid,
            arready     => arready,
            arsize      => arsize,
            arburst     => arburst,
            arlen       => arlen,
            rdata       => rdata,
            rvalid      => rvalid,
            rready      => rready,
            rlast       => rlast,
            rresp       => rresp,
            tdata       => tdata_gf,
            tvalid      => tvalid_gf,
            tready      => tready_gf,
            tlast       => tlast_gf,
            start       => start
        );

    clip_cull_inst : entity work.clip_cull
        port map (
            clk_in      => clk,
            rst_n       => rst_n,
            tdata_in    => tdata_gf,
            tvalid_in   => tvalid_gf,
            tready_in   => tready_gf,
            tlast_in    => tlast_gf,
            tdata_out   => tdata_cc,
            tvalid_out  => tvalid_cc,
            tready_out  => tready_cc,
            tlast_out   => tlast_cc,
            start_out   => open
        );

end RTL;