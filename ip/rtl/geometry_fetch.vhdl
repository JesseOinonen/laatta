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
    port ( clk              : in  std_logic;
           rst_n            : in  std_logic;
           -- AXI4 READ ADDRESS CHANNEL
           araddr           : out std_logic_vector(C_AXI_ADDR_W-1 downto 0);
           arvalid          : out std_logic;
           arready          : in  std_logic;
           arsize           : out std_logic_vector(2 downto 0);
           arburst          : out std_logic_vector(1 downto 0);
           arlen            : out std_logic_vector(7 downto 0);
           arid             : out std_logic_vector(3 downto 0);  -- TBD NOT IMPLEMENTED
           -- AXI4 READ DATA CHANNEL
           rdata            : in  std_logic_vector(C_AXI_DATA_W-1 downto 0);
           rvalid           : in  std_logic;
           rready           : out std_logic;
           rlast            : in  std_logic;
           rresp            : in  std_logic_vector(1 downto 0);
           rid              : in  std_logic_vector(3 downto 0);  -- TBD NOT IMPLEMENTED
           -- Control signals
           start            : in  std_logic
        );
end geometry_fetch;

architecture RTL of geometry_fetch is
    type ar_state_t is (
        DONE,
        DESC,
        INDEX,
        VERTEX
    );
    signal arstate    : ar_state_t := DONE;

    signal araddr_int  : std_logic_vector(C_AXI_ADDR_W-1 downto 0); -- internal read address
    signal arvalid_int : std_logic; -- internal read address valid
    signal arsize_int  : std_logic_vector(2 downto 0); -- internal read size
    signal arburst_int : std_logic_vector(1 downto 0); -- internal read burst type
    signal arlen_int   : std_logic_vector(7 downto 0); -- internal read burst length
    signal rdata_int   : std_logic_vector(C_AXI_DATA_W-1 downto 0); -- internal read data
    signal rdata_err   : std_logic := '0'; -- internal error flag for read data channe
    signal rdone       : std_logic := '0'; -- internal flag for read data channel done

    signal axi_active  : std_logic; -- active signal for AXI4 read so it has time to finish the previous read operation before clock gate is enabled
    signal axi4_state  : axi4_state_t;
begin
    
    axi4_read_inst : entity work.axi4_read
        generic map ( C_AXI_ADDR_W => C_AXI_ADDR_W,
                      C_AXI_DATA_W => C_AXI_DATA_W )
        port map (
            clk_in      => clk,
            rst_n       => rst_n,
            ce          => axi_active,
            araddr      => araddr,
            arvalid     => arvalid,
            arready     => arready,
            arsize      => arsize,
            arburst     => arburst,
            arlen       => arlen,
            arid        => arid,
            rdata       => rdata,
            rvalid      => rvalid,
            rready      => rready,
            rlast       => rlast,
            rresp       => rresp,
            rid         => rid,
            araddr_int  => araddr_int,
            arvalid_int => arvalid_int,
            arsize_int  => arsize_int,
            arburst_int => arburst_int,
            arlen_int   => arlen_int,
            rdata_int   => rdata_int,
            rdata_err   => rdata_err,
            rdone       => rdone,
            axi4_state  => axi4_state
        );

    ---------------------------------------
    -- sequencer for read address generation
    -- Current design without ARID/RID relys on
    -- rdone to indicate that read operation is
    -- complete and new AR signals can be generated.
    sequencer : process(clk, rst_n)
    begin
        if rst_n = '0' then
            araddr_int  <= (others => '0');
            arsize_int  <= (others => '0');
            arburst_int <= (others => '0');
            arlen_int   <= (others => '0');
            arstate     <= DONE;
            axi_active  <= '0';
        elsif rising_edge(clk) then
            if axi4_state = IDLE then -- enable AXI4 read FSM only when in idle state
                axi_active <= start;
                case arstate is
                    when DESC =>
                        araddr_int  <= std_logic_vector(CMD_BASE); -- Base address for descriptor
                        arvalid_int <= '1';
                        arsize_int  <= AXSIZE_8B; -- 64-bit beat size
                        arburst_int <= AXBURST_INCR; -- Incrementing burst
                        arlen_int   <= std_logic_vector(to_unsigned(DESC_BEATS - 1, 8)); -- Number of beats for descriptor
                        arstate     <= INDEX;
                    when INDEX =>

                    when VERTEX =>

                    when others => -- DONE
                        arstate <= DESC;
                end case;      
            end if;
        end if;
    end process sequencer;

end RTL;