--------------------------------------
-- Laatta GPU
-- Geometry Fetch IP Top
-- Author: Jesse Oinonen
--------------------------------------
library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

library work;
use work.laatta_pkg.all;

entity geometry_fetch is
    port ( clk_in           : in  std_logic;
           rst_n            : in  std_logic;
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
           -- AXI stream signals
           -- TBD NOT IMPLEMENTED
           -- Control signals
           start            : in  std_logic  -- Start pulse to begin fetching a draw descriptor, index buffer and vertex buffer.
        );
end geometry_fetch;

architecture RTL of geometry_fetch is
    type ar_state_t is (
        IDLE,
        DESC,
        INDEX,
        VERTEX
    );
    signal arstate    : ar_state_t;

    signal rdata_int   : std_logic_vector(C_AXI_DATA_W-1 downto 0); -- internal read data
    signal rdata_err   : std_logic; -- internal error flag for read data channe
    signal busy        : std_logic; -- internal busy flag
begin

    cg_inst : entity work.cg
        port map (
            clk     => clk_in,
            en      => busy,
            clk_out => clk
        );

    r_channel : process(clk, rst_n)
    begin
        if rst_n = '0' then
            rdata_int  <= (others => '0');
        elsif rising_edge(clk) then
            if rresp /= RESP_OKAY then
                rdata_err <= '1';
            elsif rvalid = '1' and rready = '1' then
                rdata_int <= rdata;
            end if;
        end if;
    end process r_channel;

    ---------------------------------------
    -- sequencer for read address generation
    sequencer : process(clk, rst_n)
    begin
        if rst_n = '0' then
            araddr  <= (others => '0');
            arvalid <= '0';
            arsize  <= (others => '0');
            arburst <= (others => '0');
            arlen   <= (others => '0');
            arstate     <= IDLE;
            arready     <= '0';
            rready      <= '0';
        elsif rising_edge(clk) then
            case arstate is
                when DESC =>
                    araddr  <= std_logic_vector(CMD_BASE); -- Base address for descriptor
                    arvalid <= '1';
                    arsize  <= AXSIZE_8B; -- 64-bit beat size
                    arburst <= AXBURST_INCR; -- Incrementing burst
                    arlen   <= std_logic_vector(to_unsigned(DESC_BEATS - 1, 8)); -- Number of beats for descriptor
                    arstate <= INDEX;
                when INDEX =>

                when VERTEX =>

--                    if rlast and vrtx_beat_cnt = x then
--                        arvalid <= '0';
--                    end if;
                when others => -- IDLE
                    if start = '1' then
                        arstate <= DESC;
                        busy    <= '1';
                    end if;
                    rready <= '0';
                    busy   <= '0';
            end case;      
        end if;
    end process sequencer;

end RTL;